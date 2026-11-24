// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9 in the background, all of it optional: the antivirus's signatures
/// kept fresh every day, each new download scanned as it lands, and the
/// one-click scan run on a schedule. Nothing is cleaned or removed without
/// the user: a scheduled scan only finds and tells. Pure: dates, names and
/// the battery come in, what is due goes out.
enum ForkCareAutomationLogic {
    // MARK: - Signatures

    /// ClamAV publishes new signatures several times a day; one check a day is enough.
    static let signatureCheckInterval: TimeInterval = 20 * 3600
    /// After a failed check, the next attempt waits this long.
    static let signatureRetry: TimeInterval = 6 * 3600
    /// Older than this, the window and the tools bar say so.
    static let oldSignatures: TimeInterval = 7 * 24 * 3600

    static func signaturesDue(lastCheck: Date?, lastAttempt: Date?, now: Date) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < signatureRetry { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= signatureCheckInterval
    }

    /// The freshest of the signatures' file date and the last successful
    /// check: a check that finds nothing new leaves the files untouched.
    static func freshness(fileDate: Date?, lastCheck: Date?) -> Date? {
        [fileDate, lastCheck].compactMap { $0 }.max()
    }

    static func signaturesAreOld(freshness: Date?, now: Date) -> Bool {
        guard let freshness else { return true }
        return now.timeIntervalSince(freshness) > oldSignatures
    }

    // MARK: - The scheduled scan

    enum Frequency: String, CaseIterable {
        case off, weekly, daily
    }

    /// Monday (the Gregorian calendar's weekday 2) at 10:00.
    static let defaultWeekday = 2
    static let defaultHour = 10

    private static func slot(_ frequency: Frequency, weekday: Int, hour: Int) -> DateComponents? {
        switch frequency {
        case .off: return nil
        case .daily: return DateComponents(hour: hour, minute: 0, second: 0)
        case .weekly: return DateComponents(hour: hour, minute: 0, second: 0, weekday: weekday)
        }
    }

    /// The latest scheduled time at or before `now`.
    static func lastSlot(before now: Date, frequency: Frequency, weekday: Int, hour: Int,
                         calendar: Calendar = .current) -> Date? {
        guard let match = slot(frequency, weekday: weekday, hour: hour) else { return nil }
        return calendar.nextDate(after: now.addingTimeInterval(1), matching: match,
                                 matchingPolicy: .nextTime, direction: .backward)
    }

    /// The next scheduled time after `now`, shown under the scan's button.
    static func nextSlot(after now: Date, frequency: Frequency, weekday: Int, hour: Int,
                         calendar: Calendar = .current) -> Date? {
        guard let match = slot(frequency, weekday: weekday, hour: hour) else { return nil }
        return calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
    }

    /// A slot has passed since the last scheduled run: on time, or on waking
    /// when the Mac slept through it.
    static func scanDue(now: Date, lastRun: Date, frequency: Frequency, weekday: Int, hour: Int,
                        calendar: Calendar = .current) -> Bool {
        guard let slot = lastSlot(before: now, frequency: frequency, weekday: weekday, hour: hour,
                                  calendar: calendar) else { return false }
        return lastRun < slot
    }

    /// Work in the background waits for the charger, or for a battery above half.
    static func powerAllows(onBattery: Bool, percent: Int?) -> Bool {
        !onBattery || (percent ?? 0) > 50
    }

    // MARK: - New downloads

    /// What browsers write while a download is under way; the finished file
    /// gets its own name, which arrives as a new item.
    static let partialSuffixes = [".crdownload", ".download", ".part", ".partial", ".opdownload", ".tmp"]

    static func isPartial(_ name: String) -> Bool {
        let lower = name.lowercased()
        return partialSuffixes.contains { lower.hasSuffix($0) }
    }

    /// The names of Downloads not seen before, finished and not hidden.
    static func newDownloads(_ names: [String], seen: Set<String>) -> [String] {
        names.filter { !seen.contains($0) && !$0.hasPrefix(".") && !isPartial($0) }.sorted()
    }

    /// Changes are read once the folder has been quiet this long, so a burst
    /// of writes becomes one scan.
    static let settleDelay: TimeInterval = 8
}
