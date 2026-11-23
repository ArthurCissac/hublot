// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The area the capture menu frames, once drawn: moved by dragging it,
/// resized from its edges and corners, held to a ratio or set to a fixed
/// size, and remembered for the next time. Pure geometry, in the frame
/// view's own space (points, origin at the display's bottom left), except
/// `region`, which turns an area into what upstream's tools take.
enum ForkCaptureAreaGeometry {
    /// A shape the area can be held to: free, a ratio, or a size in pixels.
    enum Format: Equatable {
        case free
        case ratio(width: CGFloat, height: CGFloat)
        case pixels(width: CGFloat, height: CGFloat)

        /// What the bar shows.
        var label: String? {
            switch self {
            case .free: return nil
            case let .ratio(width, height): return "\(Int(width)):\(Int(height))"
            case let .pixels(width, height): return "\(Int(width))×\(Int(height))"
            }
        }

        /// Width over height, nil when free.
        var aspect: CGFloat? {
            switch self {
            case .free: return nil
            case let .ratio(width, height), let .pixels(width, height):
                return height > 0 ? width / height : nil
            }
        }
    }

    /// One click on the bar's format item moves to the next.
    static let formats: [Format] = [
        .free, .ratio(width: 1, height: 1), .ratio(width: 4, height: 3), .ratio(width: 16, height: 9),
        .ratio(width: 9, height: 16), .pixels(width: 1280, height: 720), .pixels(width: 1920, height: 1080),
    ]

    static func nextFormat(after format: Format) -> Format {
        guard let index = formats.firstIndex(of: format) else { return .free }
        return formats[(index + 1) % formats.count]
    }

    static func format(at index: Int) -> Format {
        formats.indices.contains(index) ? formats[index] : .free
    }

    /// The smallest side an area keeps while it is resized.
    static let minimumSide: CGFloat = 32
    /// How far from an edge a press takes hold of it.
    static let edgeBand: CGFloat = 8

    /// Which edge or corner a press takes hold of.
    struct Handle: Equatable {
        /// -1 for the left edge, 1 for the right one, 0 for neither.
        let horizontal: Int
        /// -1 for the bottom edge, 1 for the top one, 0 for neither.
        let vertical: Int
    }

    /// The pointer over the frame: the ordinary arrow (the crosshair belongs
    /// to drawing an area, which upstream's selection shows), except on an
    /// edge, which shows the way it resizes.
    enum Cursor: Equatable { case arrow, resizeLeftRight, resizeUpDown }

    static func cursor(at point: CGPoint, in area: CGRect) -> Cursor {
        guard let handle = handle(at: point, in: area), handle.horizontal == 0 || handle.vertical == 0 else { return .arrow }
        return handle.horizontal != 0 ? .resizeLeftRight : .resizeUpDown
    }

    /// The handle under a point, nil inside the area (which moves it) or
    /// outside it (which starts a new selection).
    static func handle(at point: CGPoint, in area: CGRect) -> Handle? {
        let outer = area.insetBy(dx: -edgeBand, dy: -edgeBand)
        guard outer.contains(point) else { return nil }
        let horizontal = abs(point.x - area.minX) <= edgeBand ? -1 : abs(point.x - area.maxX) <= edgeBand ? 1 : 0
        let vertical = abs(point.y - area.minY) <= edgeBand ? -1 : abs(point.y - area.maxY) <= edgeBand ? 1 : 0
        guard horizontal != 0 || vertical != 0 else { return nil }
        return Handle(horizontal: horizontal, vertical: vertical)
    }

    /// The area moved by a drag, kept on the display.
    static func moved(_ area: CGRect, by delta: CGSize, within bounds: CGRect) -> CGRect {
        var moved = area.offsetBy(dx: delta.width, dy: delta.height)
        moved.origin.x = min(max(moved.minX, bounds.minX), max(bounds.minX, bounds.maxX - moved.width))
        moved.origin.y = min(max(moved.minY, bounds.minY), max(bounds.minY, bounds.maxY - moved.height))
        return moved.integral
    }

