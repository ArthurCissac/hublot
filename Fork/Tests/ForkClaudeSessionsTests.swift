// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The AI page's Claude additions (ForkClaudeSessionsLogic, ForkAgentCardsLogic).
enum ForkClaudeSessionsTests {
    typealias Logic = ForkClaudeSessionsLogic

    static func run(_ suite: TestSuite) {
        sessions(suite)
        time(suite)
        projects(suite)
        cards(suite)
        appSessions(suite)
    }

    private static func appSessions(_ suite: TestSuite) {
        let file = #"{"sessionId":"local_abc-1","cliSessionId":"x","cwd":"/Users/me/Shop","originCwd":"/Users/me/Shop","lastActivityAt":1795521482611,"isArchived":false,"title":"Shop"}"#
        let read = Logic.appSession(from: Data(file.utf8))
        suite.expect(read == Logic.AppSession(id: "local_abc-1", cwd: "/Users/me/Shop", origin: "/Users/me/Shop",
                                              lastActivity: Date(timeIntervalSince1970: 1795521482.611), archived: false)
            && Logic.appSession(from: Data(#"{"sessionId":"bad id","cwd":"/x"}"#.utf8)) == nil
            && Logic.appSession(from: Data(#"{"sessionId":"local_a","cwd":"relative"}"#.utf8)) == nil,
                     "a Claude app session file reads its id, folders and last activity; odd ones are left out")
        let old = Logic.AppSession(id: "local_old", cwd: "/Users/me/Shop", lastActivity: Date(timeIntervalSince1970: 100))
        let tree = Logic.AppSession(id: "local_tree", cwd: "/Users/me/Shop/.claude/worktrees/fix", origin: "/Users/me/Shop",
                                    lastActivity: Date(timeIntervalSince1970: 300))
        let archived = Logic.AppSession(id: "local_gone", cwd: "/Users/me/Shop", lastActivity: Date(timeIntervalSince1970: 900), archived: true)
        let other = Logic.AppSession(id: "local_other", cwd: "/Users/me/Shopping", lastActivity: Date(timeIntervalSince1970: 999))
        let all = [old, tree, archived, other]
        suite.expect(Logic.latestAppSession(forFolder: "/Users/me/Shop", in: all)?.id == "local_tree"
            && Logic.latestAppSession(named: "Shop", in: all)?.id == "local_tree"
            && Logic.latestAppSession(named: "Shopping", in: all)?.id == "local_other"
            && Logic.latestAppSession(named: "Nowhere", in: all) == nil,
                     "a project opens its most recent session, a work tree's included, never an archived one")
        suite.expect(Logic.folder(named: "Shop", in: all) == "/Users/me/Shop", "a project's folder is found by its name")
    }

    private static func record(_ fields: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    private static func sessions(_ suite: TestSuite) {
        let waiting = Logic.session(from: record([
            "pid": 4242, "sessionId": "abc", "cwd": "/Users/me/Projects/Shop", "name": "Fix the cart",
            "status": "waiting", "waitingFor": "input needed", "entrypoint": "claude-desktop",
            "statusUpdatedAt": 1_700_000_000_000.0,
        ]))
        suite.expect(waiting == Logic.Session(id: "abc", pid: 4242, name: "Fix the cart", cwd: "/Users/me/Projects/Shop",
                                              status: .waiting, waitingFor: "input needed", host: .claudeApp,
                                              since: Date(timeIntervalSince1970: 1_700_000_000)),
                     "a session's record gives its state, name, folder, app and since when")
        let cli = Logic.session(from: record(["pid": 7, "sessionId": "x", "cwd": "/Users/me/Blog", "status": "busy", "entrypoint": "cli"]))
        suite.expect(cli?.host == .terminal && cli?.name == "Blog" && cli?.since == nil,
                     "without a name the folder names it; outside the Claude app it runs in a terminal")
        suite.expect(Logic.session(from: record(["pid": 7, "sessionId": "x", "status": "sleeping"])) == nil
            && Logic.session(from: record(["sessionId": "x", "status": "idle"])) == nil
            && Logic.session(from: record(["pid": 7, "sessionId": "", "status": "idle"])) == nil
            && Logic.session(from: Data("{\"pid\": 7, \"sess".utf8)) == nil,
                     "a record with an unknown state, no process, no id or half written is ignored")

        suite.expect(Logic.wait("input needed") == .question && Logic.wait("goal proposal") == .plan
            && Logic.wait("dialog open") == .answer && Logic.wait(nil) == .answer,
                     "what a session waits for reads from its record, an answer when unclear")

        func session(_ id: String, _ status: Logic.Status, pid: Int32, since: TimeInterval?) -> Logic.Session {
            Logic.Session(id: id, pid: pid, name: id, cwd: "/p/\(id)", status: status, waitingFor: nil, host: .claudeApp,
                          since: since.map { Date(timeIntervalSince1970: $0) })
        }
        let all = [session("late", .waiting, pid: 1, since: 200), session("early", .waiting, pid: 2, since: 100),
                   session("dead", .waiting, pid: 3, since: 50), session("busy", .busy, pid: 4, since: 10)]
        suite.expect(Logic.waiting(all, isRunning: { $0 != 3 }).map(\.id) == ["early", "late"],
                     "only waiting sessions whose process runs, the longest waiting first")

        let now = Date(timeIntervalSince1970: 205)
        let fresh = Logic.toAnnounce(Logic.waiting(all, isRunning: { $0 != 3 }), announced: [], now: now)
        suite.expect(fresh.map(\.id) == ["early", "late"]
            && Logic.toAnnounce([session("new", .waiting, pid: 1, since: 204)], announced: [], now: now).isEmpty,
                     "a wait gets a notice once it lasted a few seconds")
        let once = session("early", .waiting, pid: 2, since: 100)
        let again = session("early", .waiting, pid: 2, since: 180)
        suite.expect(Logic.toAnnounce([once], announced: [Logic.key(once)], now: now).isEmpty
            && Logic.toAnnounce([again], announced: [Logic.key(once)], now: now).count == 1,
                     "a wait is announced once, the next wait of the same session again")
        suite.expect(Logic.isNotice(symbol: Logic.noticeSymbol) && !Logic.isNotice(symbol: "checkmark"),
                     "the notice is recognised by its symbol")

        let app = Logic.session(from: record(["pid": 9, "sessionId": "s", "cwd": "/Users/me/Shop", "status": "idle",
                                              "entrypoint": "claude-desktop", "hostSessionId": "local_ab12-cd34"]))
        suite.expect(app?.appSession == "local_ab12-cd34"
            && Logic.session(from: record(["pid": 9, "sessionId": "s", "status": "idle", "hostSessionId": "evil&x=1"]))?.appSession == nil,
                     "the Claude app's id for a session is kept only when its links accept it")
        suite.expect(Logic.continueURL(appSession: "local_ab12-cd34")?.absoluteString == "claude://code/continue?session=local_ab12-cd34"
            && Logic.continueURL(appSession: "session_x") == nil,
                     "a Claude app session opens by its own link")
        let new = Logic.newSessionURL(folder: "/Users/me/Mes Projets/Café & Co")
        let folder = new.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "folder" }?.value
        suite.expect(new?.scheme == "claude" && new?.host == "code" && new?.path == "/new"
            && folder == "/Users/me/Mes Projets/Café & Co" && Logic.newSessionURL(folder: "relative") == nil,
                     "a new session opens in a folder, its path carried whole")

        func appSession(_ id: String, cwd: String, since: TimeInterval, app: String? = "local_1") -> Logic.Session {
            Logic.Session(id: id, pid: 1, name: id, cwd: cwd, status: .idle, waitingFor: nil, host: .claudeApp,
                          since: Date(timeIntervalSince1970: since), appSession: app)
        }
        let running = [appSession("old", cwd: "/Users/me/Shop", since: 10), appSession("tree", cwd: "/Users/me/Shop/.claude/worktrees/a", since: 20),
                       appSession("other", cwd: "/Users/me/Shopify", since: 30), appSession("cli", cwd: "/Users/me/Shop", since: 40, app: nil)]
        suite.expect(Logic.openSession(for: "/Users/me/Shop", in: running)?.id == "tree"
            && Logic.openSession(for: "/Users/me/Blog", in: running) == nil
            && Logic.openSession(for: "/Users/me/Shopify", in: running)?.id == "other",
                     "a project opens in the latest Claude app session in its folder or below, not a neighbour's")
    }

    private static func time(_ suite: TestSuite) {
        let base = Date(timeIntervalSince1970: 1_000_000)
        func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
        suite.expect(Logic.activeTime([at(0), at(2), at(5)]) == 5 * 60
            && Logic.activeTime([at(5), at(0), at(2)]) == 5 * 60,
                     "requests close together count the time between them, in any order")
        suite.expect(Logic.activeTime([at(0), at(4), at(30), at(31)]) == 5 * 60
            && Logic.activeTime([at(0)]) == 0 && Logic.activeTime([]) == 0,
                     "a gap longer than ten minutes is a pause, a lone request no time")

        let requests: [(project: String, date: Date)] = [
            ("Shop", at(0)), ("Shop", at(6)), ("Shop", at(12)), ("Blog", at(1)), ("Blog", at(3)),
            ("", at(2)), ("", at(4)), ("Old", at(-500)), ("Old", at(-498)),
        ]
        let times = Logic.projectTimes(requests, from: at(-10), to: at(60))
        suite.expect(times == [Logic.ProjectTime(project: "Shop", seconds: 12 * 60), Logic.ProjectTime(project: "Blog", seconds: 2 * 60)],
                     "projects by time in the period, most first, nameless and earlier requests left out")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
        suite.expect(Logic.start(of: 1, now: noon, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
            && Logic.start(of: 7, now: noon, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))!,
                     "today starts at midnight, the week six days before")
        suite.expect(Logic.ago(20, french: true) == "à l’instant" && Logic.ago(8 * 60, french: true) == "8 min"
            && Logic.ago(2 * 3600 + 60, french: true) == "2 h" && Logic.ago(3 * 86_400, french: true) == "3 j"
            && Logic.ago(3 * 86_400, french: false) == "3 d" && Logic.ago(-50, french: false) == "now",
                     "how long ago reads short, never negative")
        suite.expect(Logic.duration(30) == "< 1 min" && Logic.duration(45 * 60) == "45 min" && Logic.duration(125 * 60) == "2 h 05",
                     "durations read in minutes, then hours and minutes")
    }

    private static func projects(_ suite: TestSuite) {
        suite.expect(Logic.isProject("/Users/me/Documents/Shop")
            && !Logic.isProject("/Users/me/Library/Application Support/Claude/scratch-workspaces/a/b/scratch-1")
            && !Logic.isProject("/private/tmp/claude-501/x/scratchpad/wt")
            && !Logic.isProject("/Users/me/Shop/.claude/worktrees/feature")
            && !Logic.isProject("/") && !Logic.isProject("relative/path"),
                     "scratch spaces, temporary folders and single-session work trees are not projects")
        let day = Date(timeIntervalSince1970: 2_000_000)
        let candidates: [(path: String, date: Date)] = [
            ("/Users/me/Shop", day), ("/Users/me/Shop/", day.addingTimeInterval(60)), ("/Users/me/Blog", day.addingTimeInterval(30)),
            ("/Users/me/Gone", day.addingTimeInterval(90)), ("/private/tmp/x", day.addingTimeInterval(120)),
            ("/Users/me/App", day.addingTimeInterval(10)), ("/Users/me/Old", day.addingTimeInterval(-60)),
        ]
        let recent = Logic.recentProjects(candidates, exists: { $0 != "/Users/me/Gone" })
        suite.expect(recent.map(\.name) == ["Shop", "Blog", "App"] && recent.first?.lastActivity == day.addingTimeInterval(60),
                     "the three latest existing projects, one entry per folder, most recent first")

        let head = """
        {"type":"summary","summary":"x"}
        {"type":"user","cwd":"/Users/me/Shop","sessionId":"s"}
        {"type":"assistant","cwd":"/Users/me/Other"}
        """
        suite.expect(Logic.workingFolder(inLogHead: head) == "/Users/me/Shop"
            && Logic.workingFolder(inLogHead: "{\"type\":\"summary\"}\n{\"cwd\":") == nil,
                     "a log's working folder is the first one it names")
    }

    private static func cards(_ suite: TestSuite) {
        let cards: [NotchAgentCard] = [.limits, .spend, .forkWaiting, .forkTime]
        suite.expect(ForkAgentCardsLogic.arranged(cards, waiting: true) == [.forkWaiting, .limits, .spend, .forkTime]
            && ForkAgentCardsLogic.arranged(cards, waiting: false) == [.limits, .spend, .forkTime]
            && ForkAgentCardsLogic.arranged([.limits, .forkTime], waiting: true) == [.limits, .forkTime],
                     "the Waiting card comes first while a session waits, not at all otherwise or when hidden")
        suite.expect(NotchAgentCard.forkTime.followsPeriod && !NotchAgentCard.forkResume.followsPeriod
            && !NotchAgentCard.forkWaiting.followsPeriod,
                     "the time per project follows the chosen period")
        let symbols = NotchAgentCard.allCases.map(\.symbol)
        suite.expect(Set(symbols).count == symbols.count,
                     "every card of the AI page has its own symbol")
        suite.expect([NotchAgentCard.forkWaiting, .forkTime, .forkResume].allSatisfy {
            ForkAgentCardsLogic.title($0, french: true) != $0.rawValue && ForkAgentCardsLogic.title($0, french: false) != $0.rawValue
                && ForkAgentCardsLogic.title($0, french: true) != ForkAgentCardsLogic.title($0, french: false)
        },
                     "the fork's cards are named in French and English")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkAgentsWaitingAlert] as? Bool == true
            && SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkAgentsWaitingAlert),
                     "the waiting notice is on out of the box and travels in backups")
    }
}
