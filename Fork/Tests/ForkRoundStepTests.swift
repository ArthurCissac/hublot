// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Volume and brightness keys in round steps of 5 % (ForkRoundSteps).
enum ForkRoundStepTests {
    typealias Steps = ForkRoundSteps

    static func run(_ suite: TestSuite) {
        suite.expect(Steps.next(from: 0.63, direction: 1) == 0.65 && Steps.next(from: 0.63, direction: -1) == 0.60,
               "from 63 %, up lands on 65 % and down on 60 %")
        suite.expect(Steps.next(from: 0.65, direction: 1) == 0.70 && Steps.next(from: 0.65, direction: -1) == 0.60,
               "from a round value, a press moves a whole 5 %")
        suite.expect(Steps.next(from: 0.6499, direction: 1) == 0.70 && Steps.next(from: 0.6501, direction: -1) == 0.60,
               "a level read back a hair off 65 % counts as 65 %")
        suite.expect(Steps.next(from: 1, direction: 1) == 1 && Steps.next(from: 0.98, direction: 1) == 1
            && Steps.next(from: 0, direction: -1) == 0 && Steps.next(from: 0.02, direction: -1) == 0,
               "the range ends at 0 % and 100 %")
        suite.expect(Steps.next(from: 0, direction: 1) == 0.05 && Steps.next(from: .nan, direction: 1) == 0.05,
               "from silence, or an unreadable level, the first press gives 5 %")

        var level = 0.0
        var seen: [Double] = []
        for _ in 0..<21 { level = Steps.next(from: level, direction: 1); seen.append(level) }
        suite.expect(seen.prefix(20).enumerated().allSatisfy { abs($0.element - Double($0.offset + 1) * 0.05) < 1e-9 }
            && seen.last == 1,
               "twenty presses climb 5, 10, … 100 % and stay there")

        let full = Steps.systemStep
        suite.expect(Steps.level(current: 0.63, delta: full, enabled: true) == 0.65
            && Steps.level(current: 0.63, delta: -full, enabled: true) == 0.60,
               "a full key step becomes a round step")
        suite.expect(Steps.level(current: 0.63, delta: 2 * full, enabled: true) == 0.70,
               "two presses queued together take two round steps")
        suite.expect(Steps.level(current: 0.63, delta: full / 4, enabled: true) == nil
            && Steps.level(current: 0.63, delta: full / 2, enabled: true) == nil,
               "finer steps (Option-Shift, half and quarter steps) are left as they are")
        suite.expect(Steps.level(current: 0.63, delta: full, enabled: false) == nil
            && Steps.level(current: .nan, delta: full, enabled: true) == nil,
               "switched off, or with no level to start from, the usual step applies")

        let defaults = UserDefaults(suiteName: "ForkRoundStepTests")!
        defaults.removePersistentDomain(forName: "ForkRoundStepTests")
        defaults.set(true, forKey: DefaultsKey.forkVolumeRoundSteps)
        defaults.set(false, forKey: DefaultsKey.forkBrightnessRoundSteps)
        suite.expect(Steps.volumeLevel(current: 0.63, direction: 1, fine: false, defaults: defaults) == 0.65
            && Steps.volumeLevel(current: 0.63, direction: 1, fine: true, defaults: defaults) == nil,
               "the volume keys round their step, except the fine step")
        suite.expect(Steps.brightness(0.52, delta: full, defaults: defaults) == nil,
               "each key family follows its own setting")
        defaults.removePersistentDomain(forName: "ForkRoundStepTests")

        for key in [DefaultsKey.forkVolumeRoundSteps, DefaultsKey.forkBrightnessRoundSteps] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) is on out of the box and travels in backups")
        }
    }
}
