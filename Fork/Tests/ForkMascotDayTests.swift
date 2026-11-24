// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The companion through the day: what it wears by hour and season, which
/// headwear wins, when it sleeps or worries, when it next changes, how it
/// cheers a ticked task and when a break begins.
enum ForkMascotDayTests {
    typealias Logic = ForkMascotDayLogic

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }()

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private static func wear(_ date: Date, focused: Bool = false) -> Logic.Outfit {
        Logic.outfit(at: date, focused: focused, calendar: calendar)
    }

    static func run(_ suite: TestSuite) {
        hours(suite)
        seasons(suite)
        headwear(suite)
        moods(suite)
        changes(suite)
        todoist(suite)
        focus(suite)
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkMascotDay] as? Bool == true,
                     "following the day is on by default")
    }

    private static func hours(_ suite: TestSuite) {
        suite.expect(wear(at(2026, 11, 23, 15)) == .none,
                     "an ordinary November afternoon: nothing to wear")
        suite.expect(wear(at(2026, 11, 23, 6)).extras == [.coffee] && wear(at(2026, 11, 23, 9, 59)).extras == [.coffee]
            && wear(at(2026, 11, 23, 5, 59)).extras.isEmpty && wear(at(2026, 11, 23, 10)).extras.isEmpty,
                     "coffee from six to ten in the morning")
        suite.expect(wear(at(2026, 11, 23, 21)).head == .nightcap && wear(at(2026, 11, 23, 20, 59)).head == nil
            && wear(at(2026, 11, 24, 3)).head == .nightcap && wear(at(2026, 11, 24, 5, 59)).head == .nightcap
            && wear(at(2026, 11, 24, 6)).head == nil,
                     "the nightcap from nine in the evening, kept on while it sleeps, until six")
    }

    private static func seasons(_ suite: TestSuite) {
        suite.expect(wear(at(2026, 12, 1, 15)).head == .beanie && wear(at(2026, 11, 30, 15)).head == nil
            && wear(at(2027, 2, 28, 15)).head == .beanie && wear(at(2028, 2, 29, 15)).head == .beanie
            && wear(at(2027, 3, 1, 15)).head == nil,
                     "the beanie from the first of December to the end of February")
        suite.expect(wear(at(2026, 12, 31, 15)).head == .partyHat && wear(at(2027, 1, 1, 15)).head == .partyHat
            && wear(at(2027, 1, 2, 15)).head == .beanie && wear(at(2026, 12, 30, 15)).head == .beanie,
                     "the party hat on New Year's Eve and New Year's Day only")
        suite.expect(wear(at(2026, 6, 21, 10)).extras == [.sunglasses] && wear(at(2026, 9, 22, 18, 59)).extras == [.sunglasses]
            && wear(at(2026, 6, 20, 12)).extras.isEmpty && wear(at(2026, 9, 23, 12)).extras.isEmpty
            && wear(at(2026, 7, 14, 9, 59)).extras == [.coffee] && wear(at(2026, 7, 14, 19)).extras.isEmpty,
                     "sunglasses on summer days, 21 June to 22 September, from ten to seven")
        suite.expect(wear(at(2026, 10, 25, 12)).extras == [.pumpkin] && wear(at(2026, 10, 31, 23)).extras == [.pumpkin]
            && wear(at(2026, 10, 24, 12)).extras.isEmpty && wear(at(2026, 11, 1, 12)).extras.isEmpty,
                     "the pumpkin the last week of October")
    }

    private static func headwear(_ suite: TestSuite) {
        suite.expect(wear(at(2026, 12, 31, 15), focused: true).head == .partyHat
            && wear(at(2026, 12, 10, 15), focused: true).head == .headset
            && wear(at(2026, 12, 10, 22), focused: true).head == .headset
            && wear(at(2026, 12, 10, 22)).head == .nightcap,
                     "on its head: party hat, then headset, then nightcap, then beanie")
        let morning = wear(at(2026, 12, 10, 8))
        let evening = wear(at(2026, 10, 31, 22), focused: true)
        suite.expect(morning.head == .beanie && morning.extras == [.coffee]
            && evening.head == .headset && evening.extras == [.pumpkin],
                     "coffee and the pumpkin go with whatever is on its head")
    }

    private static func moods(_ suite: TestSuite) {
        suite.expect(Logic.sleeps(at: at(2026, 11, 23, 23), calendar: calendar) && !Logic.sleeps(at: at(2026, 11, 23, 22, 59), calendar: calendar)
            && Logic.sleeps(at: at(2026, 11, 24, 5, 59), calendar: calendar) && !Logic.sleeps(at: at(2026, 11, 24, 6), calendar: calendar),
                     "it sleeps from eleven at night to six")
        suite.expect(Logic.worries(at: at(2026, 11, 23, 19), overdue: 1, calendar: calendar)
            && !Logic.worries(at: at(2026, 11, 23, 18, 59), overdue: 1, calendar: calendar)
            && !Logic.worries(at: at(2026, 11, 23, 20), overdue: 0, calendar: calendar)
            && !Logic.worries(at: at(2026, 11, 23, 23, 30), overdue: 3, calendar: calendar),
                     "it worries from seven in the evening while late tasks remain, until it sleeps")
        let night = at(2026, 11, 23, 23, 30), evening = at(2026, 11, 23, 20), day = at(2026, 11, 23, 15)
        suite.expect(Logic.restingMood(base: .idle, at: night, overdue: 0, calendar: calendar) == .sleepy
            && Logic.restingMood(base: .idle, at: evening, overdue: 2, calendar: calendar) == .confused
            && Logic.restingMood(base: .idle, at: evening, overdue: 0, calendar: calendar) == .idle
            && Logic.restingMood(base: .idle, at: day, overdue: 2, calendar: calendar) == .idle
            && Logic.restingMood(base: .alert, at: night, overdue: 2, calendar: calendar) == .alert,
                     "at rest the day makes it sleepy or worried; kept awake, it stays alert")
    }

    private static func changes(_ suite: TestSuite) {
        func next(_ date: Date) -> Date { Logic.nextChange(after: date, calendar: calendar) }
        suite.expect(next(at(2026, 11, 23, 15)) == at(2026, 11, 23, 19) && next(at(2026, 11, 23, 9, 30)) == at(2026, 11, 23, 10)
            && next(at(2026, 11, 23, 19)) == at(2026, 11, 23, 21) && next(at(2026, 11, 23, 23, 30)) == at(2026, 11, 24, 0)
            && next(at(2026, 11, 24, 0)) == at(2026, 11, 24, 6),
                     "it next changes at the following hour that matters, midnight included")
        suite.expect(next(at(2027, 3, 28, 1, 30)) == at(2027, 3, 28, 6),
                     "the spring clock change does not upset the next change")
    }

    private static func todoist(_ suite: TestSuite) {
        suite.expect(Logic.cheer(remaining: 0) == .party && Logic.cheer(remaining: 3) == .task,
                     "a ticked task is cheered; the last of the day is a party")
        let sample = """
        {"results": [
          {"id": "1", "content": "En retard", "priority": 1, "checked": false, "due": {"date": "2026-11-21"}},
          {"id": "2", "content": "Aujourd'hui", "priority": 1, "checked": false, "due": {"date": "2026-11-23"}},
          {"id": "3", "content": "Faite", "priority": 1, "checked": true, "due": {"date": "2026-11-20"}},
          {"id": "4", "content": "Sans date", "priority": 1, "checked": false}
        ]}
        """
        let tasks = ForkTodoistLogic.page(from: Data(sample.utf8))?.results ?? []
        suite.expect(tasks.count == 4 && Logic.overdueCount(tasks, today: "2026-11-23") == 1,
                     "only open tasks whose day has gone by are late")
    }

    private static func focus(_ suite: TestSuite) {
        func focus(_ playing: Bool, _ phase: ForkAmbientLogic.Phase?, _ running: Bool, _ timer: NotchTimerPhase) -> Logic.Focus {
            Logic.focus(soundPlaying: playing, soundPhase: phase, timerRunning: running, timerPhase: timer)
        }
        suite.expect(focus(true, nil, false, .timer) == .working && focus(true, .work, false, .timer) == .working
            && focus(false, nil, true, .focus) == .working && focus(true, .shortBreak, true, .focus) == .working,
                     "background sound or a Pomodoro's work means focus")
        suite.expect(focus(true, .longBreak, false, .timer) == .resting && focus(false, nil, true, .shortBreak) == .resting
            && focus(false, nil, true, .timer) == .none && focus(false, nil, false, .focus) == .none
            && focus(false, .work, true, .stopwatch) == .none,
                     "a Pomodoro's break is rest; a plain timer, a stopwatch or nothing running is neither")
        suite.expect(Logic.startsBreak(from: .working, to: .resting) && !Logic.startsBreak(from: .none, to: .resting)
            && !Logic.startsBreak(from: .resting, to: .working) && !Logic.startsBreak(from: .working, to: .none),
                     "it stretches only when work turns into a break")
    }
}
