// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9f: the one-click scan's steps, what it recommends and its summaries.
enum ForkSmartScanTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkSmartScanLogic

        suite.expect(Logic.Step.allCases == [.cleaning, .protection, .performance],
                     "three steps: cleaning, protection, performance")
        suite.expect(Logic.progress(step: .cleaning) == 0
            && abs(Logic.progress(step: .protection, fraction: 0.5) - 0.5) < 1e-9
            && abs(Logic.progress(step: .performance) - 2.0 / 3) < 1e-9
            && Logic.progress(step: .performance, fraction: 7) == 1,
                     "the ring fills a third per step, the protection third as places are scanned")

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let day: TimeInterval = 86_400
        suite.expect(Logic.dueJobs(lastRuns: [:], now: now) == [.dns, .launchServices],
                     "jobs never run are due")
        suite.expect(Logic.dueJobs(lastRuns: [.dns: now.addingTimeInterval(-29 * day),
                                              .launchServices: now.addingTimeInterval(-30 * day)], now: now)
            == [.launchServices],
                     "a job is due again after 30 days")
        suite.expect(Logic.dueJobs(lastRuns: [.dns: now, .launchServices: now], now: now).isEmpty
            && !Logic.offeredJobs.contains(.memory) && !Logic.offeredJobs.contains(.spotlight),
                     "freeing memory and reindexing Spotlight are never recommended")

        let recent = Logic.recentDownloads([("/Users/a/Downloads/old.zip", now.addingTimeInterval(-40 * day)),
                                            ("/Users/a/Downloads/new.dmg", now.addingTimeInterval(-day)),
                                            ("/Users/a/Downloads/newer", now.addingTimeInterval(-60))], now: now)
        suite.expect(recent == ["/Users/a/Downloads/newer", "/Users/a/Downloads/new.dmg"],
                     "only what arrived in Downloads this month, newest first")
        let many = (0..<1_000).map { ("/d/\($0)", now.addingTimeInterval(-Double($0))) }
        suite.expect(Logic.recentDownloads(many, now: now).count == Logic.recentLimit
            && Logic.recentDownloads(many, now: now).first == "/d/0",
                     "a few hundred items at most, the newest")
        let apps = Logic.quickAppTargets([
            Logic.RecentApp(path: "/Applications/Xcode.app", bundleID: "com.apple.dt.Xcode", fromAppStore: true),
            Logic.RecentApp(path: "/Applications/Tool.app", bundleID: "com.example.tool", fromAppStore: false),
            Logic.RecentApp(path: "/Applications/Store.app", bundleID: "com.example.store", fromAppStore: true),
            Logic.RecentApp(path: "/Applications/iMovie.app", bundleID: "com.apple.iMovieApp", fromAppStore: false),
        ])
        suite.expect(apps == ["/Applications/Tool.app/Contents/MacOS"],
                     "the quick step reads only the programs of recent apps, none from Apple or the App Store")
        let targets = Logic.protectionTargets(recentDownloads: recent, home: "/Users/a", recentApps: ["/Applications/New.app"])
        suite.expect(targets.first == "/Users/a/Downloads/newer" && targets.contains("/Library/LaunchDaemons")
            && targets.last == "/Applications/New.app" && !targets.contains("/Users/a/Downloads")
            && !targets.contains("/Users/a/Documents") && !targets.contains("/Users/a/Desktop"),
                     "protection looks at new downloads, startup items and new apps, never whole folders of documents")

        suite.expect(Logic.protection(installed: false, threats: 0) == .notInstalled
            && Logic.protection(installed: true, threats: 0) == .clean
            && Logic.protection(installed: true, threats: 2) == .threats(2),
                     "protection: not installed, clean, or threats to look at")

        suite.expect(!Logic.Plan().hasWork && Logic.Plan(cleanCount: 3, cleanBytes: 10).hasWork
            && Logic.Plan(jobs: [.dns]).hasWork,
                     "Run is offered only when there is junk to clean or a job due")

        let outcome = Logic.outcome(freed: 2_000, cleanFailed: 1, jobResults: [true, false])
        suite.expect(outcome == Logic.Outcome(freedBytes: 2_000, cleanFailed: 1, jobsDone: 1, jobsFailed: 1)
            && !outcome.nothingDone && Logic.outcome(freed: 0, cleanFailed: 0, jobResults: []).nothingDone,
                     "the summary counts what was freed and the jobs done and failed")
    }
}
