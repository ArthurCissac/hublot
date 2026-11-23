// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// How a window capture comes out.
enum ForkWindowCaptureTests {
    typealias Style = ForkWindowCaptureStyle

    static func run(_ suite: TestSuite) {
        suite.expect(Style.mode(stored: "plain") == .plain && Style.mode(stored: "backdrop") == .backdrop
            && Style.mode(stored: nil) == .shadow && Style.mode(stored: "glow") == .shadow,
               "the stored style is read back; anything else means the shadow")

        let layout = Style.shadowLayout(windowSize: CGSize(width: 1000, height: 600), scale: 2)
        suite.expect(layout.canvas == CGSize(width: 1000 + 144, height: 600 + 48 + 104),
               "the shadow gets room on every side, more below than above, at the display's scale")
        suite.expect(layout.window == CGRect(x: 72, y: 104, width: 1000, height: 600),
               "the window keeps its own size inside it, raised above the shadow")
        suite.expect(Style.shadowLayout(windowSize: CGSize(width: 10, height: 10), scale: .nan).canvas.width == 10 + 72,
               "a scale that is no number counts as 1")

        // The note that a window was just clicked.
        let now = Date(timeIntervalSince1970: 5_000)
        Style.markWindowCapture(at: now)
        suite.expect(Style.takeWindowCaptureNote(at: now.addingTimeInterval(0.2)),
               "a picture arriving just after a window was clicked is that window")
        suite.expect(!Style.takeWindowCaptureNote(at: now.addingTimeInterval(0.3)),
               "the note is read once: the next capture is not taken for a window")
        Style.markWindowCapture(at: now)
        suite.expect(!Style.takeWindowCaptureNote(at: now.addingTimeInterval(Style.noteLifetime + 1)),
               "a note left unread goes stale")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkWindowCaptureStyle] as? String == "shadow"
            && SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkWindowCaptureStyle),
               "window captures come with their shadow by default, and the choice travels in backups")
    }
}
