// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Runs an action once, on the next turn of the main run loop, however many
/// times it is asked for before then.
///
/// The fork's global hotkeys follow the preferences. Registering one claims
/// it through upstream's `SystemShortcutTakeover`, which writes a preference
/// while it holds its lock; the write posts `UserDefaults.didChangeNotification`
/// on the spot. An owner that registered again from inside that notification
/// asked for the same lock and froze the app at launch. Deferring the
/// registration to the next turn lets the first claim finish first.
final class ForkCoalescedMainAction {
    private let action: () -> Void
    private var scheduled = false

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [self] in
            scheduled = false
            action()
        }
    }
}
