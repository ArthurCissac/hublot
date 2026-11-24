// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The menu bar panel's direct ways in: quitting apps and the cleaning tools.
enum ForkMenuShortcutsTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkMenuShortcutsLogic

        suite.expect(Logic.offer(isRegularApp: true, bundleID: "com.google.Chrome", isProtected: false, canForce: true) == .quit,
                     "an app is offered a normal quit")
        suite.expect(Logic.offer(isRegularApp: false, bundleID: nil, isProtected: false, canForce: true) == .forceOnly
            && Logic.offer(isRegularApp: false, bundleID: nil, isProtected: false, canForce: false) == .none,
                     "a process that is not an app can only be forced, when the process tools allow it")
        suite.expect(Logic.offer(isRegularApp: true, bundleID: "com.apple.finder", isProtected: false, canForce: true) == .none
            && Logic.offer(isRegularApp: true, bundleID: "x", isProtected: true, canForce: true) == .none,
                     "the Finder and protected processes get no button")

        suite.expect(Logic.action(for: .quit, optionKey: false) == .quit
            && Logic.action(for: .quit, optionKey: true) == .forceQuit
            && Logic.action(for: .forceOnly, optionKey: false) == .forceQuit
            && Logic.action(for: .none, optionKey: true) == .none,
                     "a click quits, Option forces (confirmed), nothing for protected processes")

        let rows: [(pid: Int32, memory: Double)] = [(10, 100), (11, 900), (12, 500), (13, 800), (14, 50), (15, 700), (16, 600)]
        let offers: [Int32: Logic.QuitOffer] = [10: .quit, 11: .none, 12: .quit, 13: .forceOnly, 14: .quit, 15: .quit, 16: .quit]
        let heavy = Logic.heavyApps(rows, offer: { offers[$0] ?? .none })
        suite.expect(heavy == [15, 16, 12, 10, 14],
                     "the heaviest apps that can be quit, five at most, protected and background processes left out")
        suite.expect(Logic.heavyApps([], offer: { _ in .quit }).isEmpty && Logic.heavyLimit == 5,
                     "nothing measured yet, nothing listed")
    }
}
