// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine

/// Plays the copy sound when upstream's history records a new copy. It only
/// watches the history's published entries; nothing runs while nothing is
/// copied, and no sound plays when the setting is off.
final class ForkClipboardCopySoundPlayer {
    static let shared = ForkClipboardCopySoundPlayer()

    private var watcher: AnyCancellable?
    private var lastHeard = Date()
    private var quietUntil: Date?
    private var sounds: [String: NSSound] = [:]

    func start() {
        lastHeard = Date()
        watcher = ClipboardHistoryService.shared.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in self?.entriesChanged(entries) }
    }

    /// The shelf is about to copy a card again: that is no new copy.
    func stayQuiet() {
        quietUntil = Date().addingTimeInterval(1.5)
    }

    private func entriesChanged(_ entries: [ClipboardHistoryEntry]) {
        let newest = entries.map(\.copiedAt).max()
        let now = Date()
        let isNew = ForkClipboardCopySound.isNewCopy(newest: newest, lastHeard: lastHeard, quietUntil: quietUntil, now: now)
        if let newest, newest > lastHeard { lastHeard = newest }
        guard isNew, let name = ForkClipboardCopySound.sound(
            stored: UserDefaults.standard.string(forKey: DefaultsKey.forkClipboardCopySound)) else { return }
        play(name)
    }

    func play(_ name: String) {
        let sound = sounds[name] ?? NSSound(named: NSSound.Name(name))
        guard let sound else { return }
        sounds[name] = sound
        sound.volume = ForkClipboardCopySound.volume
        sound.stop()
        sound.play()
    }
}
