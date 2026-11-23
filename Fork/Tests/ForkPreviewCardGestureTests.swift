// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The keyboard and trackpad on capture cards.
enum ForkPreviewCardGestureTests {
    typealias Gestures = ForkPreviewCardGestures

    static func run(_ suite: TestSuite) {
        suite.expect(Gestures.shortcut(character: "c", keyCode: 8, commandOnly: true) == .copy
            && Gestures.shortcut(character: "s", keyCode: 1, commandOnly: true) == .save
            && Gestures.shortcut(character: "w", keyCode: 13, commandOnly: true) == .close
            && Gestures.shortcut(character: "e", keyCode: 14, commandOnly: true) == .edit,
               "⌘C copies, ⌘S saves, ⌘W puts the card away, ⌘E opens the editor")
        suite.expect(Gestures.shortcut(character: "w", keyCode: 6, commandOnly: true) == .close
            && Gestures.shortcut(character: "z", keyCode: 13, commandOnly: true) == nil,
               "on an AZERTY keyboard ⌘W is the W key, not the key where a US keyboard has its W")
        suite.expect(Gestures.shortcut(character: "C", keyCode: 8, commandOnly: true) == .copy,
               "the letter is read whatever its case")
        suite.expect(Gestures.shortcut(character: "ц", keyCode: 13, commandOnly: true) == .close,
               "a layout without Latin letters falls back to the key's position")
        suite.expect(Gestures.shortcut(character: "c", keyCode: 8, commandOnly: false) == nil
            && Gestures.shortcut(character: "v", keyCode: 9, commandOnly: true) == nil,
               "any other key or modifier reaches the app in front untouched: ⌘V still pastes there")

        suite.expect(Gestures.swipeOffset(fingerTravel: -50) == -50, "a swipe toward the edge moves the card with the fingers")
        suite.expect(Gestures.swipeOffset(fingerTravel: 40) == 10 && Gestures.swipeOffset(fingerTravel: 400) == Gestures.largestResistedOffset,
               "a swipe the other way only gives a little, then holds")
        suite.expect(Gestures.swipeOffset(fingerTravel: .nan) == 0, "a travel that is no number moves nothing")
        suite.expect(Gestures.swipeDismisses(offset: -Gestures.dismissDistance) && !Gestures.swipeDismisses(offset: -40)
            && !Gestures.swipeDismisses(offset: 18),
               "only a swipe far enough toward the edge puts the card away; a shorter one slides it back")
        suite.expect(Gestures.isSideways(dx: -6, dy: 2) && !Gestures.isSideways(dx: 2, dy: -6) && !Gestures.isSideways(dx: 1, dy: 0),
               "a vertical scroll over a card is not taken for a swipe")

        suite.expect(Gestures.reopenShortcut == GlobalShortcut(keyCode: 15, modifiers: [.option, .shift, .command]),
               "the reopen shortcut is Option-Shift-Command-R")
        for key in [DefaultsKey.forkReopenPreviewShortcutEnabled, DefaultsKey.forkReopenPreviewShortcut] {
            suite.expect(Defaults.registeredDefaults[key] != nil && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) has its default and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkReopenPreviewShortcutEnabled] as? Bool == true,
               "the reopen shortcut is on by default")
    }
}
