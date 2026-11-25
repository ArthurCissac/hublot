// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The recording options the fork adds: mono sound, and click rings by default.
enum ForkRecorderTests {
    static func run(_ suite: TestSuite) {
        suite.expect(ForkRecorderOptions.channelCount(mono: true) == 1
            && ForkRecorderOptions.channelCount(mono: false) == 2,
               "mono is one channel, the rest is stereo")

        let suiteName = "fork-recorder-tests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "a scratch preferences domain is available")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        // Where nothing is registered (the harness, upstream's own tests), the
        // hooks answer exactly what upstream did before them.
        suite.expect(ForkRecorderOptions.exportChannelCount(in: defaults) == 2,
               "with no preference the export stays in stereo")
        suite.expect(ForkRecorderOptions.exportReaderSettings(in: defaults).isEmpty,
               "and reads its sound exactly as upstream does: a named channel count would change the mix")
        suite.expect(ForkRecorderOptions.showsClicks(in: defaults),
               "with no preference a new recording shows its clicks, as upstream does")
        suite.expect(RecorderEditDocument().showsClickRing,
               "upstream's edit document keeps its own default where the fork registers nothing")

        defaults.set(true, forKey: DefaultsKey.forkRecorderMonoAudio)
        suite.expect(ForkRecorderOptions.exportChannelCount(in: defaults) == 1, "mono follows its preference")
        suite.expect(ForkRecorderOptions.exportReaderSettings(in: defaults).count == 1,
               "in mono the export asks for its one channel as it reads")
        defaults.set(false, forKey: DefaultsKey.forkRecorderShowsClicks)
        suite.expect(!ForkRecorderOptions.showsClicks(in: defaults), "the click rings follow theirs")

        for key in [DefaultsKey.forkRecorderMonoAudio, DefaultsKey.forkRecorderShowsClicks] {
            suite.expect(key.hasPrefix("fork"), "\(key) carries the fork prefix")
            suite.expect(SettingsBackupSupport.exportKeys().contains(key), "\(key) travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkRecorderMonoAudio] as? Bool == true,
               "the app exports in mono by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkRecorderShowsClicks] as? Bool == false,
               "the app leaves the click rings off by default")

        saveFolder(suite, defaults: defaults)
    }

    /// Where saved recordings go: their own folder, else the captures' one.
    private static func saveFolder(_ suite: TestSuite, defaults: UserDefaults) {
        suite.expect(ForkRecorderOptions.saveFolder(recorder: "", screenshot: "~/Downloads") == "~/Downloads",
               "with no folder of their own, recordings go where the captures go")
        suite.expect(ForkRecorderOptions.saveFolder(recorder: "/Volumes/Films", screenshot: "~/Downloads")
            == "/Volumes/Films",
               "a folder chosen for the recordings themselves wins")
        suite.expect(ForkRecorderOptions.saveFolder(recorder: "", screenshot: "").isEmpty,
               "neither set: empty, so upstream's Desktop still applies")

        defaults.removeObject(forKey: DefaultsKey.recorderSaveFolder)
        defaults.removeObject(forKey: DefaultsKey.screenshotSaveFolder)
        suite.expect(ForkRecorderOptions.saveFolder(in: defaults).isEmpty,
               "no preference at all: upstream's default folder")
        defaults.set("~/Downloads", forKey: DefaultsKey.screenshotSaveFolder)
        suite.expect(ForkRecorderOptions.saveFolder(in: defaults) == "~/Downloads",
               "the captures' folder, read from the preferences, takes the recordings too")
        suite.expect(ForkRecorderOptions.saveFolder(recorder: "", in: defaults) == "~/Downloads",
               "and so it does for a recorder folder handed over empty")
        defaults.set("~/Movies", forKey: DefaultsKey.recorderSaveFolder)
        suite.expect(ForkRecorderOptions.saveFolder(in: defaults) == "~/Movies",
               "the recordings' own folder, read from the preferences, wins")
    }
}
