// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Auto-scroll driven by the pointer during a scrolling capture: once switched
/// on, the further the pointer goes past where it was (down, or right for a
/// sideways capture), the faster the page scrolls; brought back, it slows, and
/// stops at the start line. Pure arithmetic, fed the pointer's position.
enum ForkCursorScroll {
    /// How far the pointer moves before anything scrolls, so a hand at rest
    /// does not creep.
    static let deadZone: CGFloat = 6

    /// How far past the start line the pointer is, in points: down for a
    /// capture that goes down, right for one that goes sideways. AppKit
    /// coordinates, y upward. Negative when it is back above or left of it.
    static func distance(from start: CGPoint, to pointer: CGPoint, horizontal: Bool) -> CGFloat {
        horizontal ? pointer.x - start.x : start.y - pointer.y
    }

    /// Points per second for a distance past the start line: gentle near it,
    /// quicker further on, never above `maxSpeed`.
    static func speed(distance: CGFloat, maxSpeed: CGFloat) -> CGFloat {
        guard distance.isFinite, maxSpeed > 0 else { return 0 }
        let past = distance - deadZone
        guard past > 0 else { return 0 }
        return min(maxSpeed, 3 * past + 0.02 * past * past)
    }

    /// The fastest scrolling the assembly keeps up with. It joins two pictures
    /// in a row only when they overlap; it takes one every 0.1 to 0.3 s, so at
    /// one and a half areas a second the page moves less than half the area
    /// between two pictures, however slow the Mac.
    static func maxSpeed(areaLength: CGFloat) -> CGFloat {
        guard areaLength.isFinite, areaLength > 0 else { return 0 }
        return max(120, areaLength * 1.5)
    }

    /// The speed eased toward the one the pointer asks for, so a sudden move
    /// of the hand does not jolt the page.
    struct Smoother: Equatable {
        /// About how long the speed takes to follow the pointer.
        static let timeConstant: TimeInterval = 0.12
        private(set) var current: CGFloat = 0

        mutating func next(target: CGFloat, interval: TimeInterval) -> CGFloat {
            guard target.isFinite, interval > 0 else { return current }
            current += (target - current) * CGFloat(min(1, interval / Self.timeConstant))
            // Back at the start line, it stops instead of creeping on.
            if target == 0, current < 1 { current = 0 }
            return current
        }
    }

    /// Whole points to scroll on each tick, the fractions carried over so a
    /// slow speed still moves.
    struct Accumulator: Equatable {
        private(set) var carried: Double = 0

        mutating func step(speed: CGFloat, interval: TimeInterval) -> Int32 {
            guard speed > 0, interval > 0, speed.isFinite else {
                carried = 0
                return 0
            }
            carried += Double(speed) * interval
            let whole = carried.rounded(.down)
            carried -= whole
            return Int32(min(whole, 2_000))
        }
    }

    /// Where the capture's controls sit: centred above the area, or inside
    /// its top edge when there is no room above. Never under it: the pointer
    /// starts on them and goes down over the page to scroll it. AppKit
    /// coordinates (y upward), kept inside the display.
    static func controlsFrame(size: CGSize, area: CGRect, screen: CGRect, gap: CGFloat = 12) -> CGRect {
        let x = min(max(area.midX - size.width / 2, screen.minX + 8), screen.maxX - 8 - size.width)
        let above = area.maxY + gap
        let y = above + size.height <= screen.maxY - 8 ? above : min(area.maxY, screen.maxY) - gap - size.height
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
