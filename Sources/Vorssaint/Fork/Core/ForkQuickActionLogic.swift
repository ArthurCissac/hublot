// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The quick actions the fork adds to the menu's tiles, before upstream's:
/// each opens a tool Hublot already has (the colour picker, the screen's
/// text, the phone QR code, background sound, a note, the clipboard shelf,
/// the camera mirror, the next sound output, the one-click scan), plus a
/// presentation mode made of upstream's own switches. Pure: which tiles
/// show, which dev server the QR code opens, what presentation mode changes
/// and what it puts back.
enum ForkQuickActionLogic {
    enum Action: String, CaseIterable {
        case tasks, colorPicker, screenText, phoneSite, ambient, note, clipboard, presentation, camera, soundOutput, smartScan
        case recordScreen, weather, translate, home, printer
    }

    // MARK: - Which tiles show

    /// The fork's tiles hidden in the edit list, as a comma-separated list of names.
    static func hidden(_ stored: String?) -> Set<Action> {
        Set((stored ?? "").split(separator: ",").compactMap { Action(rawValue: String($0)) })
    }

    static func stored(_ hidden: Set<Action>) -> String {
        Action.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }

    /// In their own order, those not hidden and whose tool is on.
    static func visible(hidden: Set<Action>, available: (Action) -> Bool) -> [Action] {
        Action.allCases.filter { !hidden.contains($0) && available($0) }
    }

    // MARK: - The phone QR code

    /// A listening socket, as the port manager reads it.
    struct Listener: Equatable {
        let port: Int
        let protocolName: String
        let processName: String
        let address: String
    }

    /// The dev servers a phone could open: usual dev ports, one per port
    /// (a server often listens on IPv4 and IPv6), lowest port first.
    static func devServers(_ listeners: [Listener]) -> [Listener] {
        var seen = Set<Int>()
        return listeners
            .filter { ForkLocalQRLogic.showsButton(port: $0.port, protocolName: $0.protocolName, processName: $0.processName) }
            .sorted { $0.port == $1.port ? reachRank($0) < reachRank($1) : $0.port < $1.port }
            .filter { seen.insert($0.port).inserted }
    }

    /// Of two sockets on one port, the one bound to every interface comes first.
    private static func reachRank(_ listener: Listener) -> Int {
        switch ForkLocalQRLogic.reach(of: listener.address) {
        case .everywhere: return 0
        case .address: return 1
        case .loopback: return 2
        }
    }

    // MARK: - Presentation mode

    /// What was on before presentation mode, so leaving it puts back only
    /// what it changed.
    struct Snapshot: Codable, Equatable {
        var desktopIconsShown: Bool
        var islandNotifications: Bool
        var keepAwakeActive: Bool
    }

    enum Change: Equatable {
        case hideDesktopIcons, showDesktopIcons
        case pauseIslandNotifications, resumeIslandNotifications
        case startKeepAwake, stopKeepAwake
        case focusOn, focusOff
    }

    static func entering(_ now: Snapshot) -> [Change] {
        var changes: [Change] = [.focusOn]
        if now.desktopIconsShown { changes.append(.hideDesktopIcons) }
        if now.islandNotifications { changes.append(.pauseIslandNotifications) }
        if !now.keepAwakeActive { changes.append(.startKeepAwake) }
        return changes
    }

    /// Back to the snapshot, leaving alone what the user changed meanwhile.
    static func leaving(_ before: Snapshot, now: Snapshot) -> [Change] {
        var changes: [Change] = [.focusOff]
        if before.desktopIconsShown, !now.desktopIconsShown { changes.append(.showDesktopIcons) }
        if before.islandNotifications, !now.islandNotifications { changes.append(.resumeIslandNotifications) }
        if !before.keepAwakeActive, now.keepAwakeActive { changes.append(.stopKeepAwake) }
        return changes
    }

    /// The shortcuts the user makes once in the Shortcuts app to turn Do Not
    /// Disturb on and off, which no app can do directly.
    static let focusOnShortcut = "Hublot présentation début"
    static let focusOffShortcut = "Hublot présentation fin"

    static func hasFocusShortcuts(in list: String) -> Bool {
        let names = Set(list.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        return names.contains(focusOnShortcut) && names.contains(focusOffShortcut)
    }

    // MARK: - The sound output

    /// The outputs the tile goes through: those chosen in Settings, or all
    /// that can play when none is chosen.
    static func outputCycle(selected: [String], available: [String]) -> [String] {
        selected.isEmpty ? available : selected
    }
}
