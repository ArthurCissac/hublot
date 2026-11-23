// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics

/// Which windows of *other* apps a screenshot leaves out on the fork's behalf.
///
/// Upstream's `ScreenshotCapturePolicy` only ever excludes the app's own
/// windows. The desktop icons belong to the Finder, so their rule lives here,
/// as pure logic the harness can pin down without a screen.
enum ForkCapturePolicy {
    /// One shareable window, reduced to what the decision reads.
    struct Window: Equatable {
        let id: CGWindowID
        let ownerBundleID: String?
        let layer: Int
    }

    static let finderBundleID = "com.apple.finder"

    /// The window level the Finder draws the desktop icons at. It keeps one
    /// such window per display, transparent apart from the icons.
    static var desktopIconLayer: Int { Int(CGWindowLevelForKey(.desktopIconWindow)) }

    /// The Finder's desktop-icon windows, or none when the preference is off
    /// or the capture is a reading rather than a picture.
    ///
    /// Leaving these windows out of the capture filter removes the icons from
    /// the image only. Nothing changes on screen, so there is nothing to put
    /// back after a cancelled capture or a crash, and whatever sits behind the
    /// icons (the wallpaper, or another app's desktop-level window) is
    /// captured as it is. The owner check keeps in the picture any other
    /// app's window that happens to sit at the same level.
    static func desktopIconWindowIDs(excludesDesktopIcons: Bool,
                                     isReading: Bool,
                                     windows: [Window],
                                     iconLayer: Int = desktopIconLayer) -> Set<CGWindowID> {
        guard excludesDesktopIcons, !isReading else { return [] }
        return Set(windows.lazy
            .filter { $0.ownerBundleID == finderBundleID && $0.layer == iconLayer }
            .map(\.id))
    }
}
