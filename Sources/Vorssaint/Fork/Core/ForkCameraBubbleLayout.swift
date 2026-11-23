// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Where the camera bubble goes, its shapes and its sizes: a live picture of
/// the person recording, shown inside the recorded area so it ends up in the
/// video. Pure geometry and choices, in AppKit coordinates (origin at the
/// bottom left).
enum ForkCameraBubbleLayout {
    enum Shape: String, CaseIterable {
        case circle, square, rectangle

        /// Width over height: the rectangle is a landscape 16:9.
        var aspect: CGFloat { self == .rectangle ? 16.0 / 9.0 : 1 }

        /// The shape a click on the recording bar's item moves to.
        var next: Shape {
            let all = Shape.allCases
            return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
        }
    }

    /// A bubble's size is its height in points: the circle's diameter.
    static let defaultSize: CGFloat = 160
    static let smallestSize: CGFloat = 60
    static let largestSize: CGFloat = 480
    /// From the area's edges to the bubble.
    static let margin: CGFloat = 16
    /// The corners of the square and of the rectangle.
    static let cornerRadius: CGFloat = 14
    /// How far inside its border a press resizes the bubble instead of moving it.
    static let edgeBand: CGFloat = 14

    static func shape(stored: String?) -> Shape {
        stored.flatMap(Shape.init(rawValue:)) ?? .circle
    }

    /// The remembered size, kept between the smallest and the largest; the
    /// default one for a value that is no size at all.
    static func size(stored: Double) -> CGFloat {
        guard stored.isFinite, stored > 0 else { return defaultSize }
        return min(max(CGFloat(stored), smallestSize), largestSize)
    }

    static func bubbleSize(shape: Shape, height: CGFloat) -> CGSize {
        CGSize(width: (height * shape.aspect).rounded(), height: height.rounded())
    }

    static func cornerRadius(shape: Shape, height: CGFloat) -> CGFloat {
        shape == .circle ? height / 2 : min(cornerRadius, height / 4)
    }

    /// The bubble's frame for an area: its bottom right corner, at the
    /// remembered size where the area has room for it, smaller in a small
    /// area, and always inside the display.
    static func frame(shape: Shape, size: CGFloat, in area: CGRect, screen: CGRect) -> CGRect {
        let room = min(area.height - 2 * margin, (area.width - 2 * margin) / shape.aspect)
        let bubble = bubbleSize(shape: shape, height: min(size, max(smallestSize, room)))
        let origin = CGPoint(x: area.maxX - margin - bubble.width, y: area.minY + margin)
        return held(CGRect(origin: origin, size: bubble), inside: screen.insetBy(dx: margin, dy: margin))
    }

    /// The frame after a resize by `factor`, around its center. The shape's
    /// proportions are kept, the size stays between the smallest and what the
    /// display can show, and the result is moved back inside the display.
    static func scaled(_ frame: CGRect, shape: Shape, by factor: CGFloat, within screen: CGRect) -> CGRect {
        guard factor.isFinite, factor > 0, frame.height > 0 else { return frame }
        let largest = max(smallestSize, min(largestSize, screen.height, screen.width / shape.aspect))
        let bubble = bubbleSize(shape: shape, height: min(max(frame.height * factor, smallestSize), largest))
        let origin = CGPoint(x: frame.midX - bubble.width / 2, y: frame.midY - bubble.height / 2)
        return held(CGRect(origin: origin, size: bubble), inside: screen)
    }

    /// The same bubble in another shape: same height, same center.
    static func reshaped(_ frame: CGRect, to shape: Shape, within screen: CGRect) -> CGRect {
        scaled(frame, shape: shape, by: 1, within: screen)
    }

    /// Whether a press at `point`, in the bubble's own coordinates, takes hold
    /// of its border. That resizes the bubble; a press anywhere else moves it.
    /// The corners a circle leaves empty count as its border.
    static func isOnEdge(_ point: CGPoint, in size: CGSize, shape: Shape) -> Bool {
        let band = min(edgeBand, size.height / 4)
        switch shape {
        case .circle:
            return hypot(point.x - size.width / 2, point.y - size.height / 2) >= size.height / 2 - band
        case .square, .rectangle:
            return point.x < band || point.y < band || point.x > size.width - band || point.y > size.height - band
        }
    }

    /// What a drag from the border asks for: how far the pointer now is from
    /// the bubble's center, over how far it was when the drag began. The
    /// border then stays under the pointer.
    static func resizeFactor(from start: CGPoint, to current: CGPoint, center: CGPoint) -> CGFloat {
        let before = hypot(start.x - center.x, start.y - center.y)
        guard before > 1 else { return 1 }
        return hypot(current.x - center.x, current.y - center.y) / before
    }

    private static func held(_ frame: CGRect, inside bounds: CGRect) -> CGRect {
        let x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
        let y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
        return CGRect(x: x.rounded(), y: y.rounded(), width: frame.width, height: frame.height)
    }
}
