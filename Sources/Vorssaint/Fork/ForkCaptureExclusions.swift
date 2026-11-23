// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation
import ScreenCaptureKit

/// Feeds `ForkCapturePolicy` from a live shareable-content snapshot. Called
/// from one line in `ScreenshotCaptureEngine.excludedOwnWindows`, the single
/// place every display capture builds its exclusion list.
enum ForkCaptureExclusions {
    /// Other apps' windows this capture leaves out, resolved against the same
    /// snapshot the capture will use.
    ///
    /// `isReading` marks a capture that watches the screen instead of taking a
    /// picture of it (Watch on the island). A file landing on the desktop is a
    /// change it has to see, so the icons stay in what it reads.
    static func windowIDs(in content: SCShareableContent,
                          isReading: Bool,
                          defaults: UserDefaults = .standard) -> Set<CGWindowID> {
        ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: defaults.bool(forKey: DefaultsKey.forkScreenshotExcludeDesktopIcons),
            isReading: isReading,
            windows: content.windows.map {
                .init(id: $0.windowID,
                      ownerBundleID: $0.owningApplication?.bundleIdentifier,
                      layer: $0.windowLayer)
            })
    }
}
