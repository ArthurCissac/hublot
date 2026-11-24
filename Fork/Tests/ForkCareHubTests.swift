// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The Care window's sidebar (ForkCareHubLogic).
enum ForkCareHubTests {
    typealias Logic = ForkCareHubLogic

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.Module.allCases == [.smartScan, .cleanup, .protection, .performance, .applications, .diskMap],
               "six tools, the one-click scan first")
        suite.expect(Logic.Module.allCases.map(\.digit) == [1, 2, 3, 4, 5, 6]
            && Logic.module(forDigit: 3) == .protection && Logic.module(forDigit: 7) == nil,
               "⌘1 to ⌘6 follow the sidebar's order")
        suite.expect(Logic.module(stored: "diskMap") == .diskMap && Logic.module(stored: nil) == .smartScan
            && Logic.module(stored: "gone") == .smartScan,
               "the window reopens on the tool left open, or on the one-click scan")
        suite.expect(Logic.Module.protection.tool == .antivirus && Logic.Module.performance.tool == .maintenance
            && Logic.Module.cleanup.tool == nil && Logic.Module.applications.tool == nil,
               "the fork's tools keep their colours; upstream's pages get hues of their own")
        suite.expect(Set(Logic.Module.allCases.map { "\($0.tint)" }).count == Logic.Module.allCases.count,
               "every tool has its own hue in the sidebar")

        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 1))!
        let yesterday = calendar.date(byAdding: .hour, value: -5, to: now)!
        let threeDays = calendar.date(byAdding: .day, value: -3, to: now)!
        suite.expect(Logic.relativeDay(now, now: now, french: true, calendar: calendar) == "aujourd’hui"
            && Logic.relativeDay(yesterday, now: now, french: true, calendar: calendar) == "hier"
            && Logic.relativeDay(threeDays, now: now, french: false, calendar: calendar) == "3 days ago",
               "a past date reads as today, yesterday or so many days ago")

        suite.expect(Logic.protectionState(threats: 3, scanning: true, lastScan: now, now: now, french: true) == "3 menaces à examiner"
            && Logic.protectionState(threats: 1, scanning: false, lastScan: nil, now: now, french: false) == "1 threat to review",
               "threats to review come before anything else")
        suite.expect(Logic.protectionState(threats: 0, scanning: true, lastScan: nil, now: now, french: true) == "Analyse en cours…"
            && Logic.protectionState(threats: 0, scanning: false, lastScan: now, now: now, french: true) == "Analysé aujourd’hui"
            && Logic.protectionState(threats: 0, scanning: false, lastScan: nil, now: now, french: true) == nil,
               "then a scan under way, then the last scan, else nothing")
        suite.expect(Logic.performanceState(running: true, lastRun: nil, now: now, french: true) == "En cours…"
            && Logic.performanceState(running: false, lastRun: threeDays, now: now, french: true) == "Fait il y a 3 jours"
            && Logic.performanceState(running: false, lastRun: nil, now: now, french: false) == nil,
               "maintenance shows its jobs under way, or its last run")
        suite.expect(Logic.diskMapState(scanning: true, files: 12_340, hasMap: false, french: false) == "Scanning… 12,340 files"
            && Logic.diskMapState(scanning: false, files: 0, hasMap: true, french: true) == "Carte prête"
            && Logic.diskMapState(scanning: false, files: 0, hasMap: false, french: true) == nil,
               "the disk map counts its files, then says it is ready")
    }
}
