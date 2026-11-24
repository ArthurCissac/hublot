// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The companion follows the day (`forkMascotDay`): what it wears at a given
/// hour and date, when it sleeps, when it worries about late tasks, and
/// when a focus session turns into a break. Pure: dates come in, choices
/// go out.
enum ForkMascotDayLogic {
    // MARK: - What it wears

    /// On its head, one at a time.
    enum Headwear: String, CaseIterable {
        /// New Year's Eve and New Year's Day.
        case partyHat
        /// While background sound plays or a Pomodoro's work runs.
        case headset
        /// From the evening until morning.
        case nightcap
        /// December to February.
        case beanie
    }

    /// Beside its head: these add to whatever it wears.
    enum Extra: String, CaseIterable {
        /// In the morning.
        case coffee
        /// On summer days.
        case sunglasses
        /// The last week of October.
        case pumpkin
        /// When it rains where the user is (`forkMascotWeather`).
        case umbrella
    }

    struct Outfit: Equatable {
        var head: Headwear?
        var extras: Set<Extra> = []

        static let none = Outfit(head: nil)
    }

    static let morning = 6..<10
    static let nightcapFrom = 21
    static let sleepFrom = 23
    static let wakeAt = 6
    static let sunnyHours = 10..<19
    static let worryFrom = 19

    /// What it wears at `date`; `focused` while sound plays or work runs;
    /// `weather` where the user is, when it is followed.
    static func outfit(at date: Date, focused: Bool, weather: ForkMascotExtrasLogic.Weather? = nil,
                       calendar: Calendar = .current) -> Outfit {
        let parts = calendar.dateComponents([.month, .day, .hour], from: date)
        guard let month = parts.month, let day = parts.day, let hour = parts.hour else { return .none }
        var outfit = Outfit.none
        if isNewYear(month: month, day: day) {
            outfit.head = .partyHat
        } else if focused {
            outfit.head = .headset
        } else if hour >= nightcapFrom || hour < wakeAt {
            outfit.head = .nightcap
        } else if month == 12 || month <= 2 {
            outfit.head = .beanie
        }
        if morning.contains(hour) { outfit.extras.insert(.coffee) }
        if isSummer(month: month, day: day), sunnyHours.contains(hour) { outfit.extras.insert(.sunglasses) }
        if month == 10, day >= 25 { outfit.extras.insert(.pumpkin) }
        if let weather {
            if weather.wet { outfit.extras.insert(.umbrella) }
            if weather.sunny { outfit.extras.insert(.sunglasses) } else if weather.sky != .clear { outfit.extras.remove(.sunglasses) }
        }
        return outfit
    }

    static func isNewYear(month: Int, day: Int) -> Bool {
        (month == 12 && day == 31) || (month == 1 && day == 1)
    }

    /// 21 June to 22 September, both included.
    static func isSummer(month: Int, day: Int) -> Bool {
        let key = month * 100 + day
        return key >= 621 && key <= 922
    }

    // MARK: - Its mood through the day

    /// Late at night it sleeps.
    static func sleeps(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= sleepFrom || hour < wakeAt
    }

    /// In the evening, while late tasks remain.
    static func worries(at date: Date, overdue: Int, calendar: Calendar = .current) -> Bool {
        overdue > 0 && calendar.component(.hour, from: date) >= worryFrom && !sleeps(at: date, calendar: calendar)
    }

    /// The face the day gives it at rest, over the island's own idle one;
    /// any other face (kept awake, for one) stays as it is.
    static func restingMood(base: NotchMascotMood, at date: Date, overdue: Int,
                            calendar: Calendar = .current) -> NotchMascotMood {
        guard base == .idle else { return base }
        if sleeps(at: date, calendar: calendar) { return .sleepy }
        if worries(at: date, overdue: overdue, calendar: calendar) { return .confused }
        return base
    }

    /// Hours at which what it wears or how it feels can change; midnight
    /// for the date.
    static let changeHours = [0, wakeAt, morning.upperBound, sunnyHours.upperBound, nightcapFrom, sleepFrom]

    /// The next moment something above can change, strictly after `date`.
    static func nextChange(after date: Date, calendar: Calendar = .current) -> Date {
        let candidates = changeHours.compactMap { hour in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0),
                              matchingPolicy: .nextTime)
        }
        return candidates.min() ?? date.addingTimeInterval(3600)
    }

    // MARK: - Todoist

    enum Cheer: Equatable {
        /// A task ticked off.
        case task
        /// The last of today's list ticked off.
        case party
    }

    /// How it greets a ticked task, from the open tasks left for today.
    static func cheer(remaining: Int) -> Cheer { remaining <= 0 ? .party : .task }

    /// Open tasks whose day has gone by.
    static func overdueCount(_ tasks: [ForkTodoistLogic.Item], today: String) -> Int {
        tasks.filter { $0.checked != true && ForkTodoistLogic.isOverdue($0, today: today) }.count
    }

    // MARK: - Focus

    enum Focus: Equatable {
        case none, working, resting
    }

    /// Where focus stands, from the background sound and the island's timer.
    static func focus(soundPlaying: Bool, soundPhase: ForkAmbientLogic.Phase?,
                      timerRunning: Bool, timerPhase: NotchTimerPhase) -> Focus {
        var working = false, resting = false
        if soundPlaying {
            switch soundPhase {
            case nil, .work?: working = true
            case .shortBreak?, .longBreak?: resting = true
            }
        }
        if timerRunning {
            switch timerPhase {
            case .focus: working = true
            case .shortBreak, .longBreak: resting = true
            case .timer, .stopwatch: break
            }
        }
        if working { return .working }
        return resting ? .resting : .none
    }

    /// A break has just begun: it stretches.
    static func startsBreak(from previous: Focus, to current: Focus) -> Bool {
        previous == .working && current == .resting
    }
}
