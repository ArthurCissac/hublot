// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9f, the one-click scan: cleaning, protection and performance in one
/// pass, then one "Run" for what is safe to do without a second look. Pure:
/// dates, paths and counts come in, the steps, what is due and the summaries
/// go out.
enum ForkSmartScanLogic {
    typealias Job = ForkMaintenanceLogic.Job

    enum Step: Int, CaseIterable, Equatable {
        case cleaning, protection, performance
    }

    /// The ring while scanning: each step a third, the protection step
    /// filling its third as places are scanned.
    static func progress(step: Step, fraction: Double = 0) -> Double {
        let share = 1 / Double(Step.allCases.count)
        return min(1, (Double(step.rawValue) + min(1, max(0, fraction))) * share)
    }

    /// The maintenance jobs a scan may recommend. Freeing memory and
    /// reindexing Spotlight are never offered unasked: the first does little,
    /// the second leaves search incomplete for hours.
    static let offeredJobs: [Job] = [.dns, .launchServices]

    /// A job is due when it never ran or last ran this long ago.
    static let dueAfter: TimeInterval = 30 * 24 * 3600

    static func dueJobs(lastRuns: [Job: Date], now: Date) -> [Job] {
        offeredJobs.filter { job in
            guard let last = lastRuns[job] else { return true }
            return now.timeIntervalSince(last) >= dueAfter
        }
    }

    /// The protection step looks where malware lands, and only at what is
    /// new, so it stays quick whatever the size of the folders: what arrived
    /// in Downloads this month, what starts by itself and the apps added this
    /// month. The antivirus's own scans still read everything.
    static func protectionTargets(recentDownloads: [String], home: String, recentApps: [String]) -> [String] {
        recentDownloads + ["\(home)/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
            + recentApps
    }

    /// A recent app, as the quick protection step sees it.
    struct RecentApp: Equatable {
        let path: String
        let bundleID: String?
        /// It carries a Mac App Store receipt: reviewed and sandboxed by Apple.
        let fromAppStore: Bool
    }

    /// The quick step reads only the programs of recent apps (their
    /// Contents/MacOS), and none from Apple or the Mac App Store: whole
    /// bundles such as Xcode made it last a quarter of an hour. The
    /// antivirus's own scans still read whole apps.
    static func quickAppTargets(_ apps: [RecentApp]) -> [String] {
        apps.filter { app in
            !app.fromAppStore && !(app.bundleID?.hasPrefix("com.apple.") ?? false)
        }
        .map { "\($0.path)/Contents/MacOS" }
    }

    /// How far back the protection step looks in Downloads, and at most how
    /// many items it takes from there, newest first.
    static let recentWindow: TimeInterval = 30 * 24 * 3600
    static let recentLimit = 400

    /// The items of Downloads that arrived within the window, newest first;
    /// a folder that arrived (an unzipped download) is read whole.
    static func recentDownloads(_ entries: [(path: String, arrived: Date)], now: Date) -> [String] {
        entries.filter { now.timeIntervalSince($0.arrived) <= recentWindow }
            .sorted { $0.arrived > $1.arrived }
            .prefix(recentLimit)
            .map(\.path)
    }

    /// What the protection step found.
    enum Protection: Equatable {
        case notInstalled
        case clean
        case threats(Int)
    }

    static func protection(installed: Bool, threats: Int) -> Protection {
        guard installed else { return .notInstalled }
        return threats > 0 ? .threats(threats) : .clean
    }

    /// What "Run" would do: the junk the cleaner checks by itself (never the
    /// Trash, leftovers, device backups nor screenshots, which upstream's
    /// cleaner leaves unchecked) and the jobs due. Threats are never handled
    /// here: they wait for a look in the antivirus.
    struct Plan: Equatable {
        var cleanCount = 0
        var cleanBytes: Int64 = 0
        var jobs: [Job] = []

        var hasWork: Bool { cleanCount > 0 || !jobs.isEmpty }
    }

    /// How a run went, for its summary.
    struct Outcome: Equatable {
        var freedBytes: Int64 = 0
        var cleanFailed = 0
        var jobsDone = 0
        var jobsFailed = 0

        var nothingDone: Bool { freedBytes == 0 && jobsDone == 0 }
    }

    static func outcome(freed: Int64, cleanFailed: Int, jobResults: [Bool]) -> Outcome {
        Outcome(freedBytes: freed, cleanFailed: cleanFailed,
                jobsDone: jobResults.filter { $0 }.count, jobsFailed: jobResults.filter { !$0 }.count)
    }
}
