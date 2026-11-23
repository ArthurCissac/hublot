// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// How a window capture comes out: as upstream takes it (the window alone,
/// no shadow), with a drop shadow on a transparent background, or set on the
/// background last chosen in the screenshot editor. Pure geometry and choices.
enum ForkWindowCaptureStyle {
    enum Mode: String, CaseIterable {
        case plain, shadow, backdrop
    }

    /// Upstream's selection hands a window over as a plain picture, like an
    /// area. It says, from one line, that a window was just clicked; the
    /// screenshot tool takes the note when the picture reaches it, a moment
    /// later. A note left unread, by a window sent to text recognition, goes
    /// stale before it could be mistaken for the next capture's.
    private static var windowCapturedAt: Date?
    static let noteLifetime: TimeInterval = 3

    static func markWindowCapture(at date: Date = Date()) {
        windowCapturedAt = date
    }

    /// Whether the picture arriving now is the window just clicked. Read once.
    static func takeWindowCaptureNote(at date: Date = Date()) -> Bool {
        defer { windowCapturedAt = nil }
        guard let marked = windowCapturedAt else { return false }
        let age = date.timeIntervalSince(marked)
        return age >= 0 && age <= noteLifetime
    }

    static func mode(stored: String?) -> Mode {
        stored.flatMap(Mode.init(rawValue:)) ?? .shadow
    }

    /// Room around the window for its shadow, in points: more below, where a
    /// window's shadow falls, than above.
    static let sideMargin: CGFloat = 36
    static let topMargin: CGFloat = 24
    static let bottomMargin: CGFloat = 52
    static let shadowBlur: CGFloat = 30
    static let shadowDrop: CGFloat = 12
    static let shadowOpacity: CGFloat = 0.45

    /// The picture with its shadow, in pixels, and where the window sits in
    /// it (origin at the bottom left, as Core Graphics draws).
    static func shadowLayout(windowSize: CGSize, scale: CGFloat) -> (canvas: CGSize, window: CGRect) {
        let factor = scale.isFinite && scale > 0 ? scale : 1
        let side = (sideMargin * factor).rounded()
        let top = (topMargin * factor).rounded()
        let bottom = (bottomMargin * factor).rounded()
        let canvas = CGSize(width: windowSize.width + 2 * side, height: windowSize.height + top + bottom)
        return (canvas, CGRect(x: side, y: bottom, width: windowSize.width, height: windowSize.height))
    }
}
