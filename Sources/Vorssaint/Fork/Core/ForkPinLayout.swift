// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics

/// The buttons a pinned capture shows under the pointer, and how a pin grows
/// and shrinks. Pure geometry and choices.
enum ForkPinLayout {
    /// What the bar offers, in display order.
    enum Control: CaseIterable {
        case close, restore, edit, save, drag, shrink, enlarge
    }

    static let buttonSize: CGFloat = 24
    static let barPadding: CGFloat = 4
    static let barHeight: CGFloat = 32
    /// From the pin's edges to the bar.
    static let margin: CGFloat = 8
    /// One step of the enlarge and shrink buttons.
    static let zoomStep: CGFloat = 1.25

    static func barWidth(for controls: [Control]) -> CGFloat {
        2 * barPadding + CGFloat(controls.count) * buttonSize
    }

    /// The controls a pin of this width has room for. A pin too narrow for
    /// the whole bar keeps the two that matter then: closing it, and
    /// enlarging it until the rest fits.
    static func controls(forPinWidth width: CGFloat) -> [Control] {
        let all = Control.allCases
        if barWidth(for: all) + 2 * margin <= width { return all }
        let compact: [Control] = [.close, .enlarge]
        return barWidth(for: compact) + 2 * margin <= width ? compact : []
    }

    /// A pin's frame after one zoom step, grown or shrunk around its center.
    /// The proportions are kept; the size stays between the minimum and what
    /// the display can show, and the result is moved back inside the display.
    static func resized(_ frame: CGRect, by factor: CGFloat, minimum: CGSize, within screen: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0, factor > 0 else { return frame }
        let smallest = max(minimum.width / frame.width, minimum.height / frame.height)
        let largest = min(screen.width / frame.width, screen.height / frame.height)
        // Never below the minimum, never past the display. A pin already larger
        // than the display is only ever brought back to it.
        let scale = max(min(factor, max(largest, smallest)), smallest)
        let size = CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        origin.x = min(max(origin.x, screen.minX), max(screen.minX, screen.maxX - size.width))
        origin.y = min(max(origin.y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }
}
