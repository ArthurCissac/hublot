// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9d, maintenance: one-off upkeep jobs run on request, the way
/// CleanMyMac offers them. The jobs that need administrator rights run
/// together in one shell, behind one password prompt from macOS. Pure: the
/// selection and the shell's output come in, commands and results go out.
///
/// Left out on purpose: the "maintenance scripts" (`periodic` no longer
/// exists on macOS 27, which does that upkeep by itself), thinning local
/// Time Machine snapshots (the ones on this Mac belong to macOS updates and
/// must stay), and compacting Mail's database (full disk access, Mail's data).
enum ForkMaintenanceLogic {
    enum Job: String, CaseIterable, Identifiable {
        case dns, launchServices, memory, spotlight

        var id: String { rawValue }

        /// The password is asked once for all the jobs that need it.
        var needsAdministrator: Bool { self != .launchServices }

        /// Reindexing leaves search incomplete for hours: asked first.
        var asksConfirmation: Bool { self == .spotlight }

        var symbol: String {
            switch self {
            case .dns: return "network"
            case .launchServices: return "square.stack.3d.up"
            case .memory: return "memorychip"
            case .spotlight: return "magnifyingglass"
            }
        }
    }

    /// Checked the first time: the two quick jobs with nothing to regret.
    static let defaultSelection: [Job] = [.dns, .launchServices]

    /// What was checked last time, in the catalog's order; names this
    /// version does not know are dropped.
    static func selection(stored: [String]?) -> [Job] {
        guard let stored else { return defaultSelection }
        let names = Set(stored)
        return Job.allCases.filter { names.contains($0.rawValue) }
    }

    static func stored(_ selection: [Job]) -> [String] {
        Job.allCases.filter(selection.contains).map(\.rawValue)
    }

    /// The command a job runs as administrator, absolute paths only.
    static func administratorCommand(_ job: Job) -> String? {
        switch job {
        case .dns: return "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"
        case .memory: return "/usr/sbin/purge"
        // The system volume and the data volume each keep their own index;
        // the files people search for live on the data volume.
        case .spotlight: return "/usr/bin/mdutil -E / /System/Volumes/Data"
        case .launchServices: return nil
        }
    }

    /// Launch Services, as the user: the database compacted, then the apps of
    /// the local and user Applications folders registered again, which drops
    /// duplicates and vanished apps from "Open With".
    static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    static let launchServicesRuns: [[String]] = [["-gc"], ["-f", "-apps", "local,user"]]

    /// Each job's line in the shell's output: "maintenance-result <job> <status>".
    static let marker = "maintenance-result"

    /// One shell for every administrator job checked, each followed by its
    /// result line. It always ends well, so one failing job never hides how
    /// the others went; nil when none needs the password.
    static func administratorScript(_ jobs: [Job]) -> String? {
        let parts = Job.allCases.filter(jobs.contains).compactMap { job in
            administratorCommand(job).map { "\($0); echo \"\(marker) \(job.rawValue) $?\"" }
        }
        guard !parts.isEmpty else { return nil }
        return (parts + ["exit 0"]).joined(separator: "; ")
    }

    enum Outcome: Equatable {
        /// The password was given; each job's success.
        case done([Job: Bool])
        /// The password prompt was dismissed: nothing ran.
        case cancelled
        /// The prompt could not run, or the password was refused.
        case failed
    }

    /// Reads osascript's answer. `do shell script` turns line ends into
    /// carriage returns, so both count; a job with no result line failed.
    static func administratorOutcome(status: Int32, output: String, jobs: [Job]) -> Outcome {
        guard status == 0 else { return output.contains("(-128)") ? .cancelled : .failed }
        var results: [Job: Bool] = [:]
        for line in output.components(separatedBy: .newlines) {
            let words = line.split(separator: " ")
            guard words.count == 3, words[0] == Substring(marker),
                  let job = Job(rawValue: String(words[1])), let code = Int32(words[2]) else { continue }
            results[job] = code == 0
        }
        for job in jobs where job.needsAdministrator && results[job] == nil {
            results[job] = false
        }
        return .done(results)
    }

    /// When each job last went well, as stored: seconds since 1970 by name.
    static func lastRuns(stored: [String: Double]?) -> [Job: Date] {
        var runs: [Job: Date] = [:]
        for (name, seconds) in stored ?? [:] {
            if let job = Job(rawValue: name) { runs[job] = Date(timeIntervalSince1970: seconds) }
        }
        return runs
    }

    static func stored(_ runs: [Job: Date]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: runs.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
    }
}
