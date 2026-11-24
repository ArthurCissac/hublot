// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9h, the cleaning tools' motion: one rhythm for every window. Slow
/// loops for what waits (the button's breathing light, the floating symbol,
/// the drifting background), short ones for what changes. Every animation
/// stops, or becomes a plain fade, when Reduce Motion is on.
enum ForkCareMotion {
    /// The round button's light, in and out.
    static let breathe: TimeInterval = 3.2
    /// The welcome symbol, up and down.
    static let float: TimeInterval = 3.6
    /// One turn of the working ring.
    static let turn: TimeInterval = 1.4
    /// A pulse leaving the working button.
    static let pulse: TimeInterval = 1.8
    /// The background's light, from one side to the other.
    static let drift: TimeInterval = 18

    /// A card or a screen arriving.
    static let appear: TimeInterval = 0.4
    /// Between two cards arriving one after the other.
    static let stagger: TimeInterval = 0.06
    /// A figure counting up to its value.
    static let countUp: TimeInterval = 0.9
    /// The closing tick drawing itself.
    static let check: TimeInterval = 0.5

    /// When the card at `index` starts arriving.
    static func delay(index: Int) -> TimeInterval {
        Double(max(0, index)) * stagger
    }
}
