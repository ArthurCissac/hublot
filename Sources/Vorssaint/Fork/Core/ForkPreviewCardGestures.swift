// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// What the keyboard and the trackpad do to a capture card: four shortcuts
/// while the pointer is over a card, a two-finger swipe toward the screen's
/// edge to put it away, and a shortcut that brings back the last card put
/// away. Pure choices, so the harness can pin them down.
enum ForkPreviewCardGestures {
    enum Shortcut: Equatable {
        case copy, save, close, edit
    }

    /// ⌘C copies, ⌘S saves, ⌘W puts the card away, ⌘E opens the editor.
    /// Letters are read as typed, so ⌘W is the W key on an AZERTY keyboard
    /// too; a layout without Latin letters falls back to the keys' positions.
    /// Nil for anything else, which then reaches the app in front untouched.
    static func shortcut(character: String?, keyCode: Int, commandOnly: Bool) -> Shortcut? {
        guard commandOnly else { return nil }
        let folded = character?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if let folded, folded.count == 1, let letter = folded.first, letter.isASCII, letter.isLetter {
            switch letter {
            case "c": return .copy
            case "s": return .save
            case "w": return .close
            case "e": return .edit
            default: return nil
            }
        }
        // Positions of C, S, W and E on a US keyboard.
        switch keyCode {
        case 8: return .copy
        case 1: return .save
        case 13: return .close
        case 14: return .edit
        default: return nil
        }
    }

    /// How far a swipe puts the card away before it goes: toward the left
    /// edge, where the cards live.
    static let dismissDistance: CGFloat = 70
    /// A swipe the other way only gives a little, then holds.
    static let resistance: CGFloat = 0.25
    static let largestResistedOffset: CGFloat = 18

    /// Where the card is drawn for this much finger travel, negative to the left.
    static func swipeOffset(fingerTravel: CGFloat) -> CGFloat {
        guard fingerTravel.isFinite else { return 0 }
        if fingerTravel <= 0 { return fingerTravel }
        return min(fingerTravel * resistance, largestResistedOffset)
    }

    static func swipeDismisses(offset: CGFloat) -> Bool {
        offset <= -dismissDistance
    }

    /// A swipe is taken for the card only when it is mostly sideways: a
    /// vertical scroll over a card is left to whatever is under it.
    static func isSideways(dx: CGFloat, dy: CGFloat) -> Bool {
        abs(dx) > abs(dy) && abs(dx) >= 2
    }

    /// Option-Shift-Command-R brings back the last card put away, by key
    /// position so it is the same key on every layout.
    static let reopenShortcut = GlobalShortcut(keyCode: 15, modifiers: [.option, .shift, .command])
    /// Option-Shift-Command-H, by key position: hides every preview card, and shows them again.
    static let hideShortcut = GlobalShortcut(keyCode: 4, modifiers: [.option, .shift, .command])
}
