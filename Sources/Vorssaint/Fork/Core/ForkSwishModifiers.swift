// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The modifiers that change what a Swish-style gesture does, kept as raw
/// event flag masks: the form macOS reports them in, and the form Swish
/// stores them in, so its settings carry over unchanged.
///
/// The super modifier lets a gesture start anywhere in a window instead of
/// only on its title bar, and combines with the others. The four other roles
/// are told apart by the exact set of keys held: fn alone is not fn ⌥.
enum ForkSwishModifiers {
    static let fn: Int = 0x80_0000
    static let shift: Int = 0x2_0000
    static let control: Int = 0x4_0000
    static let option: Int = 0x8_0000
    static let command: Int = 0x10_0000
    /// The keys a modifier can be made of, in the order macOS prints them.
    static let keys: [Int] = [fn, control, option, shift, command]
    static let relevantMask = keys.reduce(0, |)

    /// The values Swish was set to on this Mac, the defaults.
    static let defaultGeneral = fn
    static let defaultScreen = shift
    static let defaultSecondary = fn | control | option
    static let defaultTertiary = fn | option
    static let defaultSuper = command

    enum Role: Equatable {
        /// No modifier: the plain gestures.
        case none
        /// Full screen, closing, quitting.
        case general
        /// Another display.
        case screen
        /// The 3×2 grid, thirds, top and bottom halves; all windows of an app.
        case secondary
        /// The 3×3 grid.
        case tertiary
    }

    /// The five modifiers as set.
    struct Set: Equatable {
        var general = defaultGeneral
        var screen = defaultScreen
        var secondary = defaultSecondary
        var tertiary = defaultTertiary
        var superKey = defaultSuper
    }

    /// Which role the keys held select, and whether the super modifier is held
    /// too. Nil when the keys held match no role: a gesture made while typing
    /// some unrelated shortcut does nothing rather than something unexpected.
    static func role(flags: Int, in set: Set) -> (role: Role, superHeld: Bool)? {
        var held = flags & relevantMask
        let superKey = set.superKey & relevantMask
        let superHeld = superKey != 0 && held & superKey == superKey
        if superHeld { held &= ~superKey }
        if held == 0 { return (.none, superHeld) }
        // The most specific roles first, should two ever be set alike.
        let roles: [(Int, Role)] = [(set.tertiary, .tertiary), (set.secondary, .secondary),
                                    (set.screen, .screen), (set.general, .general)]
        for (mask, role) in roles where mask & relevantMask == held { return (role, superHeld) }
        return nil
    }

    /// A modifier as the keyboard prints it, "fn ⌃ ⌥" for example.
    static func symbols(_ mask: Int) -> String {
        let names: [(Int, String)] = [(fn, "fn"), (control, "⌃"), (option, "⌥"), (shift, "⇧"), (command, "⌘")]
        let held = names.filter { mask & $0.0 != 0 }.map(\.1)
        return held.isEmpty ? "—" : held.joined(separator: " ")
    }
}
