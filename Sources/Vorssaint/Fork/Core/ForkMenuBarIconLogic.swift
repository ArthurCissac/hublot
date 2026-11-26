// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics

/// The Hublot icon cut to its ink (`ForkMenuBarIconTrim`). Pure.
enum ForkMenuBarIconLogic {
    /// The part of the canvas kept: the ink's width plus `margin` on each
    /// side, within the canvas, at full height.
    static func trimmedRect(ink: CGRect, canvas: CGSize, margin: CGFloat) -> CGRect {
        let minX = max(0, ink.minX - margin)
        let maxX = min(canvas.width, ink.maxX + margin)
        guard maxX > minX else { return CGRect(origin: .zero, size: canvas) }
        return CGRect(x: minX, y: 0, width: maxX - minX, height: canvas.height)
    }
}
