// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Todoist in the island: today's and overdue tasks from the user's own
/// account, through Todoist's API v1 with their personal token (kept in the
/// Keychain), so what is added or ticked here shows on every device. Pure:
/// the API's answers, the order, when to reload.
enum ForkTodoistLogic {
    static let base = URL(string: "https://api.todoist.com/api/v1/")!
    /// Today's and overdue tasks, in Todoist's filter language.
    static let todayFilter = "today | overdue"
    /// Where the user makes their personal token.
    static let tokenPage = URL(string: "https://app.todoist.com/app/settings/integrations/developer")!
    /// A page of tasks is a few kilobytes; anything far larger is refused.
    static let maximumSize = 2 << 20
    /// Pages read at most per refresh (200 tasks a page).
    static let maximumPages = 5

    static func filterURL(cursor: String?) -> URL? {
        var components = URLComponents(url: base.appendingPathComponent("tasks/filter"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "query", value: todayFilter), URLQueryItem(name: "limit", value: "200")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components?.queryItems = items
        return components?.url
    }

    static let quickAddURL = base.appendingPathComponent("tasks/quick")

    static func closeURL(_ id: String) -> URL? {
        guard isTaskID(id) else { return nil }
        return base.appendingPathComponent("tasks/\(id)/close")
    }

    /// Ids go into a path: letters, digits, dashes and underscores only.
    static func isTaskID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// A personal token is a long run of letters and digits.
    static func isPlausibleToken(_ token: String) -> Bool {
        (20...100).contains(token.count) && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    // MARK: - Tasks

    struct Due: Decodable, Equatable {
        /// "2026-11-23", or a full date and time ("2026-11-23T10:00:00").
        let date: String
        let string: String?
        let isRecurring: Bool?

        enum CodingKeys: String, CodingKey {
            case date, string
            case isRecurring = "is_recurring"
        }

        /// The day in the Mac's time zone: a fixed time (ending in « Z ») is
        /// moved there first, so late evening tasks stay on their own day.
        var day: String { local.map { String($0.prefix(10)) } ?? String(date.prefix(10)) }
        /// "10:00" when the task has a time, in the Mac's time zone.
        var time: String? {
            let shown = local ?? date
            guard shown.count >= 16, shown.dropFirst(10).first == "T" else { return nil }
            return String(shown.dropFirst(11).prefix(5))
        }

        /// A fixed UTC time written in the Mac's time zone, else nil.
        private var local: String? {
            guard date.hasSuffix("Z"), date.count >= 19 else { return nil }
            let reader = ISO8601DateFormatter()
            reader.formatOptions = [.withInternetDateTime]
            guard let moment = reader.date(from: String(date.prefix(19)) + "Z") else { return nil }
            let writer = DateFormatter()
            writer.locale = Locale(identifier: "en_US_POSIX")
            writer.calendar = Calendar(identifier: .gregorian)
            writer.timeZone = .current
            writer.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return writer.string(from: moment)
        }
    }

    struct Item: Decodable, Equatable, Identifiable {
        let id: String
        let content: String
        /// Todoist's API counts priority backwards: 4 is « p1 », the most urgent.
        let priority: Int
        let due: Due?
        let checked: Bool?
        var description: String? = nil
        var projectID: String? = nil
        /// When a done task was ticked, for the list of what was done.
        var completedAt: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, content, priority, due, checked, description
            case projectID = "project_id"
            case completedAt = "completed_at"
        }

        /// As the user writes it: 1 for the most urgent, 4 for none.
        var level: Int { min(4, max(1, 5 - priority)) }
    }

    struct Page: Decodable {
        let results: [Item]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case results
            case nextCursor = "next_cursor"
        }
    }

    static func page(from data: Data) -> Page? {
        guard data.count <= maximumSize else { return nil }
        return try? JSONDecoder().decode(Page.self, from: data)
    }

    static func isOverdue(_ task: Item, today: String) -> Bool {
        guard let day = task.due?.day else { return false }
        return day < today
    }

    /// The task being done first (`active`), then the most urgent; at equal
    /// urgency the overdue ones, then by time.
    static func sorted(_ tasks: [Item], today: String, active: String? = nil) -> [Item] {
        tasks.filter { $0.checked != true }.sorted { a, b in
            if let active, (a.id == active) != (b.id == active) { return a.id == active }
            if a.level != b.level { return a.level < b.level }
            let (lateA, lateB) = (isOverdue(a, today: today), isOverdue(b, today: today))
            if lateA != lateB { return lateA }
            let (timeA, timeB) = (a.due?.time ?? "99", b.due?.time ?? "99")
            if timeA != timeB { return timeA < timeB }
            return a.content.localizedCompare(b.content) == .orderedAscending
        }
    }

    /// The day in Todoist's form, in the Mac's time zone.
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The quick add's body: Todoist reads the date, project and priority from the words.
    static func quickAddBody(_ text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["text": trimmed])
    }

    /// The task in the Todoist app, or on the web when the app is missing.
    static func appURL(_ id: String) -> URL? {
        isTaskID(id) ? URL(string: "todoist://task?id=\(id)") : nil
    }

    static func webURL(_ id: String) -> URL? {
        isTaskID(id) ? URL(string: "https://app.todoist.com/app/task/\(id)") : nil
    }

    // MARK: - When to reload

    /// For the tile's count, every five minutes; at once when the panel opens.
    static let refreshInterval: TimeInterval = 5 * 60

    static func refreshDue(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= refreshInterval
    }

    // MARK: - The island

    static let islandSymbol = "checklist"
    static let pageSymbol = islandSymbol

    static func title(french: Bool) -> String { french ? "Tâches" : "Tasks" }

    static func pageAvailable(in defaults: UserDefaults) -> Bool { islandControlAvailable(in: defaults) }

    static func pageSummary(french: Bool) -> String {
        french ? "Les tâches Todoist du jour et en retard, à cocher, et un champ pour en ajouter."
            : "Today's and overdue Todoist tasks to tick, and a field to add more."
    }

    /// The control exists while the feature is on.
    static func islandControlAvailable(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkTodoistEnabled)
    }
}
