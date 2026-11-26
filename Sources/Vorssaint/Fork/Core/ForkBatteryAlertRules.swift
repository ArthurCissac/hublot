// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Lot 8, Juicy's alerts: rules set one by one (threshold, colour, place on
/// the screen, sound, halo, staying until clicked) for the Mac and for the
/// devices, and what each alert pill says. Pure: readings come in, the rule
/// crossed and the pill's content go out.
enum ForkBatteryAlertRules {
    enum Target: String, Codable, Equatable { case mac, device }
    enum Kind: String, Codable, Equatable { case low, charged }
    enum Tint: String, Codable, Equatable, CaseIterable { case red, orange, yellow, green, blue }
    enum Position: String, Codable, Equatable, CaseIterable { case top, center }

    struct Rule: Codable, Equatable, Identifiable {
        var id: UUID
        var target: Target
        var kind: Kind
        var percent: Int
        var tint: Tint
        var position: Position
        /// A `ForkBatteryPanelLogic.SoundChoice`, as stored.
        var sound: String
        var glow: Bool
        var sticky: Bool
        var enabled: Bool
    }

    /// At most this many rules in one list (the Mac's low alerts, say).
    static let maxRulesPerList = 5

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    /// Arthur's alerts in Juicy (docs/reference/juicy.md): 20 % orange,
    /// 15 % yellow, 5 % red, each with a halo, and 80 % reached in green
    /// without one. Devices: a low alert at 20 %, a full one at 100 % off.
    static let defaultRules: [Rule] = [
        Rule(id: id(1), target: .mac, kind: .low, percent: 20, tint: .orange, position: .top,
             sound: "hublot.low", glow: true, sticky: false, enabled: true),
        Rule(id: id(2), target: .mac, kind: .low, percent: 15, tint: .yellow, position: .top,
             sound: "hublot.low", glow: true, sticky: false, enabled: true),
        Rule(id: id(3), target: .mac, kind: .low, percent: 5, tint: .red, position: .top,
             sound: "hublot.critical", glow: true, sticky: true, enabled: true),
        Rule(id: id(4), target: .mac, kind: .charged, percent: 80, tint: .green, position: .top,
             sound: "hublot.charged", glow: false, sticky: false, enabled: true),
        Rule(id: id(5), target: .device, kind: .low, percent: 20, tint: .orange, position: .top,
             sound: "hublot.low", glow: false, sticky: false, enabled: true),
        Rule(id: id(6), target: .device, kind: .charged, percent: 100, tint: .green, position: .top,
             sound: "hublot.charged", glow: false, sticky: false, enabled: false),
    ]

    /// The rules as stored (JSON text); the defaults when nothing usable is.
    static func decode(_ stored: String) -> [Rule] {
        guard !stored.isEmpty, let rules = try? JSONDecoder().decode([Rule].self, from: Data(stored.utf8)) else {
            return defaultRules
        }
        return rules.map(clamped)
    }

