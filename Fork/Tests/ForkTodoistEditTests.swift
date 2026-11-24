// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

enum ForkTodoistEditTests {
    typealias Logic = ForkTodoistLogic

    private static func json(_ data: Data?) -> [String: Any] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!

        let added = Logic.addedTask(from: Data(#"{"id": "6Ab12", "content": "Appeler Marie", "priority": 1, "due": null}"#.utf8))
        let dated = Logic.addedTask(from: Data(#"{"id": "6Ab13", "content": "Relancer", "priority": 1, "due": {"date": "2026-11-24"}}"#.utf8))
        suite.expect(added.map(Logic.needsToday) == true && dated.map(Logic.needsToday) == false
            && Logic.addedTask(from: Data("[]".utf8)) == nil && Logic.addedTask(from: nil) == nil
            && Logic.addedTask(from: Data(repeating: 32, count: Logic.maximumSize + 1)) == nil,
                     "a task added without a date is given today; one with a date keeps it")
        suite.expect(json(Logic.todayBody())["due_string"] as? String == "today"
            && json(Logic.todayBody())["due_lang"] as? String == "en",
                     "today is said in Todoist's English wording")
        suite.expect(Logic.taskURL("6X7r")?.absoluteString == "https://api.todoist.com/api/v1/tasks/6X7r"
            && Logic.moveURL("6X7r")?.path == "/api/v1/tasks/6X7r/move"
            && Logic.reopenURL("6X7r")?.path == "/api/v1/tasks/6X7r/reopen"
            && Logic.taskURL("../x") == nil && Logic.reopenURL("a b") == nil,
                     "a task's addresses take only a clean id")
        let history = Logic.completedURL(now: now, cursor: "a.b")?.absoluteString ?? ""
        suite.expect(history.contains("tasks/completed/by_completion_date?") && history.contains("since=2026-10-24T08:00:00Z")
            && history.contains("cursor=a.b") && history.contains("limit=200"),
                     "the done tasks are asked for the last 30 days")
        suite.expect(Logic.projectsURL(cursor: nil)?.absoluteString == "https://api.todoist.com/api/v1/projects?limit=200",
                     "the projects are listed by pages of 200")

        let projects = Logic.projects(from: Data("""
        {"results": [{"id": "p1", "name": "Inbox", "inbox_project": true}, {"id": "p2", "name": "Travail"}], "next_cursor": null}
        """.utf8))
        suite.expect(projects?.results.map(\.name) == ["Inbox", "Travail"] && projects?.results.first?.isInbox == true
            && projects?.results.last?.isInbox == false && projects?.nextCursor == nil,
                     "projects and the inbox are read")
        let done = Logic.completed(from: Data("""
        {"items": [
          {"id": "a", "content": "Hier soir", "priority": 1, "due": null, "checked": true, "completed_at": "2026-11-22T22:30:00.000000Z"},
          {"id": "b", "content": "Ce matin", "priority": 4, "due": null, "checked": true, "completed_at": "2026-11-23T07:10:00Z"},
          {"id": "c", "content": "Hier", "priority": 1, "due": null, "checked": true, "completed_at": "2026-11-22T09:00:00Z"}
        ]}
        """.utf8))
        let days = Logic.doneByDay(done?.items ?? [], calendar: calendar)
        suite.expect(days.map(\.day) == ["2026-11-23", "2026-11-22"] && days.first?.tasks.map(\.id) == ["b"]
            && days.last?.tasks.map(\.id) == ["a", "c"],
                     "done tasks group by the local day they were ticked, latest first")

        suite.expect(Logic.apiPriority(level: 1) == 4 && Logic.apiPriority(level: 4) == 1 && Logic.apiPriority(level: 9) == 1,
                     "P1 is the API's 4")

        var draft = Logic.Draft(content: "  Appeler Marie  ", level: 1)
        suite.expect(json(Logic.createBody(draft, calendar: calendar, now: now)) as NSDictionary
            == ["content": "Appeler Marie", "priority": 4] as NSDictionary,
                     "a task without date, notes or project sends its title and urgency")
        draft.description = "Devis site"
        draft.projectID = "p2"
        draft.day = tomorrow
        suite.expect(json(Logic.createBody(draft, calendar: calendar, now: now)) as NSDictionary
            == ["content": "Appeler Marie", "priority": 4, "description": "Devis site", "project_id": "p2",
                "due_date": "2026-11-24"] as NSDictionary,
                     "a day alone makes a whole-day task, with notes and project")
        draft.minutes = 14 * 60 + 30
        suite.expect(json(Logic.createBody(draft, calendar: calendar, now: now))["due_datetime"] as? String == "2026-11-24T13:30:00Z",
                     "a time in Paris is sent in UTC")
        suite.expect(Logic.createBody(Logic.Draft(content: "   "), calendar: calendar, now: now) == nil,
                     "an empty title makes nothing")

        suite.expect(Logic.recurrence(.daily, day: today, calendar: calendar, now: now) == "every day"
            && Logic.recurrence(.daily, day: tomorrow, calendar: calendar, now: now) == "every day starting 2026-11-24"
            && Logic.recurrence(.weekly([.friday, .monday]), day: today, calendar: calendar, now: now) == "every mon, fri"
            && Logic.recurrence(.weekly([]), day: tomorrow, calendar: calendar, now: now) == "every tue starting 2026-11-24"
            && Logic.recurrence(.monthly, day: today, calendar: calendar, now: now) == "every 23rd"
            && Logic.recurrence(.yearly, day: tomorrow, calendar: calendar, now: now) == "every nov 24th"
            && Logic.recurrence(.never, day: today, calendar: calendar, now: now) == nil,
                     "a repetition is written in Todoist's English")
        suite.expect(Logic.ordinal(1) == "1st" && Logic.ordinal(2) == "2nd" && Logic.ordinal(3) == "3rd" && Logic.ordinal(11) == "11th"
            && Logic.ordinal(12) == "12th" && Logic.ordinal(21) == "21st" && Logic.ordinal(22) == "22nd" && Logic.ordinal(31) == "31st",
                     "ordinals follow English")
        var weekly = Logic.Draft(content: "Sport", day: today, minutes: 7 * 60, repeats: .weekly([.monday, .wednesday]))
        suite.expect(Logic.dueFields(weekly, changing: false, calendar: calendar, now: now)
            == ["due_string": "every mon, wed at 07:00", "due_lang": "en"],
                     "a repeating task at a time")
        weekly.repeats = .never
        weekly.day = nil
        suite.expect(Logic.dueFields(weekly, changing: true, calendar: calendar, now: now) == ["due_string": "no date", "due_lang": "en"]
            && Logic.dueFields(weekly, changing: false, calendar: calendar, now: now).isEmpty,
                     "removing the date is said only when changing a task")

        let task = Logic.Item(id: "6X7r", content: "Appeler Marie", priority: 4,
                              due: Logic.Due(date: "2026-11-23T10:00:00", string: "chaque lundi 10h", isRecurring: true),
                              checked: false, description: "Devis", projectID: "p1")
        let form = Logic.draft(for: task, calendar: calendar)
        suite.expect(form.content == "Appeler Marie" && form.description == "Devis" && form.level == 1 && form.projectID == "p1"
            && form.day == today && form.minutes == 600 && form.repeats == .never && !form.dueChanged,
                     "a task opens in the form as it is")
        suite.expect(Logic.updateBody(form, from: task, calendar: calendar, now: now) == nil,
                     "an unchanged task sends nothing, its repetition kept")
        var changed = form
        changed.level = 3
        changed.content = "Appeler Marie demain"
        suite.expect(json(Logic.updateBody(changed, from: task, calendar: calendar, now: now)) as NSDictionary
            == ["content": "Appeler Marie demain", "priority": 2] as NSDictionary,
                     "only what changed is sent")
        changed.dueChanged = true
        changed.day = nil
        changed.minutes = nil
        suite.expect(json(Logic.updateBody(changed, from: task, calendar: calendar, now: now))["due_string"] as? String == "no date",
                     "a removed date is cleared")
        suite.expect(json(Logic.moveBody(projectID: "p2", from: task)) as NSDictionary == ["project_id": "p2"] as NSDictionary
            && Logic.moveBody(projectID: "p1", from: task) == nil && Logic.moveBody(projectID: nil, from: task) == nil,
                     "a task moves only to another project")

        let fixed = Logic.Due(date: "2026-11-23T22:30:00Z", string: nil, isRecurring: nil)
        suite.expect(fixed.day == Logic.dayString(Logic.dueMoment(fixed)!) && fixed.time != nil,
                     "a fixed time is shown in the Mac's own zone")
        suite.expect(Logic.undoDelay == 5, "a deleted task can be put back for five seconds")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkTodoistActiveTask] == nil,
                     "the task being done is not a setting")
    }
}
