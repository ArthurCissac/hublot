// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The editor's crop, made simpler to handle: grips of a fixed size on
/// screen whatever the zoom, every edge taken along its whole length, aspect
/// ratios, and the thirds while an edge is pulled. Pure geometry. The crop
/// itself is in image pixels; `zoom` is view points per image pixel.
enum ForkCropGeometry {
    typealias Handle = ScreenshotSupport.Handle

    /// How far from a corner a press still takes it, in view points.
    static let cornerZone: CGFloat = 16
    /// How far from an edge a press still takes it, in view points.
    static let edgeZone: CGFloat = 10
    /// The grips as drawn, in view points: a bracket at each corner, a bar
    /// in the middle of each edge, inside the frame.
    static let cornerLength: CGFloat = 20
    static let edgeLength: CGFloat = 26
    static let gripThickness: CGFloat = 4

    /// The grip under `point`: a corner first, then the nearest edge,
    /// anywhere along it. Inside a small crop the zones shrink, so the
    /// middle still moves the crop.
    static func grip(at point: CGPoint, in rect: CGRect, zoom: CGFloat) -> Handle? {
        guard zoom > 0, zoom.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        let inside = rect.contains(point)
        func zone(_ points: CGFloat, across length: CGFloat) -> CGFloat {
            let size = points / zoom
            return inside ? min(size, length / 4) : size
        }
        let cornerX = zone(cornerZone, across: rect.width), cornerY = zone(cornerZone, across: rect.height)
        let corners: [(Handle, CGPoint)] = [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
                                            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
                                            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
                                            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))]
        let nearCorner = corners
            .filter { abs($0.1.x - point.x) <= cornerX && abs($0.1.y - point.y) <= cornerY }
            .min { hypot($0.1.x - point.x, $0.1.y - point.y) < hypot($1.1.x - point.x, $1.1.y - point.y) }
        if let nearCorner { return nearCorner.0 }

        let edgeX = zone(edgeZone, across: rect.width), edgeY = zone(edgeZone, across: rect.height)
        let reachX = edgeZone / zoom, reachY = edgeZone / zoom
        let alongX = point.x >= rect.minX - reachX && point.x <= rect.maxX + reachX
        let alongY = point.y >= rect.minY - reachY && point.y <= rect.maxY + reachY
        let edges: [(Handle, CGFloat, Bool)] = [(.left, abs(point.x - rect.minX), alongY && abs(point.x - rect.minX) <= edgeX),
                                                (.right, abs(point.x - rect.maxX), alongY && abs(point.x - rect.maxX) <= edgeX),
                                                (.top, abs(point.y - rect.minY), alongX && abs(point.y - rect.minY) <= edgeY),
                                                (.bottom, abs(point.y - rect.maxY), alongX && abs(point.y - rect.maxY) <= edgeY)]
        return edges.filter(\.2).min { $0.1 < $1.1 }?.0
    }

    /// The proportions offered, width over height.
    enum Ratio: CaseIterable, Equatable {
        case free, original, square, fourThree, sixteenNine, nineSixteen

        func value(imageSize: CGSize) -> CGFloat? {
            switch self {
            case .free: return nil
            case .original:
                guard imageSize.width > 0, imageSize.height > 0 else { return nil }
                return imageSize.width / imageSize.height
            case .square: return 1
            case .fourThree: return 4.0 / 3
            case .sixteenNine: return 16.0 / 9
            case .nineSixteen: return 9.0 / 16
            }
        }

        /// The name shown for a fixed ratio; free and original are named by the caller.
        var label: String? {
            switch self {
            case .free, .original: return nil
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .sixteenNine: return "16:9"
            case .nineSixteen: return "9:16"
            }
        }
    }

    private static func isCorner(_ handle: Handle) -> Bool {
        [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle)
    }

    /// The crop once `handle` is dragged to `point`, kept to `ratio` and
    /// inside `bounds` when there is a ratio. Without one, edges simply follow,
    /// as upstream's do; the editor then snaps and clamps either result.
    static func resized(_ rect: CGRect, dragging handle: Handle, to point: CGPoint,
                        ratio: CGFloat?, within bounds: CGRect) -> CGRect {
        guard let ratio, ratio > 0, ratio.isFinite else {
            return ScreenshotSupport.resizedRect(rect, dragging: handle, to: point)
        }
        if isCorner(handle) {
            let anchor: CGPoint
            switch handle {
            case .topLeft: anchor = CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight: anchor = CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft: anchor = CGPoint(x: rect.maxX, y: rect.minY)
            default: anchor = CGPoint(x: rect.minX, y: rect.minY)
            }
            return drawn(from: anchor, to: point, ratio: ratio, within: bounds)
        }
        // An edge: its own size follows the pointer, the other one the ratio,
        // centred on the crop's middle.
        let horizontal = handle == .left || handle == .right
        if horizontal {
            let anchorX = handle == .right ? rect.minX : rect.maxX
            let towardRight = handle == .right ? point.x >= anchorX : point.x > anchorX
            let roomX = towardRight ? bounds.maxX - anchorX : anchorX - bounds.minX
            let roomY = 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)
            var width = min(abs(point.x - anchorX), roomX)
            var height = width / ratio
            if height > roomY {
                height = roomY
                width = height * ratio
            }
            return CGRect(x: towardRight ? anchorX : anchorX - width, y: rect.midY - height / 2,
                          width: width, height: height)
        }
        let anchorY = handle == .bottom ? rect.minY : rect.maxY
        let downward = handle == .bottom ? point.y >= anchorY : point.y > anchorY
        let roomY = downward ? bounds.maxY - anchorY : anchorY - bounds.minY
        let roomX = 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
        var height = min(abs(point.y - anchorY), roomY)
        var width = height * ratio
        if width > roomX {
            width = roomX
            height = width / ratio
        }
        return CGRect(x: rect.midX - width / 2, y: downward ? anchorY : anchorY - height,
                      width: width, height: height)
    }

    /// A crop drawn from `origin` to `point`, kept to `ratio` when there is
    /// one and inside `bounds`.
    static func drawn(from origin: CGPoint, to point: CGPoint, ratio: CGFloat?, within bounds: CGRect) -> CGRect {
        let dx = point.x - origin.x, dy = point.y - origin.y
        guard let ratio, ratio > 0, ratio.isFinite else {
            return ScreenshotSupport.selectionRect(from: origin, to: point)
        }
        let roomX = dx >= 0 ? bounds.maxX - origin.x : origin.x - bounds.minX
        let roomY = dy >= 0 ? bounds.maxY - origin.y : origin.y - bounds.minY
        var width = abs(dx), height = abs(dy)
        if width / max(height, 0.0001) > ratio { height = width / ratio } else { width = height * ratio }
        if width > roomX {
            width = max(0, roomX)
            height = width / ratio
        }
        if height > roomY {
            height = max(0, roomY)
            width = height * ratio
        }
        return CGRect(x: dx >= 0 ? origin.x : origin.x - width, y: dy >= 0 ? origin.y : origin.y - height,
                      width: width, height: height)
    }

    /// The largest crop of `ratio` inside `rect`, centred on it; `rect` itself without a ratio.
    static func fitted(ratio: CGFloat?, in rect: CGRect) -> CGRect {
        guard let ratio, ratio > 0, ratio.isFinite, rect.width > 0, rect.height > 0 else { return rect }
        var width = rect.width, height = width / ratio
        if height > rect.height {
            height = rect.height
            width = height * ratio
        }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    /// The lines that cut the crop in thirds, in the crop's own coordinates.
    static func thirds(of rect: CGRect) -> (vertical: [CGFloat], horizontal: [CGFloat]) {
        ([rect.minX + rect.width / 3, rect.minX + 2 * rect.width / 3],
         [rect.minY + rect.height / 3, rect.minY + 2 * rect.height / 3])
    }

    /// The grips as filled rectangles, in view points (y downward), inside
    /// `frame`: two bars per corner, one per edge. Shorter on a small frame.
    static func gripRects(in frame: CGRect) -> [CGRect] {
        guard frame.width > 0, frame.height > 0 else { return [] }
        let t = min(gripThickness, frame.width / 4, frame.height / 4)
        let corner = min(cornerLength, frame.width / 3, frame.height / 3)
        let edgeX = min(edgeLength, frame.width / 3), edgeY = min(edgeLength, frame.height / 3)
        var rects: [CGRect] = []
        for (x, y, right, bottom) in [(frame.minX, frame.minY, false, false), (frame.maxX, frame.minY, true, false),
                                      (frame.minX, frame.maxY, false, true), (frame.maxX, frame.maxY, true, true)] {
            let left = right ? x - corner : x
            let top = bottom ? y - t : y
            rects.append(CGRect(x: left, y: top, width: corner, height: t))
            rects.append(CGRect(x: right ? x - t : x, y: bottom ? y - corner : y, width: t, height: corner))
        }
        rects.append(CGRect(x: frame.midX - edgeX / 2, y: frame.minY, width: edgeX, height: t))
        rects.append(CGRect(x: frame.midX - edgeX / 2, y: frame.maxY - t, width: edgeX, height: t))
        rects.append(CGRect(x: frame.minX, y: frame.midY - edgeY / 2, width: t, height: edgeY))
        rects.append(CGRect(x: frame.maxX - t, y: frame.midY - edgeY / 2, width: t, height: edgeY))
        return rects
    }

    /// The crop's size in pixels, as shown beside it.
    static func sizeLabel(_ rect: CGRect) -> String {
        "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }

    /// Two clicks close together in time and place.
    struct TapTracker: Equatable {
        private var last: (point: CGPoint, time: TimeInterval)?

        static func == (lhs: TapTracker, rhs: TapTracker) -> Bool {
            lhs.last?.point == rhs.last?.point && lhs.last?.time == rhs.last?.time
        }

        /// Whether this click makes a double click with the one before; a
        /// double click is used up, so a third click starts afresh.
        mutating func isDouble(at point: CGPoint, time: TimeInterval, interval: TimeInterval, slop: CGFloat) -> Bool {
            if let last, time - last.time <= interval, time >= last.time,
               hypot(point.x - last.point.x, point.y - last.point.y) <= slop {
                self.last = nil
                return true
            }
            last = (point, time)
            return false
        }

        mutating func reset() { last = nil }
    }
}
