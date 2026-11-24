// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Closing the lid while Keep Awake's closed-lid mode runs puts every display
/// to sleep, the external ones included, as the "Put Display to Sleep" hot
/// corner does. Upstream's own option only dims the built-in panel and leaves
/// an external display exactly as it was. Pure: lid readings and settings come
/// in, what to do goes out.
enum ForkLidDisplaySleepLogic {
    /// How long after the lid closes the displays go to sleep. macOS first
    /// moves everything onto the external display; putting it to sleep before
    /// that settles would let the move light it up again.
    static let settleDelay: TimeInterval = 3

    /// What puts the displays to sleep. Allowed without administrator rights;
    /// the Mac itself keeps running.
    static let pmsetPath = "/usr/bin/pmset"
    static let pmsetArguments = ["displaysleepnow"]

    /// The lid is watched only while the closed-lid mode is in effect, the
    /// setting on and Keep Awake available.
    static func isArmed(enabled: Bool, clamshellActive: Bool, featureAvailable: Bool) -> Bool {
        enabled && clamshellActive && featureAvailable
    }

    /// The lid between two readings. Only a lid seen open, then closed, counts
    /// as closing: the first reading after the watch starts never does, so
    /// starting a session with the lid already shut, while working on the
    /// external display, leaves that display on. A Mac without a lid reads nil
    /// and never changes.
    struct LidWatch: Equatable {
        enum Change: Equatable { case none, closed, opened }

        private(set) var lastClosed: Bool?

        mutating func read(_ closed: Bool?) -> Change {
            guard let closed else { return .none }
            defer { lastClosed = closed }
            switch (lastClosed, closed) {
            case (false?, true): return .closed
            case (true?, false): return .opened
            default: return .none
            }
        }
    }

    /// Once the settle delay is over: the displays sleep only if nothing
    /// newer happened since the lid closed (no other opening or closing), the
    /// mode is still on and the lid still shut.
    static func shouldSleep(scheduled: Int, current: Int, armed: Bool, lidClosed: Bool?) -> Bool {
        scheduled == current && armed && lidClosed == true
    }

    /// While the displays sleep with the lid shut, Keep Awake's pointer nudge
    /// waits: each nudge is a mouse move, which would light them up again.
    static func holdsDisplaysAsleep(slept: Bool, lidClosed: Bool?) -> Bool {
        slept && lidClosed == true
    }
}
