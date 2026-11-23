// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The sound played on each copy.
enum ForkClipboardCopySoundTests {
    typealias Sound = ForkClipboardCopySound

    static func run(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 20_000)
        suite.expect(Sound.isNewCopy(newest: start.addingTimeInterval(5), lastHeard: start, quietUntil: nil, now: start.addingTimeInterval(5)),
               "a copy made after the last one heard plays the sound")
        suite.expect(!Sound.isNewCopy(newest: start.addingTimeInterval(-3_600), lastHeard: start, quietUntil: nil, now: start),
               "the history loaded at launch, older than that, plays nothing")
        suite.expect(!Sound.isNewCopy(newest: nil, lastHeard: start, quietUntil: nil, now: start),
               "an empty history plays nothing")
        suite.expect(!Sound.isNewCopy(newest: start.addingTimeInterval(1), lastHeard: start, quietUntil: start.addingTimeInterval(1.5),
                                      now: start.addingTimeInterval(1)),
               "a card pasted from the shelf, copied again, plays nothing")
        suite.expect(Sound.isNewCopy(newest: start.addingTimeInterval(3), lastHeard: start, quietUntil: start.addingTimeInterval(1.5),
                                     now: start.addingTimeInterval(3)),
               "the next real copy plays again")
        suite.expect(Sound.sound(stored: "Pop") == "Pop" && Sound.sound(stored: "") == nil && Sound.sound(stored: "Sosumi") == nil
            && Sound.sound(stored: nil) == nil,
               "only the offered sounds play; none means silence")
        let key = DefaultsKey.forkClipboardCopySound
        suite.expect(Defaults.registeredDefaults[key] as? String == Sound.defaultSound && SettingsBackupSupport.exportKeys().contains(key),
               "the copy sound is on by default, and the choice travels in backups")
    }
}
