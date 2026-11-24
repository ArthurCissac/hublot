// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Todoist in Hublot: the API's addresses and answers, the order of the
/// day's tasks, the quick add, the token and when to reload.
enum ForkTodoistTests {
    typealias Logic = ForkTodoistLogic

    private static let sample = """
    {"results": [
      {"id": "6X7rM8997g3RQmvh", "content": "Appeler Marie", "priority": 4, "checked": false,
       "due": {"date": "2026-11-23T10:00:00", "string": "aujourd'hui 10h", "is_recurring": false, "lang": "fr"},
       "project_id": "6Jf8VQXxpwv56VQ7", "labels": []},
      {"id": "7Y8sN9008h4SRnwi", "content": "Relancer le devis", "priority": 1, "checked": false,
       "due": {"date": "2026-11-21", "string": "21 nov.", "is_recurring": false}},
      {"id": "8Z9tP0119i5TSoxj", "content": "Poster la photo", "priority": 3, "checked": false,
       "due": {"date": "2026-11-23", "string": "chaque vendredi", "is_recurring": true}},
      {"id": "9A0uQ1220j6UTpyk", "content": "Déjà faite", "priority": 4, "checked": true,
       "due": {"date": "2026-11-23"}}
    ], "next_cursor": "abc123"}
    """

    static func run(_ suite: TestSuite) {
        let page = Logic.page(from: Data(sample.utf8))
        suite.expect(page?.results.count == 4 && page?.nextCursor == "abc123"
            && Logic.page(from: Data("{}".utf8)) == nil && Logic.page(from: Data(repeating: 32, count: Logic.maximumSize + 1)) == nil,
                     "a page of tasks and its cursor are read; anything else or oversized is refused")
        guard let tasks = page?.results else { return }
        let urgent = tasks[0], late = tasks[1], recurring = tasks[2]
        suite.expect(urgent.level == 1 && late.level == 4 && recurring.level == 2,
                     "the API's priority 4 is the user's p1")
        suite.expect(urgent.due?.time == "10:00" && urgent.due?.day == "2026-11-23" && late.due?.time == nil
            && recurring.due?.isRecurring == true,
                     "a due date gives its day and, when it has one, its time")

        let today = "2026-11-23"
        suite.expect(Logic.isOverdue(late, today: today) && !Logic.isOverdue(urgent, today: today),
                     "a task due before today is overdue")
        suite.expect(Logic.sorted(tasks, today: today).map(\.content) == ["Appeler Marie", "Poster la photo", "Relancer le devis"],
                     "the most urgent first, then overdue, then by time; ticked tasks are left out")
        suite.expect(Logic.sorted(tasks, today: today, active: late.id).map(\.content) == ["Relancer le devis", "Appeler Marie", "Poster la photo"],
                     "the task being done comes first")
        suite.expect(urgent.projectID == "6Jf8VQXxpwv56VQ7" && urgent.description == nil && late.projectID == nil,
                     "a task's project is read when given")

        let filter = Logic.filterURL(cursor: "abc123")?.absoluteString ?? ""
        suite.expect(filter.hasPrefix("https://api.todoist.com/api/v1/tasks/filter?") && filter.contains("query=today%20%7C%20overdue")
            && filter.contains("limit=200") && filter.contains("cursor=abc123"),
                     "today's and overdue tasks are asked with Todoist's filter, page by page")
        suite.expect(Logic.closeURL("6X7rM8997g3RQmvh")?.absoluteString == "https://api.todoist.com/api/v1/tasks/6X7rM8997g3RQmvh/close"
            && Logic.closeURL("../projects") == nil && Logic.appURL("a/b") == nil,
                     "a task's id goes into an address only when it is plain letters and digits")

        let body = Logic.quickAddBody("  Appeler Marie demain 10h #Travail p1 ").flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String]
        }
        suite.expect(body == ["text": "Appeler Marie demain 10h #Travail p1"] && Logic.quickAddBody("   ") == nil,
                     "the quick add sends the words as typed, trimmed; an empty one sends nothing")

        suite.expect(Logic.isPlausibleToken(String(repeating: "a1", count: 20))
            && !Logic.isPlausibleToken("short") && !Logic.isPlausibleToken(String(repeating: "a", count: 30) + " x"),
                     "a token is a long run of letters and digits")

        let now = Date()
        suite.expect(Logic.refreshDue(lastFetch: nil, now: now) && !Logic.refreshDue(lastFetch: now.addingTimeInterval(-60), now: now)
            && Logic.refreshDue(lastFetch: now.addingTimeInterval(-301), now: now),
                     "the list reloads every five minutes, at once the first time")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let late23 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 30))!
        suite.expect(Logic.dayString(late23, calendar: calendar) == "2026-11-23",
                     "today is the Mac's day, in its own time zone")
    }
}
