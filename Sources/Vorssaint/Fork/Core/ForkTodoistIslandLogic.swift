// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// Today's tasks kept in sight without staying there all day: the closed
/// island shows the task being done, or a task with a time shortly before it
/// comes (`forkTodoistIslandActivity`, `forkTodoistIslandLead`); a task with a
/// time is recalled in the island when it comes (`forkTodoistReminders`), and
/// the menu's tile carries the count. Pure: what shows, how wide, when to recall.
extension ForkTodoistLogic {
    // MARK: - The closed island

    static func showsIslandActivity(enabled: Bool, wanted: Bool, hasToken: Bool, hasTask: Bool) -> Bool {
        enabled && wanted && hasToken && hasTask
    }

    /// How many minutes before its time a task comes into the closed island.
    static let islandLeadChoices = [5, 15, 30, 60]
    static let defaultIslandLead = 15

    /// The stored choice, or the default for anything else.
    static func islandLead(minutes: Int) -> TimeInterval {
        TimeInterval(islandLeadChoices.contains(minutes) ? minutes : defaultIslandLead) * 60
    }

    /// How long a task whose time passed stays in the island, unticked; it
    /// stays in the list afterwards.
    static let islandGrace: TimeInterval = 30 * 60

    /// The task the closed island shows, if any: the one being done while it
    /// lasts; else a task with a time, from `lead` before it until
    /// `islandGrace` after, the next one to come first, else the latest gone.
    /// A task without a time never shows there.
    static func islandTask(_ tasks: [Item], active: String?, now: Date, lead: TimeInterval,
                           timeZone: TimeZone = .current) -> Item? {
        let open = tasks.filter { $0.checked != true }
        if let active, let doing = open.first(where: { $0.id == active }) { return doing }
        let timed = open
            .compactMap { task in task.due.flatMap { dueMoment($0, timeZone: timeZone) }.map { (task: task, at: $0) } }
            .filter { $0.at.addingTimeInterval(-lead) <= now && now <= $0.at.addingTimeInterval(islandGrace) }
        if let coming = timed.filter({ $0.at >= now }).min(by: { $0.at < $1.at }) { return coming.task }
        return timed.max(by: { $0.at < $1.at })?.task
    }

    /// Left of the camera beside the mark: the task's time, when it has one.
    static func islandMark(_ task: Item?) -> String? { task?.due?.time }

    /// A task's words as the island shows them: Todoist's light markup
    /// (links, bold, code) dropped, spaces folded.
    static func plainTitle(_ content: String) -> String {
        var text = content
        // [words](address) keeps its words.
        while let open = text.range(of: "["), let close = text.range(of: "](", range: open.upperBound..<text.endIndex),
              let end = text.range(of: ")", range: close.upperBound..<text.endIndex) {
            text.replaceSubrange(open.lowerBound..<end.upperBound, with: text[open.upperBound..<close.lowerBound])
        }
        for mark in ["**", "__", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The longest title the strip measures for; longer ones end in « … ».
    static let islandTitleLimit = 28

    static func islandReading(_ task: Item?) -> String? {
        guard let task else { return nil }
        let title = plainTitle(task.content)
        guard !title.isEmpty else { return nil }
        return title.count > islandTitleLimit ? String(title.prefix(islandTitleLimit - 1)) + "…" : title
    }

    /// The wider side, the mark with the task's time or its title, drawn as
    /// the strip draws them, with clearance from the curve and air beside the
    /// camera. The calendar's wings bound it.
    static func stripWing(title: String?, mark: String?, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactCalendarGeometry(wing: NotchGeometry.calendarWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let font = NSFont.systemFont(ofSize: textSize, weight: .medium)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }
        let left = iconSize + (mark.map { markSpacing + width($0) } ?? 0)
            + provisional.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
        let words = title.map { width($0) + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) } ?? 0
        return max(left, words) + NotchTimerSupport.stripCameraGap
    }

    /// Between the mark and the time.
    static let markSpacing: CGFloat = 4

    /// Set by the service at launch, read by upstream's island code (which
    /// the tests compile without the service). Until then, nothing shows.
    static var islandActivityShown: () -> Bool = { false }
    static var islandStripWing: (NotchGeometry) -> CGFloat = { stripWing(title: nil, mark: nil, in: $0) }
    static var islandReading: () -> String? = { nil }

    // MARK: - Reminders

    /// When a task with a time is due: Todoist gives a floating local time
    /// ("2026-11-23T14:00:00"), or a fixed one in UTC ending in « Z ».
    static func dueMoment(_ due: Due, timeZone: TimeZone = .current) -> Date? {
        guard due.time != nil else { return nil }
        let utc = due.date.hasSuffix("Z")
        let digits = due.date.prefix(19)
        guard digits.count == 19 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = utc ? TimeZone(identifier: "UTC") : timeZone
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return parser.date(from: String(digits))
    }

    /// One reminder per task and time: a task moved to a new time is recalled again.
    static func reminderKey(_ task: Item) -> String { "\(task.id)@\(task.due?.date ?? "")" }

    /// A Mac waking after a while recalls only what came in the last minutes.
    static let reminderReach: TimeInterval = 5 * 60

    /// The tasks whose time came after `last` (at most `reminderReach` ago)
    /// and by `now`, not yet recalled, earliest first.
    static func reminders(_ tasks: [Item], last: Date?, now: Date, recalled: Set<String>,
                          timeZone: TimeZone = .current) -> [Item] {
        let from = max(last ?? now.addingTimeInterval(-60), now.addingTimeInterval(-reminderReach))
        return tasks
            .filter { $0.checked != true && !recalled.contains(reminderKey($0)) }
            .compactMap { task in task.due.flatMap { dueMoment($0, timeZone: timeZone) }.map { (task, $0) } }
            .filter { $0.1 > from && $0.1 <= now }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The reminder's mark, which also tells its notice apart when clicked.
    static let reminderSymbol = "checklist.checked"

    static func isReminder(symbol: String) -> Bool { symbol == reminderSymbol }

    // MARK: - The menu's tile

    /// The count on the tile: nothing at zero, « 9+ » past nine.
    static func badge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 9 ? "9+" : String(count)
    }
}
