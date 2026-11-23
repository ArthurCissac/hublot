// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The arithmetic behind Swish-style feedback: the frames a window passes
/// through as it glides into place, where the action bubble sits by the
/// pointer, how far a pinch has come, and the place a layout takes on the
/// bubble's small screen.
enum ForkSwishMotion {
    /// How long a window takes to glide to a new place, and in how many steps.
    static let glideDuration: TimeInterval = 0.16
    static let glideSteps = 8

    /// The frames between two places, easing out (fast, then settling), the
    /// last one exactly the destination.
    static func glide(from start: CGRect, to end: CGRect, steps: Int = glideSteps) -> [CGRect] {
        guard steps > 1, start != end else { return [end] }
        return (1...steps).map { step in
            let t = Double(step) / Double(steps)
            let eased = CGFloat(1 - pow(1 - t, 3))
            if step == steps { return end }
            return CGRect(x: start.minX + (end.minX - start.minX) * eased,
                          y: start.minY + (end.minY - start.minY) * eased,
                          width: start.width + (end.width - start.width) * eased,
                          height: start.height + (end.height - start.height) * eased).integral
        }
    }

    /// How far a pinch has come toward acting, from 0 to 1.
    static func pinchProgress(_ magnification: Double, threshold: Double = ForkTitleBarGestureLogic.pinchThreshold) -> Double {
        guard magnification.isFinite, threshold > 0 else { return 0 }
        return min(1, abs(magnification) / threshold)
    }

    /// Where a target sits within the visible area, as fractions of it with
    /// the origin at the top left, for the bubble's small screen. Both
    /// rectangles in AppKit coordinates (y upward).
    static func region(of target: CGRect, in area: CGRect) -> CGRect {
        guard area.width > 0, area.height > 0 else { return .zero }
        let x = (target.minX - area.minX) / area.width
        let y = (area.maxY - target.maxY) / area.height
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGRect(x: x, y: y, width: target.width / area.width, height: target.height / area.height)
            .intersection(unit)
    }

    /// The bubble's origin (AppKit coordinates): up and to the right of the
    /// pointer, kept inside the display, flipped to the other side near an edge.
    static func bubbleOrigin(pointer: CGPoint, size: CGSize, screen: CGRect, gap: CGFloat = 18) -> CGPoint {
        var x = pointer.x + gap
        var y = pointer.y + gap
        if x + size.width > screen.maxX { x = pointer.x - gap - size.width }
        if y + size.height > screen.maxY { y = pointer.y - gap - size.height }
        x = max(screen.minX, min(x, screen.maxX - size.width))
        y = max(screen.minY, min(y, screen.maxY - size.height))
        return CGPoint(x: x, y: y)
    }
}
