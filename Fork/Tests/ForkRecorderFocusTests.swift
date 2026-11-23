// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Do Not Disturb while recording, through two shortcuts.
enum ForkRecorderFocusTests {
    typealias Focus = ForkRecorderFocus

    static func run(_ suite: TestSuite) {
        let french = Focus.names(appName: "Hublot", french: true)
        let english = Focus.names(appName: "Hublot", french: false)
        suite.expect(french.on == "Hublot – Activer Ne pas déranger" && french.off == "Hublot – Désactiver Ne pas déranger",
               "the shortcuts are named after the app, in French")
        suite.expect(english.on != french.on && english.off != french.off, "and in English")

        let listed = ["bonne nuit", "Définir le mode de concentration", " Hublot – Activer Ne pas déranger ",
                      "Hublot – Désactiver Ne pas déranger"]
        let found = Focus.find(in: listed, appName: "Hublot")
        suite.expect(found.on == french.on && found.off == french.off,
               "both shortcuts are found by their exact names, spaces around them aside")
        suite.expect(Focus.find(in: ["Définir le mode de concentration"], appName: "Hublot") == (nil, nil) as (String?, String?),
               "a shortcut of the person's own, whatever it does, is never run")
        let mixed = Focus.find(in: [english.on, french.off], appName: "Hublot")
        suite.expect(mixed.on == english.on && mixed.off == french.off,
               "a pair created in another language is still found")

        suite.expect(Focus.action(wasRecording: false, isRecording: true, enabled: true, turnedOn: false) == .turnOn,
               "a recording that starts turns Do Not Disturb on")
        suite.expect(Focus.action(wasRecording: false, isRecording: true, enabled: false, turnedOn: false) == nil,
               "not when the option is off")
        suite.expect(Focus.action(wasRecording: true, isRecording: false, enabled: true, turnedOn: true) == .turnOff,
               "it is turned off when the recording ends")
        suite.expect(Focus.action(wasRecording: true, isRecording: false, enabled: true, turnedOn: false) == nil,
               "but only if this recording turned it on")
        suite.expect(Focus.action(wasRecording: true, isRecording: true, enabled: true, turnedOn: true) == nil,
               "nothing runs while a recording goes on")

        let url = Focus.createURL(name: french.on)?.absoluteString
        suite.expect(url == "shortcuts://create-shortcut?name=Hublot%20%E2%80%93%20Activer%20Ne%20pas%20d%C3%A9ranger",
               "the Shortcuts app opens on a new shortcut with that name: \(url ?? "nil")")

        let key = DefaultsKey.forkRecorderDoNotDisturb
        suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
               "Do Not Disturb while recording is on by default, and travels in backups")
    }
}
