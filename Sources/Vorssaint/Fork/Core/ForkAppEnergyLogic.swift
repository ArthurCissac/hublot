// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 8, Juicy's energy per app: macOS counts the energy each process
/// uses (`ri_energy_nj`); every process inside an app's bundle (its helpers,
/// a browser's renderers) counts for that app. The panel shows what each app
/// draws now, and what it used over 24 hours, 7 and 30 days with a
/// sparkline; an app drawing a lot for minutes on battery is pointed out.
/// Pure: readings come in, rows and alerts go out.
enum ForkAppEnergyLogic {
    // MARK: - From processes to apps

    /// The app a process belongs to: its executable's outermost `.app`
    /// bundle, so helpers count for their app. Nil outside any app.
    static func appBundle(executable path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return path.hasSuffix(".app") ? path : nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// One process, as read.
    struct Process: Equatable {
        let pid: Int32
        let bundle: String
        /// Nanojoules since the process started.
        let energy: UInt64
    }

    /// The energy each app used since the last reading, in joules. A process
    /// seen before adds what it used since; one started since adds all of
    /// its own. The very first reading only sets the baseline.
    static func joules(previous: [Int32: UInt64]?, current: [Process]) -> [String: Double] {
        guard let previous else { return [:] }
        var totals: [String: Double] = [:]
        for process in current {
            let before = previous[process.pid] ?? 0
            let used = process.energy >= before ? process.energy - before : process.energy
            guard used > 0 else { continue }
            totals[process.bundle, default: 0] += Double(used) / 1e9
        }
        return totals
    }

    // MARK: - History

    /// Watt-hours per app in hourly buckets (the last 24 hours) and daily
    /// ones (the last 30 days), by the bucket's start.
    struct Store: Codable, Equatable {
        var hours: [Date: [String: Double]] = [:]
        var days: [Date: [String: Double]] = [:]
    }

    static let keptApps = 30

    static func hourStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    static func dayStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The store with a reading's joules added to its hour and its day; old
    /// buckets dropped, each bucket keeping its 30 biggest apps.
    static func adding(_ joules: [String: Double], at date: Date, to store: Store, calendar: Calendar = .current) -> Store {
        var next = store
        let hour = hourStart(date, calendar: calendar), day = dayStart(date, calendar: calendar)
        for (bundle, value) in joules where value > 0 {
            next.hours[hour, default: [:]][bundle, default: 0] += value / 3600
            next.days[day, default: [:]][bundle, default: 0] += value / 3600
        }
        next.hours = next.hours.filter { date.timeIntervalSince($0.key) < 24 * 3600 }.mapValues(trimmed)
        next.days = next.days.filter { date.timeIntervalSince($0.key) < 30 * 24 * 3600 }.mapValues(trimmed)
        return next
    }

    private static func trimmed(_ bucket: [String: Double]) -> [String: Double] {
        guard bucket.count > keptApps else { return bucket }
        return Dictionary(uniqueKeysWithValues: bucket.sorted { $0.value > $1.value }.prefix(keptApps).map { ($0.key, $0.value) })
    }

    // MARK: - Rows

    enum Period: String, CaseIterable, Equatable { case live, day, week, month }

    struct Row: Equatable, Identifiable {
        var id: String { bundle }
        let bundle: String
        /// Watts for the live view, watt-hours otherwise.
        let value: Double
        /// Share of the total, 0 to 1.
        let share: Double
        /// Oldest first: the hours of the day, or the days of the week or month.
        let spark: [Double]
    }

    static let rowCount = 6

    /// The biggest apps for a period, with their share and their sparkline.
    static func rows(period: Period, live: [String: Double], store: Store, now: Date,
                     calendar: Calendar = .current) -> [Row] {
        let buckets: [[String: Double]]
        switch period {
        case .live:
            let total = live.values.reduce(0, +)
            return live.filter { $0.value > 0.005 }.sorted { $0.value > $1.value }.prefix(rowCount).map {
                Row(bundle: $0.key, value: $0.value, share: total > 0 ? $0.value / total : 0, spark: [])
            }
        case .day:
            let start = hourStart(now, calendar: calendar)
            buckets = (0..<24).reversed().map { offset in
                store.hours[calendar.date(byAdding: .hour, value: -offset, to: start) ?? start] ?? [:]
            }
        case .week, .month:
            let start = dayStart(now, calendar: calendar)
            let count = period == .week ? 7 : 30
            buckets = (0..<count).reversed().map { offset in
                store.days[calendar.date(byAdding: .day, value: -offset, to: start) ?? start] ?? [:]
            }
        }
        var totals: [String: Double] = [:]
        for bucket in buckets { for (bundle, value) in bucket { totals[bundle, default: 0] += value } }
        let total = totals.values.reduce(0, +)
        return totals.filter { $0.value > 0.0005 }.sorted { $0.value > $1.value }.prefix(rowCount).map { entry in
            Row(bundle: entry.key, value: entry.value, share: total > 0 ? entry.value / total : 0,
                spark: buckets.map { $0[entry.key] ?? 0 })
        }
    }

    /// The app's name as Finder shows it: the bundle's file name without `.app`.
    static func name(bundle: String) -> String {
        let file = (bundle as NSString).lastPathComponent
        return file.hasSuffix(".app") ? String(file.dropLast(4)) : file
    }

    /// A sparkline's points, 0 to 1, scaled to its highest value.
    static func sparkPoints(_ values: [Double]) -> [Double] {
        let top = values.max() ?? 0
        guard top > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / top }
    }

    // MARK: - An app drawing a lot

    /// The last readings an app has to stay above the threshold for.
    static let driftReadings = 3
    /// Once pointed out, an app is left alone this long.
    static let driftQuiet: TimeInterval = 3600

    /// The apps that drew at least `threshold` watts in each of their last
    /// readings, on battery, not pointed out within the hour.
    static func drifting(recent: [String: [Double]], threshold: Double, onBattery: Bool,
                         lastAlert: [String: Date], now: Date) -> [String] {
        guard onBattery, threshold > 0 else { return [] }
        return recent.compactMap { bundle, watts in
            guard watts.count >= driftReadings, watts.suffix(driftReadings).allSatisfy({ $0 >= threshold }) else { return nil }
            if let last = lastAlert[bundle], now.timeIntervalSince(last) < driftQuiet { return nil }
            return bundle
        }.sorted()
    }

    /// The last readings kept per app, newest last.
    static func remembering(_ watts: [String: Double], in recent: [String: [Double]]) -> [String: [Double]] {
        var next: [String: [Double]] = [:]
        for bundle in Set(watts.keys).union(recent.keys) {
            let history = (recent[bundle] ?? []) + [watts[bundle] ?? 0]
            if history.contains(where: { $0 > 0 }) { next[bundle] = Array(history.suffix(driftReadings)) }
        }
        return next
    }
}
