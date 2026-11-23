// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// A short sound each time something is copied, read from upstream's history
/// as it records the copy. Pure choices: playing it happens elsewhere.
enum ForkClipboardCopySound {
    /// macOS's own sounds that suit a copy, quietest first. "" means none.
    static let sounds = ["Pop", "Tink", "Morse", "Bottle", "Purr", "Ping"]
    static let defaultSound = "Pop"
    static let volume: Float = 0.6

    static func sound(stored: String?) -> String? {
        guard let stored, sounds.contains(stored) else { return nil }
        return stored
    }

    /// Whether the history's newest entry is a copy made just now: copied
    /// after the app started listening, newer than the last one heard, and
    /// not while the shelf itself was copying (a paste from the shelf copies
    /// its card again, and that is no new copy).
    static func isNewCopy(newest: Date?, lastHeard: Date, quietUntil: Date?, now: Date) -> Bool {
        guard let newest, newest > lastHeard else { return false }
        if let quietUntil, now <= quietUntil { return false }
        return true
    }
}
