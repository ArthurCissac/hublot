// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The fork's quick action tiles: which show, which dev server the QR code
/// opens, what presentation mode changes and puts back, the sound outputs.
enum ForkQuickActionTests {
    typealias Logic = ForkQuickActionLogic

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.hidden("note,camera,nonsense") == [.note, .camera] && Logic.hidden(nil).isEmpty
            && Logic.stored([.camera, .colorPicker]) == "colorPicker,camera",
                     "hidden tiles are kept by name, in the tiles' order; unknown names are dropped")
        suite.expect(Logic.visible(hidden: [.note], available: { $0 != .camera }).first == .tasks
            && !Logic.visible(hidden: [.note], available: { $0 != .camera }).contains(.note)
            && !Logic.visible(hidden: [], available: { $0 != .camera }).contains(.camera),
                     "a tile shows unless hidden or its tool is off, in a fixed order")

        let listeners: [Logic.Listener] = [
            .init(port: 5173, protocolName: "TCP", processName: "node", address: "127.0.0.1:5173"),
            .init(port: 3000, protocolName: "TCP", processName: "node", address: "[::1]:3000"),
            .init(port: 3000, protocolName: "TCP", processName: "node", address: "*:3000"),
            .init(port: 5000, protocolName: "TCP", processName: "ControlCenter", address: "*:5000"),
            .init(port: 49152, protocolName: "TCP", processName: "Spotify", address: "*:49152"),
        ]
        let servers = Logic.devServers(listeners)
        suite.expect(servers.map(\.port) == [3000, 5173] && servers.first?.address == "*:3000",
                     "dev servers come once per port, lowest first, the socket open to the network preferred")

        let before = Logic.Snapshot(desktopIconsShown: true, islandNotifications: true, keepAwakeActive: false)
        suite.expect(Logic.entering(before) == [.focusOn, .hideDesktopIcons, .pauseIslandNotifications, .startKeepAwake]
            && Logic.entering(.init(desktopIconsShown: false, islandNotifications: false, keepAwakeActive: true)) == [.focusOn],
                     "presentation mode changes only what is not already as a demo wants it")
        let during = Logic.Snapshot(desktopIconsShown: false, islandNotifications: false, keepAwakeActive: true)
        suite.expect(Logic.leaving(before, now: during) == [.focusOff, .showDesktopIcons, .resumeIslandNotifications, .stopKeepAwake]
            && Logic.leaving(.init(desktopIconsShown: false, islandNotifications: true, keepAwakeActive: true), now: during)
                == [.focusOff, .resumeIslandNotifications],
                     "leaving puts back only what presentation mode changed")
        suite.expect(Logic.hasFocusShortcuts(in: "Autre\nHublot présentation début\nHublot présentation fin\n")
            && !Logic.hasFocusShortcuts(in: "Hublot présentation début"),
                     "Do Not Disturb follows only when both shortcuts exist")

        suite.expect(Logic.outputCycle(selected: [], available: ["a", "b"]) == ["a", "b"]
            && Logic.outputCycle(selected: ["b"], available: ["a", "b"]) == ["b"],
                     "the sound tile goes through the outputs chosen in Settings, or all of them")
    }
}