    static func encode(_ rules: [Rule]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The thresholds a rule may take: a low alert from 1 to 95 %, a charge
    /// alert from 50 to 100 %.
    static func range(for kind: Kind) -> ClosedRange<Int> {
        kind == .low ? 1...95 : 50...100
    }

    static func clamped(_ rule: Rule) -> Rule {
        var rule = rule
        let range = range(for: rule.kind)
        rule.percent = min(range.upperBound, max(range.lowerBound, rule.percent))
        return rule
    }

    /// A new rule for a list: below the lowest low alert, above the highest
    /// charge alert, in the next colour.
    static func newRule(target: Target, kind: Kind, after existing: [Rule]) -> Rule {
        let same = existing.filter { $0.target == target && $0.kind == kind }
        let percent: Int
        if kind == .low {
            percent = max(1, (same.map(\.percent).min() ?? 25) - 5)
        } else {
            percent = min(100, (same.map(\.percent).max() ?? 75) + 5)
        }
        let tint: Tint = kind == .charged ? .green : percent <= 5 ? .red : percent <= 15 ? .yellow : .orange
        return Rule(id: UUID(), target: target, kind: kind, percent: percent, tint: tint, position: .top,
                    sound: kind == .low ? "hublot.low" : "hublot.charged", glow: target == .mac && kind == .low,
                    sticky: false, enabled: true)
    }

    // MARK: - Which rule a change crosses

    /// The Mac's rule a change of reading crosses: while the battery drains
    /// (on battery, or plugged into a charger too weak), the lowest low level
    /// just gone under; while it charges, the highest level just reached.
    /// Nothing at the first reading. A sleep that skips levels still alerts
    /// on waking, for the lowest one.
    static func macRule(from previous: ForkBatteryLogic.Reading?, to current: ForkBatteryLogic.Reading,
                        rules: [Rule]) -> Rule? {
        guard let previous else { return nil }
        let active = rules.filter { $0.enabled && $0.target == .mac }
        if current.charging {
            return active
                .filter { $0.kind == .charged && previous.percent < $0.percent && current.percent >= $0.percent }
                .max { $0.percent < $1.percent }
        }
        return active
            .filter { $0.kind == .low && previous.percent > $0.percent && current.percent <= $0.percent }
            .min { $0.percent < $1.percent }
    }

    /// A device's rule: falling under a low level, or rising to a full one.
    /// Devices do not say whether they charge, so the direction tells.
    static func deviceRule(from previous: Int?, to current: Int, rules: [Rule]) -> Rule? {
        guard let previous, previous != current else { return nil }
        let active = rules.filter { $0.enabled && $0.target == .device }
        if current > previous {
            return active
                .filter { $0.kind == .charged && previous < $0.percent && current >= $0.percent }
                .max { $0.percent < $1.percent }
        }
        return active
            .filter { $0.kind == .low && previous > $0.percent && current <= $0.percent }
            .min { $0.percent < $1.percent }
    }

    // MARK: - The charger

    /// The charger is announced this soon after plugging: just enough to let
    /// a flickering connection settle.
    static let chargerSettle: TimeInterval = 0.35
    /// USB-C starts at 15 W before agreeing on its power: the pill's watts
    /// are read again this long after, and updated in place.
    static let wattsSettle: TimeInterval = 2

    /// What to announce once settled: nothing when the Mac is back where the
    /// last announcement left it (a flicker), else plugged or unplugged.
    static func chargerAnnouncement(lastAnnounced: Bool?, onPower: Bool) -> ForkBatteryLogic.PowerChange? {
        guard let lastAnnounced, lastAnnounced != onPower else { return nil }
        return onPower ? .plugged : .unplugged
    }

    /// Under this, a charger (or its cable) is too slow for a MacBook.
    static let slowChargerWatts = 30

    static func isSlowCharger(_ watts: Int?) -> Bool {
        guard let watts else { return false }
        return watts < slowChargerWatts
    }

    // MARK: - The pill

    /// What a pill says, before words: the strings come from the language.
    enum Message: Equatable {
        case low(percent: Int, minutesLeft: Int?)
        case critical(percent: Int)
        case charged(percent: Int, minutesToFull: Int?)
        case plugged(percent: Int, watts: Int?, slow: Bool, minutesToFull: Int?)
        case unplugged(percent: Int, minutesLeft: Int?)
        case deviceLow(name: String, percent: Int)
        case deviceCharged(name: String, percent: Int)
        case appDrift(name: String, watts: Double)
    }

    enum Icon: Equatable {
        case battery(percent: Int)
        case bolt
        case plug
        case device(symbol: String)
    }

    struct Pill: Equatable {
        let message: Message
        let icon: Icon
        let tint: Tint
        /// How much of the outline is lit: the level.
        let outline: CGFloat
        let position: Position
        let glow: Bool
        let sticky: Bool
        let sound: String?
    }

    /// At or under this a low alert is critical: its words turn red and ask
    /// for the charger.
    static let criticalPercent = 5

    static func outline(percent: Int) -> CGFloat {
        max(0.04, min(1, CGFloat(percent) / 100))
    }

    static func pill(for rule: Rule, percent: Int, minutesLeft: Int?, minutesToFull: Int?) -> Pill {
        let message: Message
        if rule.kind == .charged {
            message = .charged(percent: percent, minutesToFull: minutesToFull)
        } else if percent <= criticalPercent {
            message = .critical(percent: percent)
        } else {
            message = .low(percent: percent, minutesLeft: minutesLeft)
        }
        return Pill(message: message, icon: rule.kind == .charged ? .bolt : .battery(percent: percent), tint: rule.tint,
                    outline: outline(percent: percent), position: rule.position, glow: rule.glow,
                    sticky: rule.sticky, sound: rule.sound)
    }

    static func devicePill(for rule: Rule, name: String, symbol: String, percent: Int) -> Pill {
        Pill(message: rule.kind == .charged ? .deviceCharged(name: name, percent: percent) : .deviceLow(name: name, percent: percent),
             icon: .device(symbol: symbol), tint: rule.tint, outline: outline(percent: percent),
             position: rule.position, glow: rule.glow, sticky: rule.sticky, sound: rule.sound)
    }

    /// The charger coming: its watts, amber when it is too slow. Before the
    /// charger has agreed on its power (`settled` false), a low figure is
    /// left out rather than called slow.
    static func pluggedPill(percent: Int, watts: Int?, minutesToFull: Int?, sound: String?, settled: Bool = true) -> Pill {
        let watts = !settled && isSlowCharger(watts) ? nil : watts
        let slow = isSlowCharger(watts)
        return Pill(message: .plugged(percent: percent, watts: watts, slow: slow, minutesToFull: minutesToFull), icon: .bolt,
                    tint: slow ? .orange : .green, outline: outline(percent: percent), position: .top,
                    glow: false, sticky: false, sound: sound)
    }

    static func unpluggedPill(percent: Int, minutesLeft: Int?, sound: String?) -> Pill {
        Pill(message: .unplugged(percent: percent, minutesLeft: minutesLeft), icon: .plug, tint: percent <= 20 ? .orange : .green,
             outline: outline(percent: percent), position: .top, glow: false, sticky: false, sound: sound)
    }

    /// An app drawing a lot on battery: its name and its watts.
    static func appDriftPill(name: String, watts: Double) -> Pill {
        Pill(message: .appDrift(name: name, watts: watts), icon: .device(symbol: "flame.fill"), tint: .orange,
             outline: max(0.04, min(1, CGFloat(watts) / 20)), position: .top, glow: false, sticky: false, sound: "hublot.ping")
    }

    // MARK: - Pill sizes and timing

    enum PillSize: String, CaseIterable, Equatable {
        case extraSmall, small, standard, large

        var scale: CGFloat {
            switch self {
            case .extraSmall: return 0.78
            case .small: return 0.89
            case .standard: return 1
            case .large: return 1.18
            }
        }
    }

    /// A pill stays this long, unless it waits for a click.
    static let pillDuration: TimeInterval = 6

    // MARK: - Imported sounds

    static let importableSoundExtensions: Set<String> = ["aiff", "aif", "wav", "mp3", "m4a", "caf"]
    static let maxImportedSoundBytes = 5 * 1024 * 1024

    /// A sound file Hublot accepts to copy among its own: a known audio
    /// type, 5 MB at most, a plain name.
    static func isImportableSound(fileName: String, bytes: Int) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return importableSoundExtensions.contains(ext) && bytes > 0 && bytes <= maxImportedSoundBytes
            && !fileName.contains("/") && !fileName.hasPrefix(".")
    }
}
