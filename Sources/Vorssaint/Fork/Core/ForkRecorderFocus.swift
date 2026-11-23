// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Do Not Disturb while recording. macOS lets no app switch a Focus on by
/// itself, but the Shortcuts app can: the person creates two shortcuts once,
/// one that turns Do Not Disturb on and one that turns it off, under names
/// this file gives, and the recorder runs them at its start and its end.
/// Pure choices: listing and running shortcuts happens elsewhere.
enum ForkRecorderFocus {
    enum Action: Equatable {
        case turnOn, turnOff
    }

    struct Names: Equatable {
        let on: String
        let off: String
    }

    /// The names to create, in the language shown. Both languages are
    /// recognized when looking for them, so changing language breaks nothing.
    static func names(appName: String, french: Bool) -> Names {
        french
            ? Names(on: "\(appName) – Activer Ne pas déranger", off: "\(appName) – Désactiver Ne pas déranger")
            : Names(on: "\(appName) – Turn On Do Not Disturb", off: "\(appName) – Turn Off Do Not Disturb")
    }

    /// The two shortcuts among those the Shortcuts app lists, by exact name.
    /// Nil for one that was not created; a pair is usable only complete.
    static func find(in listed: [String], appName: String) -> (on: String?, off: String?) {
        let present = Set(listed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let candidates = [names(appName: appName, french: true), names(appName: appName, french: false)]
        return (candidates.map { $0.on }.first(where: present.contains),
                candidates.map { $0.off }.first(where: present.contains))
    }

    /// What to run when the recorder starts or stops. Do Not Disturb is
    /// turned off at the end only when it was turned on for this recording.
    static func action(wasRecording: Bool, isRecording: Bool, enabled: Bool, turnedOn: Bool) -> Action? {
        if !wasRecording, isRecording { return enabled ? .turnOn : nil }
        if wasRecording, !isRecording { return turnedOn ? .turnOff : nil }
        return nil
    }

    /// The address that opens the Shortcuts app on a new shortcut with this name.
    static func createURL(name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "create-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }
}
