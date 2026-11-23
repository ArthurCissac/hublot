// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Which display lies a given way from another, as Swish moves windows: by
/// where the displays sit in the Displays settings, not by their order.
enum ForkSwishDisplays {
    typealias Direction = ForkTitleBarGestureLogic.Direction

    /// The display `toward` from `current`, among `displays` (AppKit frames,
    /// y up): the nearest one whose center lies within 60° of that direction.
    /// Nil for a diagonal, or when no display lies that way.
    static func neighbor(of current: CGRect, toward direction: Direction, among displays: [CGRect]) -> Int? {
        let unit: CGVector
        switch direction {
        case .right: unit = CGVector(dx: 1, dy: 0)
        case .left: unit = CGVector(dx: -1, dy: 0)
        case .up: unit = CGVector(dx: 0, dy: 1)
        case .down: unit = CGVector(dx: 0, dy: -1)
        default: return nil
        }
        var best: (index: Int, distance: CGFloat)?
        for (index, display) in displays.enumerated() where display != current {
            let dx = display.midX - current.midX, dy = display.midY - current.midY
            let distance = hypot(dx, dy)
            guard distance > 0, (dx * unit.dx + dy * unit.dy) / distance >= 0.5 else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// One cell of a 3×3 grid over a visible area in Accessibility
    /// coordinates (y downward), so row 0 is the top row. Cells share their
    /// edges exactly: the last one in each line takes the rounding.
    static func ninth(column: Int, row: Int, in visible: CGRect) -> CGRect {
        let column = max(0, min(2, column)), row = max(0, min(2, row))
        func edge(_ index: Int, _ start: CGFloat, _ length: CGFloat) -> CGFloat {
            (start + length * CGFloat(index) / 3).rounded()
        }
        let minX = edge(column, visible.minX, visible.width), maxX = edge(column + 1, visible.minX, visible.width)
        let minY = edge(row, visible.minY, visible.height), maxY = edge(row + 1, visible.minY, visible.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// An AppKit rectangle (origin at the bottom left of the primary display)
    /// in the coordinates Accessibility uses (origin at its top left).
    static func accessibilityRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where a window goes on another display: the same place relative to the
    /// visible area, shrunk only if it does not fit. All in one coordinate space.
    static func frame(_ window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return window }
        let width = min(window.width, destination.width)
        let height = min(window.height, destination.height)
        let fx = source.width > window.width ? (window.minX - source.minX) / (source.width - window.width) : 0
        let fy = source.height > window.height ? (window.minY - source.minY) / (source.height - window.height) : 0
        let x = destination.minX + max(0, min(1, fx)) * (destination.width - width)
        let y = destination.minY + max(0, min(1, fy)) * (destination.height - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}
