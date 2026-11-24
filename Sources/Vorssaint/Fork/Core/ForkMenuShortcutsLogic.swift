// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Direct ways in from the menu bar panel: quitting the apps that weigh the
/// most from the System section, and the cleaning tools from the Disks
/// section. Pure: what each process allows, which apps to show, what a click
/// does.
enum ForkMenuShortcutsLogic {
    /// What the panel offers for a process.
    enum QuitOffer: Equatable {
        /// Nothing: a protected process (the system's, the Finder, this app).
        case none
        /// An app: quit it as its menu would, asking to save if it needs to.
        case quit
        /// Not an app: only a forced end, always confirmed first.
        case forceOnly
    }

    /// Apps never offered to quit from the panel: the Finder relaunches at
    /// once and quitting it only flashes the desktop.
    static let protectedBundleIDs: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver"]

    static func offer(isRegularApp: Bool, bundleID: String?, isProtected: Bool, canForce: Bool) -> QuitOffer {
        if isProtected || bundleID.map(protectedBundleIDs.contains) == true { return .none }
        if isRegularApp { return .quit }
        return canForce ? .forceOnly : .none
    }

    enum Action: Equatable { case none, quit, forceQuit }

    /// A click quits; with Option held it forces, after the confirmation
    /// upstream's process tools already show.
    static func action(for offer: QuitOffer, optionKey: Bool) -> Action {
        switch offer {
        case .none: return .none
        case .quit: return optionKey ? .forceQuit : .quit
        case .forceOnly: return .forceQuit
        }
    }

    /// How many apps the System section lists, and how often it reads them.
    static let heavyLimit = 5
    static let refreshInterval: TimeInterval = 4

    /// The apps to list, heaviest in memory first: only those that can be
    /// quit, `limit` at most.
    static func heavyApps(_ rows: [(pid: Int32, memory: Double)], offer: (Int32) -> QuitOffer,
                          limit: Int = heavyLimit) -> [Int32] {
        rows.filter { offer($0.pid) == .quit }
            .sorted { $0.memory > $1.memory }
            .prefix(limit)
            .map(\.pid)
    }
}
