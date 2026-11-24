// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9 in the background: when signatures are checked and called old,
/// when the scheduled scan is due, when the battery lets it run, and which
/// items of Downloads are new.
enum ForkCareAutomationTests {
    typealias Logic = ForkCareAutomationLogic

    static func run(_ suite: TestSuite) {
        signatures(suite)
        schedule(suite)
        downloads(suite)
    }

    private static func signatures(_ suite: TestSuite) {
        let now = Date()
        suite.expect(Logic.signaturesDue(lastCheck: nil, lastAttempt: nil, now: now)
            && !Logic.signaturesDue(lastCheck: now.addingTimeInterval(-2 * 3600), lastAttempt: nil, now: now)
            && Logic.signaturesDue(lastCheck: now.addingTimeInterval(-21 * 3600), lastAttempt: nil, now: now)
            && !Logic.signaturesDue(lastCheck: nil, lastAttempt: now.addingTimeInterval(-3600), now: now),
                     "signatures are checked once a day, never again within six hours of a failure")
        let file = now.addingTimeInterval(-9 * 24 * 3600), check = now.addingTimeInterval(-3600)
        suite.expect(Logic.freshness(fileDate: file, lastCheck: check) == check
            && Logic.freshness(fileDate: file, lastCheck: nil) == file
            && Logic.signaturesAreOld(freshness: nil, now: now)
            && Logic.signaturesAreOld(freshness: file, now: now)
            && !Logic.signaturesAreOld(freshness: check, now: now),
                     "a check that found nothing new keeps signatures fresh; past a week they are called old")
    }

    private static func schedule(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        // Monday 23 November 2026, the default slot at 10:00.
        let weekly = { (now: Date) in
            Logic.lastSlot(before: now, frequency: .weekly, weekday: 2, hour: 10, calendar: calendar)
        }
        suite.expect(weekly(date(23, 11)) == date(23, 10) && weekly(date(23, 9)) == date(16, 10)
            && weekly(date(23, 10)) == date(23, 10)
            && Logic.lastSlot(before: date(24, 8), frequency: .daily, weekday: 2, hour: 10, calendar: calendar) == date(23, 10)
            && Logic.lastSlot(before: date(24, 8), frequency: .off, weekday: 2, hour: 10, calendar: calendar) == nil,
                     "the last slot is this Monday's once 10:00 has come, last Monday's before; daily is yesterday's")
        suite.expect(Logic.nextSlot(after: date(23, 11), frequency: .weekly, weekday: 2, hour: 10, calendar: calendar)
            == date(30, 10),
                     "the next slot shown is next Monday's")

        let due = { (now: Date, last: Date, frequency: Logic.Frequency) in
            Logic.scanDue(now: now, lastRun: last, frequency: frequency, weekday: 2, hour: 10, calendar: calendar)
        }
        suite.expect(due(date(23, 11), date(22, 20), .weekly) && !due(date(23, 11), date(23, 10, 30), .weekly)
            && due(date(25, 9), date(22, 20), .weekly) && !due(date(23, 11), date(1, 0), .off),
                     "a scan runs once per slot, on time or on waking when the Mac slept through it")

        suite.expect(Logic.powerAllows(onBattery: false, percent: 10) && Logic.powerAllows(onBattery: true, percent: 60)
            && !Logic.powerAllows(onBattery: true, percent: 40) && !Logic.powerAllows(onBattery: true, percent: nil),
                     "background work waits for the charger or a battery above half")
    }

    private static func downloads(_ suite: TestSuite) {
        let names = ["a.dmg", ".DS_Store", "b.crdownload", "c.pdf", "old.zip", "d.zip.part", "Unconfirmed.download"]
        suite.expect(Logic.newDownloads(names, seen: ["old.zip"]) == ["a.dmg", "c.pdf"]
            && Logic.isPartial("Setup.DOWNLOAD") && !Logic.isPartial("report.pdf"),
                     "only finished new items are scanned, never hidden ones or downloads under way")
    }
}
