// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The clipboard shelf's tint.
enum ForkShelfTintTests {
    typealias Tint = ForkShelfTint

    static func run(_ suite: TestSuite) {
        let blue = Tint.components("#3D7BFF")
        suite.expect(blue.map { abs($0.red - 61.0 / 255) < 0.001 && abs($0.green - 123.0 / 255) < 0.001 && $0.blue == 1 } == true,
               "a stored colour is read back")
        suite.expect(Tint.components("3d7bff") != nil, "with or without its #, in either case")
        suite.expect(Tint.components("") == nil && Tint.components(nil) == nil && Tint.components("#12345") == nil
            && Tint.components("#GGGGGG") == nil,
               "no colour, or an unreadable one, means no tint")
        suite.expect(Tint.hex(red: 61.0 / 255, green: 123.0 / 255, blue: 1) == "#3D7BFF"
            && Tint.hex(red: 2, green: -1, blue: .nan) == "#FF0000",
               "a colour is stored as #RRGGBB, its channels kept within range")
        suite.expect(Tint.intensity(3) == 1 && Tint.intensity(-1) == 0 && Tint.intensity(.nan) == Tint.defaultIntensity,
               "the tint's strength stays between none and full")
        for key in [DefaultsKey.forkClipboardShelfGlass, DefaultsKey.forkClipboardShelfTint, DefaultsKey.forkClipboardShelfTintIntensity] {
            suite.expect(Defaults.registeredDefaults[key] != nil && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) has its default and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkClipboardShelfTint] as? String == Tint.defaultHex,
               "the shelf has a little colour out of the box")
    }
}
