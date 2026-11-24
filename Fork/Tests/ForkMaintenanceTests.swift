// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9d: the maintenance jobs, their commands and the reading of their results.
enum ForkMaintenanceTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkMaintenanceLogic

        suite.expect(Logic.Job.allCases == [.dns, .launchServices, .memory, .spotlight],
                     "four jobs: DNS, Open With, memory, Spotlight")
        suite.expect(Logic.Job.allCases.filter(\.needsAdministrator) == [.dns, .memory, .spotlight],
                     "all but Open With need the administrator password")
        suite.expect(Logic.Job.allCases.filter(\.asksConfirmation) == [.spotlight],
                     "only reindexing Spotlight asks first")

        suite.expect(Logic.selection(stored: nil) == [.dns, .launchServices],
                     "the DNS and Open With are checked the first time, memory and Spotlight are not")
        suite.expect(Logic.selection(stored: ["spotlight", "gone", "dns"]) == [.dns, .spotlight]
            && Logic.stored([.spotlight, .dns]) == ["dns", "spotlight"]
            && Logic.selection(stored: []) == [],
                     "the selection is kept in the catalog's order, unknown names dropped")

        let commands = Logic.Job.allCases.compactMap(Logic.administratorCommand)
        suite.expect(commands.count == 3 && Logic.administratorCommand(.launchServices) == nil
            && commands.allSatisfy { $0.hasPrefix("/usr/") },
                     "administrator commands by absolute path, Open With runs as the user")
        suite.expect(Logic.administratorCommand(.spotlight)?.contains("/System/Volumes/Data") == true,
                     "Spotlight reindexes the data volume, where the files are")
        suite.expect(Logic.launchServicesRuns == [["-gc"], ["-f", "-apps", "local,user"]]
            && Logic.lsregisterPath.hasSuffix("/LaunchServices.framework/Support/lsregister"),
                     "Open With: the database compacted, then the Applications folders registered again")

        suite.expect(Logic.administratorScript([.launchServices]) == nil && Logic.administratorScript([]) == nil,
                     "no password asked when no job needs it")
        let script = Logic.administratorScript([.spotlight, .launchServices, .dns]) ?? ""
        suite.expect(script == "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder; "
            + "echo \"maintenance-result dns $?\"; "
            + "/usr/bin/mdutil -E / /System/Volumes/Data; echo \"maintenance-result spotlight $?\"; exit 0",
                     "one shell for the password jobs, each followed by its result, always ending well")
        let source = AdminShell.appleScriptSource(command: script, prompt: "p")
        suite.expect(source.contains("echo \\\"maintenance-result dns $?\\\"")
            && source.hasSuffix("with administrator privileges with prompt \"p\""),
                     "the shell travels quoted inside AppleScript's do shell script")

        let jobs: [Logic.Job] = [.dns, .memory, .spotlight, .launchServices]
        let output = "/:\r\tIndexing enabled. \rmaintenance-result dns 0\rmaintenance-result memory 1\r"
            + "maintenance-result spotlight 0\n"
        suite.expect(Logic.administratorOutcome(status: 0, output: output, jobs: jobs)
            == .done([.dns: true, .memory: false, .spotlight: true]),
                     "each job's result is read, whatever the line ends and the jobs' own output")
        suite.expect(Logic.administratorOutcome(status: 0, output: "maintenance-result dns 0", jobs: [.dns, .memory])
            == .done([.dns: true, .memory: false]),
                     "a job with no result line failed")
        suite.expect(Logic.administratorOutcome(status: 1, output: "execution error: User canceled. (-128)", jobs: jobs)
            == .cancelled,
                     "a dismissed password prompt runs nothing")
        suite.expect(Logic.administratorOutcome(status: 1, output: "execution error: (-60007)", jobs: jobs) == .failed,
                     "any other refusal is a failure")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runs: [Logic.Job: Date] = [.dns: now, .spotlight: now.addingTimeInterval(-86_400)]
        suite.expect(Logic.lastRuns(stored: Logic.stored(runs)) == runs
            && Logic.lastRuns(stored: ["gone": 1, "memory": 5]) == [.memory: Date(timeIntervalSince1970: 5)]
            && Logic.lastRuns(stored: nil).isEmpty,
                     "the last runs are kept by name, unknown names dropped")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkMaintenanceSelection] as? [String]
            == ["dns", "launchServices"],
                     "the default selection travels in settings backups")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkMaintenanceLastRuns] == nil,
                     "the last runs are this Mac's state, kept out of backups")
    }
}
