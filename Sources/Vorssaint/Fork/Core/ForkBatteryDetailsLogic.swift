// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 8, the battery panel's details: the Mac's battery as its registry
/// entry describes it, and the last 24 hours of its level for the chart.
/// Pure: properties and readings come in, values and spans go out.
enum ForkBatteryDetailsLogic {
    // MARK: - The battery in detail

    struct Details: Equatable {
        /// Volts.
        var voltage: Double?
        /// Amperes, negative while the battery is drained.
        var amperage: Double?
        var cycles: Int?
        /// The cycles the battery is designed for (1000 on recent Macs).
        var designCycles: Int?
        var adapterWatts: Int?
        var adapterName: String?
        /// mAh: what is left, what a full charge holds now, what it held new.
        var remainingCapacity: Int?
        var fullCapacity: Int?
        var designCapacity: Int?
        /// Watts from the battery's power telemetry: what comes in from the
        /// charger, what the Mac uses, what flows into (+) or out of (−) the battery.
        var systemPowerIn: Double?
        var systemLoad: Double?
        var batteryPower: Double?

        /// A full charge now against when new, in percent.
        var healthPercent: Double? {
            guard let fullCapacity, let designCapacity, designCapacity > 0 else { return nil }
            return min(100, Double(fullCapacity) / Double(designCapacity) * 100)
        }

        /// Watts into the battery (charging, +) or out of it (−).
        var watts: Double? {
            guard let voltage, let amperage else { return nil }
            return voltage * amperage
        }

        /// The share of the designed cycles used, 0 to 1.
        var cycleShare: Double? {
            guard let cycles, let designCycles, designCycles > 0 else { return nil }
            return min(1, Double(cycles) / Double(designCycles))
        }
    }

