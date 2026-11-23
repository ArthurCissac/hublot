// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Keys pressed during a recording, shown as captions.
enum ForkRecorderKeyTests {
    typealias Keys = ForkRecorderKeys

    static func run(_ suite: TestSuite) {
        func label(_ code: Int, _ chars: String?, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false,
                   shift: Bool = false, all: Bool = false) -> String? {
            Keys.label(keyCode: code, characters: chars, command: cmd, option: opt, control: ctrl, shift: shift,
                       allKeys: all, spaceName: "Espace")?.text
        }
        suite.expect(label(8, "c", cmd: true) == "⌘C" && label(21, "4", cmd: true, shift: true) == "⇧⌘4"
            && label(12, "q", opt: true, ctrl: true) == "⌃⌥Q",
               "a shortcut reads as its modifiers in macOS order, then its key")
        suite.expect(label(36, "\r", cmd: true) == "⌘↩" && label(49, " ", ctrl: true) == "⌃Espace"
            && label(53, nil, cmd: true) == "⌘⎋" && label(122, nil, cmd: true) == "⌘F1",
               "keys that type no character have a name")
        suite.expect(label(0, "a") == nil && label(36, "\r") == nil && label(0, "a", shift: true) == nil,
               "with shortcuts only, typing and lone keys are not shown")
        suite.expect(label(0, "a", all: true) == "a" && label(0, "A", shift: true, all: true) == "A"
            && label(51, nil, all: true) == "⌫",
               "with all keys, typing reads as typed")
        suite.expect(Keys.label(keyCode: 0, characters: "a", command: false, option: false, control: false, shift: false,
                                allKeys: true, spaceName: "Espace")?.isTyping == true
            && Keys.label(keyCode: 8, characters: "c", command: true, option: false, control: false, shift: false,
                          allKeys: true, spaceName: "Espace")?.isTyping == false,
               "typed characters are told apart from shortcuts")

        let presses = [
            Keys.Press(time: 1.0, label: "⌘C", isTyping: false),
            Keys.Press(time: 1.5, label: "⌘V", isTyping: false),
            Keys.Press(time: 4.0, label: "b", isTyping: true),
            Keys.Press(time: 4.2, label: "o", isTyping: true),
            Keys.Press(time: 4.4, label: "n", isTyping: true),
            Keys.Press(time: 6.0, label: "j", isTyping: true),
        ]
        let captions = Keys.captions(for: presses, duration: 10)
        suite.expect(captions.map(\.text) == ["⌘C", "⌘V", "bon", "j"],
               "one caption per shortcut, typing joined into words, a pause starting a new one")
        suite.expect(captions[0].start == 1 && captions[0].end == 1.5,
               "a caption ends when the next starts, so captions never stack")
        suite.expect(captions[1].end == 1.5 + Keys.holdDuration, "one left alone stays a moment")
        suite.expect(abs(captions[2].end - (4.4 + Keys.holdDuration)) < 0.0001, "a word stays a moment after its last key")
        let late = Keys.captions(for: [Keys.Press(time: 9.5, label: "⌘S", isTyping: false)], duration: 10)
        suite.expect(late.first?.end == 10, "no caption runs past the recording")
        suite.expect(Keys.captions(for: [Keys.Press(time: 12, label: "⌘S", isTyping: false)], duration: 10).isEmpty
            && Keys.captions(for: presses, duration: 0).isEmpty,
               "a press outside the recording is dropped")
        let quick = Keys.captions(for: [Keys.Press(time: 1, label: "⌘A", isTyping: false),
                                        Keys.Press(time: 1.1, label: "⌘C", isTyping: false)], duration: 10)
        suite.expect(quick.map(\.text) == ["⌘C"], "a caption too brief to read is left out")

        let start = Date(timeIntervalSince1970: 1_000)
        suite.expect(Keys.belongs(videoCreated: start.addingTimeInterval(1), start: start, end: start.addingTimeInterval(30))
            && !Keys.belongs(videoCreated: start.addingTimeInterval(-3_600), start: start, end: start.addingTimeInterval(30)),
               "keys go to the recording made while they were captured, not to an older one opened later")

        for key in [DefaultsKey.forkRecorderShowsKeys, DefaultsKey.forkRecorderAllKeys] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == false && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) is off by default and travels in backups")
        }
    }
}
