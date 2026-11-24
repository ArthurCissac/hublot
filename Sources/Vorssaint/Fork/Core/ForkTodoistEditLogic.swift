// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Tasks made and changed from Hublot: a form with the title, notes,
/// project, urgency, day, time and repetition; deleting with a few seconds
/// to undo; the tasks done lately, to put back. Pure: the requests' bodies
/// and addresses, how a repetition is written for Todoist, and the done
/// tasks grouped by day.
extension ForkTodoistLogic {
    // MARK: - Addresses

    static let tasksURL = base.appendingPathComponent("tasks")

    /// The task itself: POST changes it, DELETE removes it.
    static func taskURL(_ id: String) -> URL? {
        isTaskID(id) ? base.appendingPathComponent("tasks/\(id)") : nil
    }

    /// The task a quick add answers with; nil if unreadable or oversized.
    static func addedTask(from data: Data?) -> Item? {
        guard let data, data.count <= maximumSize else { return nil }
        return try? JSONDecoder().decode(Item.self, from: data)
    }

    /// Added from today's list without a date of its own: it is for today,
    /// as Todoist's own Today view has it, or it would vanish from the list.
    static func needsToday(_ task: Item) -> Bool { task.due == nil && isTaskID(task.id) }

    static func todayBody() -> Data? {
        try? JSONSerialization.data(withJSONObject: ["due_string": "today", "due_lang": "en"])
    }

    static func moveURL(_ id: String) -> URL? {
        isTaskID(id) ? base.appendingPathComponent("tasks/\(id)/move") : nil
    }

    static func reopenURL(_ id: String) -> URL? {
        isTaskID(id) ? base.appendingPathComponent("tasks/\(id)/reopen") : nil
    }

    static func projectsURL(cursor: String?) -> URL? {
        var components = URLComponents(url: base.appendingPathComponent("projects"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "limit", value: "200")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components?.queryItems = items
        return components?.url
    }

    /// How far back the done tasks go (Todoist allows up to three months).
    static let historyDays = 30

    static func completedURL(now: Date, cursor: String?) -> URL? {
        let writer = ISO8601DateFormatter()
        writer.formatOptions = [.withInternetDateTime]
        writer.timeZone = TimeZone(identifier: "UTC")
        let since = now.addingTimeInterval(-Double(historyDays) * 86_400)
        var components = URLComponents(url: base.appendingPathComponent("tasks/completed/by_completion_date"),
                                       resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "since", value: writer.string(from: since)),
                     URLQueryItem(name: "until", value: writer.string(from: now.addingTimeInterval(60))),
                     URLQueryItem(name: "limit", value: "200")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components?.queryItems = items
        return components?.url
    }

    // MARK: - Answers

    struct Project: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        var inboxProject: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case id, name
            case inboxProject = "inbox_project"
        }

