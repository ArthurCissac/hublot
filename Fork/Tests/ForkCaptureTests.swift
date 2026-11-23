// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// What the fork adds to the capture rules: the desktop icons stay out of
/// screenshots, and only out of screenshots.
enum ForkCaptureTests {
    static func run(_ suite: TestSuite) {
        desktopIconExclusion(suite)
        preference(suite)
        sound(suite)
    }

    private static func sound(_ suite: TestSuite) {
        let key = DefaultsKey.forkScreenshotCaptureSound
        suite.expect(key.hasPrefix("fork"), "the capture sound preference carries the fork prefix")
        suite.expect(Defaults.registeredDefaults[key] as? Bool == true, "captures make a sound by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(key),
               "the capture sound preference travels in backups")

        let suiteName = "fork-capture-sound-tests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "a scratch preferences domain is available")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        suite.expect(!ForkCaptureSound.isEnabled(in: defaults),
               "an unregistered domain reads the sound as off: the default comes from the registration")
        defaults.set(true, forKey: key)
        suite.expect(ForkCaptureSound.isEnabled(in: defaults), "the sound follows its preference")

        suite.expect(FileManager.default.fileExists(atPath: ForkCaptureSound.systemSoundPath),
               "this macOS still ships its screen-capture sound where the fork reads it")
    }

    private static func desktopIconExclusion(_ suite: TestSuite) {
        let iconLayer = ForkCapturePolicy.desktopIconLayer
        let finder = ForkCapturePolicy.finderBundleID
        let windows: [ForkCapturePolicy.Window] = [
            .init(id: 1, ownerBundleID: finder, layer: iconLayer),                    // icons, first display
            .init(id: 2, ownerBundleID: finder, layer: iconLayer),                    // icons, second display
            .init(id: 3, ownerBundleID: finder, layer: 0),                            // a Finder window
            .init(id: 4, ownerBundleID: "com.apple.dock", layer: iconLayer - 20),     // the wallpaper
            .init(id: 5, ownerBundleID: "com.example.backdrop", layer: iconLayer),    // another app, same level
            .init(id: 6, ownerBundleID: nil, layer: iconLayer),                       // no known owner
        ]

        suite.expect(ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: true, isReading: false, windows: windows) == [1, 2],
               "a picture leaves out the Finder's icon window on every display, and nothing else")
        suite.expect(ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: false, isReading: false, windows: windows).isEmpty,
               "with the preference off the icons stay in the picture")
        suite.expect(ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: true, isReading: true, windows: windows).isEmpty,
               "a reading of the screen keeps the icons: a file landing on the desktop is a change")
        suite.expect(ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: true, isReading: false, windows: []).isEmpty,
               "no window, nothing to leave out")

        // The level alone is not enough: whatever another app shows at the icon
        // level is part of the desktop the user sees, and stays in the picture.
        let othersOnly = windows.filter { $0.ownerBundleID != finder }
        suite.expect(ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: true, isReading: false, windows: othersOnly).isEmpty,
               "only the Finder's windows count as desktop icons")

        // The owner alone is not enough either: a Finder window is a window.
        suite.expect(!ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: true, isReading: false, windows: windows).contains(3),
               "an ordinary Finder window stays in the picture")

        // A caller that names another level gets that level, so the rule can
        // be pinned without depending on the running system's constant.
        suite.expect(ForkCapturePolicy.desktopIconWindowIDs(
            excludesDesktopIcons: true, isReading: false, windows: windows, iconLayer: 0) == [3],
               "the level compared against is the one passed in")

        let desktopLayer = Int(CGWindowLevelForKey(.desktopWindow))
        let normalLayer = Int(CGWindowLevelForKey(.normalWindow))
        suite.expect(iconLayer > desktopLayer && iconLayer < normalLayer,
               "the icon level sits above the wallpaper and below ordinary windows")
    }

    private static func preference(_ suite: TestSuite) {
        let key = DefaultsKey.forkScreenshotExcludeDesktopIcons
        suite.expect(key.hasPrefix("fork"), "fork keys carry the fork prefix")
        suite.expect(Defaults.registeredDefaults[key] as? Bool == true,
               "screenshots leave the desktop icons out by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(key),
               "the desktop icons preference travels in backups")
        suite.expect(SettingsBackupSupport.valueLooksRight(key, false)
            && !SettingsBackupSupport.valueLooksRight(key, "no"),
               "a backup can only restore the desktop icons preference as a switch")
    }
}
