// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Which microphone a recording listens to. Upstream takes whatever input the
/// system has as its default, which follows headphones as they connect; here
/// the Mac's own microphone is the default, and another one can be chosen.
/// Pure choices: the devices come in as plain values.
enum ForkRecorderMicrophone {
    struct Device: Equatable {
        let id: String
        let name: String
        let isBuiltIn: Bool
    }

    /// What a click on the microphone item lands on.
    struct Choice: Equatable {
        let enabled: Bool
        /// The microphone to remember; unchanged when the click turns it off.
        let id: String
    }

    /// The Mac's own microphone first, then the others by name.
    static func ordered(_ devices: [Device]) -> [Device] {
        devices.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The microphone to use: the one chosen, while it is plugged in;
    /// otherwise the Mac's own; otherwise the first there is.
    static func selected(storedID: String, among devices: [Device]) -> Device? {
        let ordered = ordered(devices)
        return ordered.first { $0.id == storedID } ?? ordered.first
    }

    /// Each click moves one step: from off to the Mac's microphone, then
    /// through the others, then off again. With no microphone known it is a
    /// plain switch.
    static func next(enabled: Bool, storedID: String, among devices: [Device]) -> Choice {
        let ordered = ordered(devices)
        guard let first = ordered.first else { return Choice(enabled: !enabled, id: storedID) }
        guard enabled,
              let current = selected(storedID: storedID, among: devices),
              let index = ordered.firstIndex(of: current)
        else { return Choice(enabled: true, id: first.id) }
        if index + 1 < ordered.count { return Choice(enabled: true, id: ordered[index + 1].id) }
        return Choice(enabled: false, id: storedID)
    }
}