    /// From the properties of the `AppleSmartBattery` registry entry.
    static func details(from properties: [String: Any]) -> Details {
        var details = Details()
        if let millivolts = integer(properties["Voltage"]), millivolts > 0, millivolts < 100_000 {
            details.voltage = Double(millivolts) / 1000
        }
        if let milliamps = integer(properties["InstantAmperage"]) ?? integer(properties["Amperage"]), abs(milliamps) < 20_000 {
            details.amperage = Double(milliamps) / 1000
        }
        if let cycles = integer(properties["CycleCount"]), cycles >= 0, cycles < 100_000 { details.cycles = Int(cycles) }
        if let design = integer(properties["DesignCycleCount9C"]), design > 0, design < 100_000 { details.designCycles = Int(design) }
        func capacity(_ key: String) -> Int? {
            guard let value = integer(properties[key]), value > 0, value < 100_000 else { return nil }
            return Int(value)
        }
        details.remainingCapacity = capacity("AppleRawCurrentCapacity")
        details.fullCapacity = capacity("AppleRawMaxCapacity") ?? capacity("FullChargeCapacity")
        details.designCapacity = capacity("DesignCapacity")
        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
            func watts(_ key: String, signed: Bool) -> Double? {
                guard let milliwatts = integer(telemetry[key]), abs(milliwatts) < 1_000_000 else { return nil }
                guard signed || milliwatts >= 0 else { return nil }
                return Double(milliwatts) / 1000
            }
            details.systemPowerIn = watts("SystemPowerIn", signed: false)
            details.systemLoad = watts("SystemLoad", signed: false)
            details.batteryPower = watts("BatteryPower", signed: true)
        }
        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            if let watts = integer(adapter["Watts"]), watts > 0, watts < 1000 { details.adapterWatts = Int(watts) }
            let name = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            details.adapterName = name?.isEmpty == false ? name : nil
        }
        return details
    }

    /// A registry number. A negative one can arrive as its unsigned bit
    /// pattern (the amperage while discharging, 18446744073709549972 for −1644).
    static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        return Int64(bitPattern: number.uint64Value)
    }

    // MARK: - Health and temperature

    enum Health: Equatable { case good, fair, poor }

    /// Good from 80 %, fair from 60 % (worth a check by Apple), poor under.
    static func health(_ percent: Double) -> Health {
        percent >= 80 ? .good : percent >= 60 ? .fair : .poor
    }

    enum Warmth: Equatable { case cold, normal, warm, hot }

    /// A battery's temperature, as Apple advises: under 10 °C cold, up to
    /// 40 °C normal, to 45 °C warm, hot above.
    static func warmth(_ celsius: Double) -> Warmth {
        celsius < 10 ? .cold : celsius <= 40 ? .normal : celsius <= 45 ? .warm : .hot
    }

    static func fahrenheit(_ celsius: Double) -> Double { celsius * 9 / 5 + 32 }

    /// The battery's temperature from its sensors (`TB0T`, `TB1T`…): the
    /// highest plausible one.
    static func batteryTemperature(_ readings: [Double]) -> Double? {
        readings.filter { $0 > 1 && $0 < 100 }.max()
    }

    // MARK: - Time left

    /// The time the panel shows: macOS's own when it has one, else an
    /// estimate from the battery's charge and what flows. While charging,
    /// until full; otherwise until empty, plugged in but paused included
    /// (how long it would last unplugged). Nil when nothing tells.
    static func estimatedMinutes(charging: Bool, onPower: Bool, minutesToEmpty: Int?, minutesToFull: Int?,
                                 details: Details) -> Int? {
        if charging {
            if let minutesToFull { return minutesToFull }
            guard let full = details.fullCapacity, let remaining = details.remainingCapacity, full > remaining,
                  let amps = details.amperage, amps > 0.05 else { return nil }
            return bounded(Double(full - remaining) / 1000 / amps * 60)
        }
        if !onPower, let minutesToEmpty { return minutesToEmpty }
        guard let remaining = details.remainingCapacity, let voltage = details.voltage,
              let load = details.systemLoad ?? details.batteryPower.map(abs) ?? details.watts.map(abs), load > 0.5 else { return nil }
        return bounded(Double(remaining) / 1000 * voltage / load * 60)
    }

    private static func bounded(_ minutes: Double) -> Int? {
        guard minutes.isFinite, minutes >= 1, minutes < 100 * 60 else { return nil }
        return Int(minutes.rounded())
    }

    // MARK: - Power flow

    /// Watts between the charger, the battery and the Mac, for the animated
    /// diagram: each path nil or zero when nothing flows on it.
    struct Flow: Equatable {
        var chargerToMac: Double = 0
        var chargerToBattery: Double = 0
        var batteryToMac: Double = 0
        var macLoad: Double?
    }

    static func flow(_ details: Details, onPower: Bool) -> Flow {
        var flow = Flow()
        let battery = details.batteryPower ?? details.watts ?? 0
        let load = details.systemLoad ?? (onPower ? nil : max(0, -battery))
        flow.macLoad = load
        if battery > 0.2 { flow.chargerToBattery = battery }
        if battery < -0.2 { flow.batteryToMac = -battery }
        if onPower {
            let input = details.systemPowerIn ?? ((load ?? 0) + max(0, battery))
            flow.chargerToMac = max(0, min(input - max(0, battery), load ?? input))
        }
        return flow
    }

    // MARK: - Figures

    /// « 5 585 »: thousands grouped as the language does.
    static func grouped(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// « 11,40 V »: the language's decimal mark, the unit after a space.
    static func number(_ value: Double, digits: Int = 1, unit: String, locale: Locale, space: String) -> String {
        String(format: "%.\(digits)f", locale: locale, value) + space + unit
    }

    /// « −18,7 W », « +45,0 W »: a true minus sign, a plus when it flows in,
    /// no sign for what rounds to zero.
    static func signed(_ value: Double, digits: Int = 1, unit: String, locale: Locale, space: String) -> String {
        let threshold = 0.5 * pow(10, -Double(digits))
        let sign = value >= threshold ? "+" : value <= -threshold ? "\u{2212}" : ""
        return sign + number(abs(value), digits: digits, unit: unit, locale: locale, space: space)
    }

    // MARK: - The last 24 hours

    struct Sample: Codable, Equatable {
        let time: Date
        let percent: Int
        let charging: Bool
        /// On power: with `charging` false and the level falling, a charger
        /// too weak (amber on the chart).
        let onPower: Bool

        init(time: Date, percent: Int, charging: Bool, onPower: Bool? = nil) {
            self.time = time
            self.percent = percent
            self.charging = charging
            self.onPower = onPower ?? charging
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode(Date.self, forKey: .time)
            percent = try container.decode(Int.self, forKey: .percent)
            charging = try container.decode(Bool.self, forKey: .charging)
            onPower = try container.decodeIfPresent(Bool.self, forKey: .onPower) ?? charging
        }
    }

    static let historyWindow: TimeInterval = 24 * 3600
    /// A level that has not moved is still recorded this often, so the
    /// chart's line reaches the present.
    static let sampleSpacing: TimeInterval = 5 * 60

    /// The history with a new reading: kept when the level or the charging
    /// changes, or `sampleSpacing` after the last one; nothing older than
    /// 24 hours, nothing from the future (a clock set back).
    static func recording(_ sample: Sample, in history: [Sample]) -> [Sample] {
        var kept = history.filter { $0.time <= sample.time && sample.time.timeIntervalSince($0.time) < historyWindow }
        if let last = kept.last, last.percent == sample.percent, last.charging == sample.charging, last.onPower == sample.onPower,
           sample.time.timeIntervalSince(last.time) < sampleSpacing {
            return kept
        }
        kept.append(sample)
        return kept
    }

    /// The stretches spent charging, for the chart's bands; one still
    /// running ends now.
    static func chargingSpans(_ history: [Sample], now: Date) -> [ClosedRange<Date>] {
        var spans: [ClosedRange<Date>] = []
        var start: Date?
        for sample in history {
            if sample.charging {
                if start == nil { start = sample.time }
            } else if let begun = start {
                if sample.time > begun { spans.append(begun...sample.time) }
                start = nil
            }
        }
        if let begun = start, now > begun { spans.append(begun...now) }
        return spans
    }

    /// The stretches spent plugged in while the level still fell (amber).
    static func drainingOnPowerSpans(_ history: [Sample]) -> [ClosedRange<Date>] {
        var spans: [ClosedRange<Date>] = []
        for (previous, next) in zip(history, history.dropFirst())
        where previous.onPower && next.onPower && !next.charging && next.percent < previous.percent && next.time > previous.time {
            if let last = spans.last, last.upperBound == previous.time {
                spans[spans.count - 1] = last.lowerBound...next.time
            } else {
                spans.append(previous.time...next.time)
            }
        }
        return spans
    }

    /// The samples within the last `hours`, and the one just before so the
    /// line starts at the left edge.
    static func visible(_ history: [Sample], hours: Int, now: Date) -> [Sample] {
        let start = now.addingTimeInterval(-Double(hours) * 3600)
        guard let first = history.firstIndex(where: { $0.time >= start }) else { return history.suffix(1) }
        return Array(history[max(0, first - 1)...])
    }
}
