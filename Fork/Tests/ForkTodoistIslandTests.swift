// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

enum ForkTodoistIslandTests {
    typealias Logic = ForkTodoistLogic

    private static func task(_ id: String, _ content: String, priority: Int = 1, due: String? = nil,
                             checked: Bool? = nil) -> Logic.Item {
        Logic.Item(id: id, content: content, priority: priority,
                   due: due.map { Logic.Due(date: $0, string: nil, isRecurring: nil) }, checked: checked)
    }

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.showsIslandActivity(enabled: true, wanted: true, hasToken: true, hasTask: true)
            && !Logic.showsIslandActivity(enabled: true, wanted: true, hasToken: true, hasTask: false)
            && !Logic.showsIslandActivity(enabled: true, wanted: false, hasToken: true, hasTask: true)
            && !Logic.showsIslandActivity(enabled: false, wanted: true, hasToken: true, hasTask: true)
            && !Logic.showsIslandActivity(enabled: true, wanted: true, hasToken: false, hasTask: true),
                     "the closed island shows a task only when one is due there, connected and wanted")

        suite.expect(Logic.plainTitle("Lire [l'article](https://example.com/a) **vite**") == "Lire l'article vite"
            && Logic.plainTitle("  Appeler   Marie \n demain ") == "Appeler Marie demain"
            && Logic.plainTitle("Fix `build.sh` [a](b) et [c](d)") == "Fix build.sh a et c"
            && Logic.plainTitle("Crochet [seul") == "Crochet [seul",
                     "a title drops Todoist's markup and folds its spaces")

        let today = "2026-11-23"
        suite.expect(Logic.islandReading(task("5", String(repeating: "a", count: 40)))?.count == Logic.islandTitleLimit
            && Logic.islandReading(task("5", String(repeating: "a", count: 40)))?.hasSuffix("…") == true
            && Logic.islandReading(task("6", "Court")) == "Court"
            && Logic.islandReading(task("7", "  ")) == nil && Logic.islandReading(nil) == nil,
                     "a long title is cut with « … », an empty one shows nothing")

        let island = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                   safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 200)
        let bare = Logic.stripWing(title: nil, mark: nil, in: island)
        let timedWing = Logic.stripWing(title: nil, mark: "12:20", in: island)
        let titled = Logic.stripWing(title: "Appeler le client pour le devis", mark: "12:20", in: island)
        let fitted = island.compactCalendarGeometry(wing: titled)
        suite.expect(titled > timedWing && timedWing >= bare && bare > 0, "a time and a title widen the wings")
        suite.expect(fitted.compactActivitySize.width <= 180 + 2 * NotchGeometry.calendarWingRange.upperBound
            && fitted.compactActivitySize.width >= 180 + 2 * NotchGeometry.calendarWingRange.lowerBound,
                     "the wings stay within the calendar's bounds")

        let zone = TimeZone(identifier: "Europe/Paris")!
        let floating = Logic.dueMoment(Logic.Due(date: "2026-11-23T14:00:00", string: nil, isRecurring: nil), timeZone: zone)
        let fixed = Logic.dueMoment(Logic.Due(date: "2026-11-23T13:00:00Z", string: nil, isRecurring: nil), timeZone: zone)
        let dayOnly = Logic.dueMoment(Logic.Due(date: today, string: nil, isRecurring: nil), timeZone: zone)
        suite.expect(floating != nil && floating == fixed && dayOnly == nil,
                     "a time is read in the Mac's zone, or in UTC with « Z »; a day alone has none")

        let now = floating!.addingTimeInterval(30)
        let timed = [task("8", "Appel", due: "2026-11-23T14:00:00"), task("9", "Plus tard", due: "2026-11-23T15:00:00"),
                     task("10", "Avant", due: "2026-11-23T13:58:00"), task("11", "Jour", due: today),
                     task("12", "Coché", due: "2026-11-23T14:00:00", checked: true)]
        let due = Logic.reminders(timed, last: now.addingTimeInterval(-60), now: now, recalled: [], timeZone: zone)
        suite.expect(due.map(\.id) == ["8"], "only a task whose time just came is recalled")
        suite.expect(Logic.reminders(timed, last: now.addingTimeInterval(-60), now: now,
                                     recalled: [Logic.reminderKey(timed[0])], timeZone: zone).isEmpty,
                     "a task is recalled once for its time")
        suite.expect(Logic.reminderKey(task("8", "Appel", due: "2026-11-23T14:00:00"))
            != Logic.reminderKey(task("8", "Appel", due: "2026-11-23T16:00:00")),
                     "a task moved to a new time is recalled again")
        let woke = Logic.reminders(timed, last: now.addingTimeInterval(-6 * 3600), now: now, recalled: [], timeZone: zone)
        suite.expect(woke.map(\.id) == ["10", "8"], "after a long sleep only the last minutes are recalled, earliest first")
        suite.expect(Logic.reminders(timed, last: nil, now: now, recalled: [], timeZone: zone).map(\.id) == ["8"],
                     "at launch the last minute counts")

        // The closed island: the task being done, or a timed task near its time.
        let at = { (clock: String) in Logic.dueMoment(Logic.Due(date: "2026-11-23T\(clock):00", string: nil, isRecurring: nil),
                                                      timeZone: zone)! }
        let lead = Logic.islandLead(minutes: 15)
        let day = [task("20", "Jour entier", priority: 4, due: today), task("21", "Appel", due: "2026-11-23T14:00:00"),
                   task("22", "Réunion", due: "2026-11-23T14:30:00"), task("23", "Coché", due: "2026-11-23T13:50:00", checked: true),
                   task("24", "Hier soir", due: "2026-11-22T20:00:00")]
        func shown(_ clock: String, active: String? = nil, in list: [Logic.Item]? = nil) -> String? {
            Logic.islandTask(list ?? day, active: active, now: at(clock), lead: lead, timeZone: zone)?.id
        }
        suite.expect(shown("10:00") == nil && shown("13:44") == nil,
                     "far from any time, the closed island stays free, whole-day tasks included")
        suite.expect(shown("13:45") == "21" && shown("13:59") == "21",
                     "a timed task comes into the island its lead before")
        suite.expect(shown("14:10") == "21" && shown("14:16") == "22",
                     "a task gone stays until the next one comes")
        suite.expect(shown("14:31") == "22" && shown("15:00") == "22" && shown("15:01") == nil,
                     "an unticked task leaves the island half an hour after its time")
        suite.expect(shown("10:00", active: "20") == "20" && shown("14:16", active: "21") == "21"
            && shown("10:00", active: "23") == nil && shown("10:00", active: "gone") == nil,
                     "the task being done shows while it lasts, a ticked or missing one doesn't")
        suite.expect(Logic.islandTask(day, active: nil, now: at("13:56"), lead: Logic.islandLead(minutes: 5), timeZone: zone)?.id == "21"
            && Logic.islandTask(day, active: nil, now: at("13:54"), lead: Logic.islandLead(minutes: 5), timeZone: zone) == nil,
                     "the lead is the chosen one")
        suite.expect(Logic.islandLead(minutes: 60) == 3600 && Logic.islandLead(minutes: 0) == 900 && Logic.islandLead(minutes: 7) == 900,
                     "a lead outside the choices is the default quarter of an hour")
        suite.expect(Logic.islandMark(day[1]) == "14:00" && Logic.islandMark(day[0]) == nil && Logic.islandMark(nil) == nil,
                     "the mark carries the task's time, when it has one")

        suite.expect(Logic.isReminder(symbol: Logic.reminderSymbol) && !Logic.isReminder(symbol: "timer"),
                     "the reminder's notice is told apart by its mark")
        suite.expect(Logic.badge(0) == nil && Logic.badge(3) == "3" && Logic.badge(9) == "9" && Logic.badge(12) == "9+",
                     "the tile's count: nothing at zero, « 9+ » past nine")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkTodoistIslandActivity] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkTodoistReminders] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkTodoistIslandLead] as? Int == Logic.defaultIslandLead,
                     "the island's tasks and the reminders are on by default, a quarter of an hour ahead")
    }
}