    /// The area with one edge or corner dragged to `point`. The opposite
    /// side stays put; a ratio, or a square with Shift, holds the shape.
    static func resized(_ area: CGRect, handle: Handle, to point: CGPoint, within bounds: CGRect,
                        aspect: CGFloat?, square: Bool) -> CGRect {
        var minX = area.minX, maxX = area.maxX, minY = area.minY, maxY = area.maxY
        let x = min(max(point.x, bounds.minX), bounds.maxX)
        let y = min(max(point.y, bounds.minY), bounds.maxY)
        if handle.horizontal < 0 { minX = min(x, maxX - minimumSide) }
        if handle.horizontal > 0 { maxX = max(x, minX + minimumSide) }
        if handle.vertical < 0 { minY = min(y, maxY - minimumSide) }
        if handle.vertical > 0 { maxY = max(y, minY + minimumSide) }
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let ratio = square ? 1 : aspect, ratio > 0 else { return rect.integral }
        // The edge dragged leads; the other side follows the ratio, from the fixed corner.
        if handle.vertical == 0 || (handle.horizontal != 0 && rect.width / ratio >= rect.height) {
            rect.size.height = rect.width / ratio
        } else {
            rect.size.width = rect.height * ratio
        }
        if handle.horizontal < 0 { rect.origin.x = maxX - rect.width }
        if handle.vertical < 0 { rect.origin.y = maxY - rect.height }
        if handle.horizontal == 0 { rect.origin.x = area.midX - rect.width / 2 }
        if handle.vertical == 0 { rect.origin.y = area.midY - rect.height / 2 }
        return fitted(rect, aspect: ratio, within: bounds).integral
    }

    /// The area given a format: around its center, as large as before for a
    /// ratio, at the format's size for pixels; never larger than the display.
    static func applying(_ format: Format, to area: CGRect, within bounds: CGRect, scale: CGFloat) -> CGRect {
        var size: CGSize
        switch format {
        case .free:
            return area
        case let .ratio(width, height):
            guard width > 0, height > 0 else { return area }
            // The same surface in the new shape.
            let surface = area.width * area.height
            let h = (surface * height / width).squareRoot()
            size = CGSize(width: h * width / height, height: h)
        case let .pixels(width, height):
            let factor = scale > 0 ? scale : 1
            size = CGSize(width: width / factor, height: height / factor)
        }
        let rect = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        return fitted(rect, aspect: format.aspect, within: bounds).integral
    }

    /// Brought inside the display: scaled down if too large, keeping the
    /// ratio, then moved in.
    static func fitted(_ rect: CGRect, aspect: CGFloat?, within bounds: CGRect) -> CGRect {
        var size = rect.size
        if size.width > bounds.width || size.height > bounds.height {
            let factor = min(bounds.width / max(size.width, 1), bounds.height / max(size.height, 1))
            size = aspect == nil
                ? CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
                : CGSize(width: size.width * factor, height: size.height * factor)
        }
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        if rect.size == size { origin = rect.origin }
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    /// What the frame shows: the area's size in the display's pixels.
    static func sizeLabel(for area: CGRect, scale: CGFloat) -> String {
        let factor = scale > 0 ? scale : 1
        return "\(Int((area.width * factor).rounded())) × \(Int((area.height * factor).rounded()))"
    }

    /// An area of a display, in global Cocoa points, turned into the region
    /// upstream's tools take: whole even pixels inside the display, with the
    /// points recomputed from them, as upstream's selection does.
    static func region(anchor: CGRect, screenFrame: CGRect, displayID: CGDirectDisplayID,
                       scale: CGFloat) -> RecorderSupport.Region {
        let factor = scale > 0 ? scale : 1
        let display = CGRect(x: 0, y: 0, width: screenFrame.width * factor, height: screenFrame.height * factor)
        let raw = CGRect(x: (anchor.minX - screenFrame.minX) * factor,
                         y: (screenFrame.maxY - anchor.maxY) * factor,
                         width: anchor.width * factor, height: anchor.height * factor)
        let pixels = RecorderSupport.snappedPixelRect(raw, in: display)
        let points = CGRect(x: screenFrame.minX + pixels.minX / factor,
                            y: screenFrame.maxY - (pixels.minY + pixels.height) / factor,
                            width: pixels.width / factor, height: pixels.height / factor)
        return RecorderSupport.Region(displayID: displayID, windowID: nil, pixelRect: pixels,
                                      anchorRect: points, scale: factor)
    }

    /// A remembered area, stored as four numbers.
    static func encoded(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(Double($0)) }.joined(separator: ",")
    }

    static func decoded(_ raw: String?) -> CGRect? {
        let parts = (raw ?? "").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, parts.allSatisfy(\.isFinite), parts[2] >= Double(minimumSide), parts[3] >= Double(minimumSide)
        else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Whether an area covers nearly all of a display: no zone worth
    /// remembering, and one that would leave no room beside it to draw another.
    static func isNearlyWholeDisplay(_ area: CGRect, screen: CGRect) -> Bool {
        let covered = area.intersection(screen)
        guard !covered.isNull, screen.width > 0, screen.height > 0 else { return false }
        return covered.width * covered.height >= 0.9 * screen.width * screen.height
    }
}
