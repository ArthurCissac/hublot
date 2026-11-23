// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// A picture being moved, resized or turned on the editor's stage is drawn
/// there by the stage itself, under the pointer, and left out of the video
/// meanwhile: otherwise the video's copy would stay at the old place and two
/// pictures would show. Read from one line of upstream's composer, on its
/// rendering thread, hence the lock.
enum ForkRecorderImageVisibility {
    private static let lock = NSLock()
    private static var hidden: Set<UUID> = []

    static func hide(_ id: UUID) {
        lock.lock()
        hidden.insert(id)
        lock.unlock()
    }

    static func show(_ id: UUID) {
        lock.lock()
        hidden.remove(id)
        lock.unlock()
    }

    static func showAll() {
        lock.lock()
        hidden.removeAll()
        lock.unlock()
    }

    static func isHidden(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hidden.contains(id)
    }
}