        var isInbox: Bool { inboxProject == true }
    }

    struct ProjectPage: Decodable {
        let results: [Project]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case results
            case nextCursor = "next_cursor"
        }
    }

    struct CompletedPage: Decodable {
        let items: [Item]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case items
            case nextCursor = "next_cursor"
        }
    }

    static func projects(from data: Data) -> ProjectPage? {
        guard data.count <= maximumSize else { return nil }
        return try? JSONDecoder().decode(ProjectPage.self, from: data)
    }

    static func completed(from data: Data) -> CompletedPage? {
        guard data.count <= maximumSize else { return nil }
        return try? JSONDecoder().decode(CompletedPage.self, from: data)
    }

    // MARK: - The form

    /// Monday first, as in France; `calendar` numbers Sunday 1.
    enum Weekday: Int, CaseIterable, Comparable {
        case monday = 2, tuesday, wednesday, thursday, friday, saturday
        case sunday = 1

        static var week: [Weekday] { [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday] }

        /// Todoist's English short name.
        var english: String {
            switch self {
            case .monday: return "mon"
            case .tuesday: return "tue"
            case .wednesday: return "wed"
            case .thursday: return "thu"
            case .friday: return "fri"
            case .saturday: return "sat"
            case .sunday: return "sun"
            }
        }

        static func < (a: Weekday, b: Weekday) -> Bool {
            (week.firstIndex(of: a) ?? 0) < (week.firstIndex(of: b) ?? 0)
        }
    }

    enum Repeat: Equatable {
        case never, daily, weekly(Set<Weekday>), monthly, yearly

        var isRepeating: Bool { self != .never }
    }

    /// What the form holds. `level` is the user's urgency: 1 for P1, the most
    /// urgent, to 4 for none. `day` alone is a whole-day task; with `minutes`
    /// (since midnight) it has a time.
    struct Draft: Equatable {
        var content = ""
        var description = ""
        var projectID: String?
        var level = 4
        var day: Date?
        var minutes: Int?
        var repeats = Repeat.never
        /// Whether the day, time or repetition was touched: an unchanged
        /// repeating task keeps Todoist's own wording.
        var dueChanged = false

        var isValid: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.count <= 500 }
    }

    /// The form for an existing task. Its repetition is Todoist's text, kept
    /// as it is unless the date is changed.
    static func draft(for task: Item, calendar: Calendar = .current) -> Draft {
        var draft = Draft(content: task.content, description: task.description ?? "", projectID: task.projectID,
                          level: task.level)
        if let due = task.due {
            draft.day = dayDate(due.day, calendar: calendar)
            if let time = due.time {
                let parts = time.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2 { draft.minutes = parts[0] * 60 + parts[1] }
            }
        }
        return draft
    }

    static func dayDate(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Todoist's urgency: its API counts backwards, 4 for P1.
    static func apiPriority(level: Int) -> Int { 5 - min(4, max(1, level)) }

    /// The due fields for `draft`. Without a repetition, a day or a day and
    /// time; with one, Todoist's English wording. Clearing the date is only
    /// said when changing a task.
    static func dueFields(_ draft: Draft, changing: Bool, calendar: Calendar = .current, now: Date = Date()) -> [String: String] {
        let time = draft.minutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        if draft.repeats.isRepeating {
            guard let wording = recurrence(draft.repeats, day: draft.day, calendar: calendar, now: now) else { return [:] }
            return ["due_string": wording + (time.map { " at \($0)" } ?? ""), "due_lang": "en"]
        }
        guard let day = draft.day else { return changing ? ["due_string": "no date", "due_lang": "en"] : [:] }
        let date = dayString(day, calendar: calendar)
        guard let minutes = draft.minutes else { return ["due_date": date] }
        // A time in the Mac's zone, sent in UTC: Todoist shows it in the user's zone.
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let moment = calendar.date(from: parts) else { return ["due_date": date] }
        let writer = ISO8601DateFormatter()
        writer.formatOptions = [.withInternetDateTime]
        writer.timeZone = TimeZone(identifier: "UTC")
        return ["due_datetime": writer.string(from: moment)]
    }

    /// A repetition in Todoist's English: « every day », « every mon, fri »,
    /// « every 24th » for a day of the month, « every nov 24th » each year.
    /// A daily or weekly one starting later than today says so.
    static func recurrence(_ repeats: Repeat, day: Date?, calendar: Calendar = .current, now: Date = Date()) -> String? {
        let start = day ?? now
        let laterStart = day.map { calendar.startOfDay(for: $0) > calendar.startOfDay(for: now) } ?? false
        let starting = laterStart ? " starting \(dayString(start, calendar: calendar))" : ""
        switch repeats {
        case .never:
            return nil
        case .daily:
            return "every day" + starting
        case .weekly(let days):
            let chosen = days.isEmpty ? [Weekday(rawValue: calendar.component(.weekday, from: start)) ?? .monday] : days.sorted()
            return "every " + chosen.map(\.english).joined(separator: ", ") + starting
        case .monthly:
            return "every \(ordinal(calendar.component(.day, from: start)))"
        case .yearly:
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            let month = months[max(0, min(11, calendar.component(.month, from: start) - 1))]
            return "every \(month) \(ordinal(calendar.component(.day, from: start)))"
        }
    }

    static func ordinal(_ number: Int) -> String {
        let tens = number % 100
        let suffix = (11...13).contains(tens) ? "th" : number % 10 == 1 ? "st" : number % 10 == 2 ? "nd" : number % 10 == 3 ? "rd" : "th"
        return "\(number)\(suffix)"
    }

    /// The body to make a task.
    static func createBody(_ draft: Draft, calendar: Calendar = .current, now: Date = Date()) -> Data? {
        guard draft.isValid else { return nil }
        var body: [String: Any] = ["content": draft.content.trimmingCharacters(in: .whitespacesAndNewlines),
                                   "priority": apiPriority(level: draft.level)]
        let notes = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { body["description"] = notes }
        if let project = draft.projectID { body["project_id"] = project }
        for (key, value) in dueFields(draft, changing: false, calendar: calendar, now: now) { body[key] = value }
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The body to change `task` into `draft`: only what changed; nil when
    /// nothing did. The project moves apart (`moveBody`).
    static func updateBody(_ draft: Draft, from task: Item, calendar: Calendar = .current, now: Date = Date()) -> Data? {
        guard draft.isValid else { return nil }
        var body: [String: Any] = [:]
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content != task.content { body["content"] = content }
        let notes = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes != (task.description ?? "") { body["description"] = notes }
        if draft.level != task.level { body["priority"] = apiPriority(level: draft.level) }
        if draft.dueChanged {
            for (key, value) in dueFields(draft, changing: true, calendar: calendar, now: now) { body[key] = value }
        }
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func moveBody(projectID: String?, from task: Item) -> Data? {
        guard let projectID, projectID != task.projectID, isTaskID(projectID) else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["project_id": projectID])
    }

    // MARK: - Deleting

    /// How long a deleted task can be put back before Todoist is told.
    static let undoDelay: TimeInterval = 5

    // MARK: - Done tasks

    /// The done tasks by the day they were ticked, in the Mac's zone, the
    /// latest day first and the latest task first within it.
    static func doneByDay(_ tasks: [Item], calendar: Calendar = .current) -> [(day: String, tasks: [Item])] {
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime]
        let dated = tasks.compactMap { task -> (Item, Date)? in
            guard let stamp = task.completedAt, stamp.count >= 19,
                  let moment = reader.date(from: String(stamp.prefix(19)) + "Z") else { return nil }
            return (task, moment)
        }.sorted { $0.1 > $1.1 }
        var groups: [(day: String, tasks: [Item])] = []
        for (task, moment) in dated {
            let day = dayString(moment, calendar: calendar)
            if groups.last?.day == day { groups[groups.count - 1].tasks.append(task) } else { groups.append((day, [task])) }
        }
        return groups
    }
}
