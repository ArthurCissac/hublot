// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The scrolling capture's live preview: a column beside the area showing
/// the picture assembled so far. It starts at the bottom of the area and grows
/// upward, then shrinks the picture to fit. Pure geometry, AppKit coordinates
/// (y upward).
enum ForkScrollingPreviewLayout {
    /// The column's width, in points.
    static let width: CGFloat = 140
    static let gap: CGFloat = 12
    /// Between the column's edge and the picture.
    static let inset: CGFloat = 6
    /// The column's height before any picture comes.
    static let emptyHeight: CGFloat = 44

    /// The room the column may take: right of the area, left of it when the
    /// right has no room, otherwise against the area's right edge (over the
    /// page, but kept out of the picture). As tall as the area, inside the display.
    static func slot(area: CGRect, screen: CGRect) -> CGRect {
        let x: CGFloat
        if area.maxX + gap + width <= screen.maxX - 8 {
            x = area.maxX + gap
        } else if area.minX - gap - width >= screen.minX + 8 {
            x = area.minX - gap - width
        } else {
            x = max(area.minX, min(area.maxX, screen.maxX) - gap - width)
        }
        let bottom = max(area.minY, screen.minY + 8)
        let top = max(bottom + emptyHeight, min(area.maxY, screen.maxY - 8))
        return CGRect(x: x.rounded(), y: bottom.rounded(), width: width, height: (top - bottom).rounded())
    }

    /// The column and, inside it, the picture, for an assembled picture of
    /// `content` (any unit). The picture takes the column's width while it
    /// fits its height; past that it shrinks, centred. The column grows from
    /// the slot's bottom. `image` is relative to `column`, from its bottom left.
    static func frames(content: CGSize, slot: CGRect) -> (column: CGRect, image: CGRect) {
        let innerWidth = max(0, slot.width - 2 * inset)
        let innerHeight = max(0, slot.height - 2 * inset)
        guard content.width > 0, content.height > 0, innerWidth > 0, innerHeight > 0 else {
            return (CGRect(x: slot.minX, y: slot.minY, width: slot.width, height: min(emptyHeight, slot.height)), .zero)
        }
        var scale = innerWidth / content.width
        if content.height * scale > innerHeight { scale = innerHeight / content.height }
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        let column = CGRect(x: slot.minX, y: slot.minY, width: slot.width,
                            height: max(min(emptyHeight, slot.height), size.height + 2 * inset))
        let image = CGRect(x: (slot.width - size.width) / 2, y: column.height - inset - size.height,
                           width: size.width, height: size.height)
        return (column, image)
    }

    /// How tall each strip is drawn, from the top, for strips of these heights
    /// in a picture `height` points tall.
    static func stripHeights(_ heights: [CGFloat], filling height: CGFloat) -> [CGFloat] {
        let total = heights.reduce(0, +)
        guard total > 0 else { return heights.map { _ in 0 } }
        return heights.map { $0 / total * height }
    }
}

/// Hands each picture the scrolling capture assembles to its live preview.
/// Upstream's capture loop calls `send` at two lines; the preview sets the
/// receiver while it is shown. No receiver, nothing happens: that is the
/// case with the setting off, and in the test harness. Called from the
/// capture loop, set from the main thread: a lock keeps the two apart.
enum ForkScrollingPreviewFeed {
    private static let lock = NSLock()
    private static var receiver: (([CGImage]) -> Void)?

    static func setReceiver(_ new: (([CGImage]) -> Void)?) {
        lock.lock()
        receiver = new
        lock.unlock()
    }

    static func send(_ slices: [CGImage]) {
        lock.lock()
        let current = receiver
        lock.unlock()
        current?(slices)
    }
}
