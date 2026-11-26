// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Lot 8, Juicy's menu: what the battery item in the menu bar and its panel
/// show, and which devices Hublot connects to itself over Bluetooth. Pure:
/// readings and names come in, rows and labels go out.
enum ForkBatteryPanelLogic {
    // MARK: - Devices

    enum DeviceKind: String, Equatable, CaseIterable {
        case iPhone, iPad, watch, audio, keyboard, mouse, trackpad, other

        /// The SF Symbol drawn for the device.
        var symbol: String {
            switch self {
            case .iPhone: return "iphone"
            case .iPad: return "ipad"
            case .watch: return "applewatch"
            case .audio: return "airpodspro"
            case .keyboard: return "keyboard"
            case .mouse: return "magicmouse"
            case .trackpad: return "rectangle.and.hand.point.up.left"
            case .other: return "dot.radiowaves.left.and.right"
            }
        }

        /// The devices Hublot keeps a Bluetooth link with itself, as Juicy
        /// does: macOS only connects them now and then for Continuity.
        var isHeldByHublot: Bool { self == .iPhone || self == .iPad || self == .watch }

        /// Listed first: the devices this panel is mostly for.
        var order: Int {
            switch self {
            case .iPhone: return 0
            case .iPad: return 1
            case .watch: return 2
            case .audio: return 3
            case .keyboard: return 4
            case .mouse: return 5
            case .trackpad: return 6
            case .other: return 7
            }
        }
    }

    /// The kind from the model number the device gives (`iPad7,4`), else from
    /// its name, else from what macOS says about an accessory.
    static func kind(model: String?, name: String, accessory: PeripheralBatteryKind? = nil) -> DeviceKind {
        let model = (model ?? "").lowercased()
        if model.hasPrefix("iphone") { return .iPhone }
        if model.hasPrefix("ipad") { return .iPad }
        if model.hasPrefix("watch") { return .watch }
        let name = normalizedName(name)
        if name.contains("iphone") { return .iPhone }
        if name.contains("ipad") { return .iPad }
        if name.contains("watch") { return .watch }
        switch accessory {
        case .audio?: return .audio
        case .keyboard?: return .keyboard
        case .mouse?: return .mouse
        case .trackpad?: return .trackpad
        case .device?, nil: return name.contains("airpods") || name.contains("beats") ? .audio : .other
        }
    }

    /// A device's battery, as the panel lists it.
    struct Device: Equatable, Identifiable {
        let id: String
        let name: String
        let kind: DeviceKind
        /// Nil while it has never been read.
        let percent: Int?
        /// Connected and read now; otherwise its last level is shown greyed.
        let isNearby: Bool
        let lastSeen: Date?
        /// Charging, as far as can be told: iPhones and iPads do not say,
        /// so a level that has just risen counts (`isCharging(...)`).
        var isCharging = false
    }

    /// A device whose level rose at its last change, within the last
    /// quarter of an hour, is taken as charging; one that fell is not.
    static func isCharging(lastRise: Date?, lastFall: Date?, now: Date) -> Bool {
        guard let lastRise, now.timeIntervalSince(lastRise) < 15 * 60 else { return false }
        guard let lastFall else { return true }
        return lastRise > lastFall
    }

    /// Names compared loosely: case, curly apostrophes and spacing aside.
    static func normalizedName(_ name: String) -> String {
        name.replacingOccurrences(of: "\u{2019}", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The devices paired with this Mac, by name, from
    /// `system_profiler SPBluetoothDataType -json`: connected or not.
    static func pairedNames(fromSystemProfilerJSON data: Data) -> [String] {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var names: [String] = []
        for controller in controllers {
            for key in ["device_connected", "device_not_connected"] {
                for entry in controller[key] as? [[String: Any]] ?? [] {
                    names.append(contentsOf: entry.keys)
                }
            }
        }
        return names
    }

    /// Whether a device found by a Bluetooth search is one of this Mac's own
    /// iPhones or iPads: named like one, and paired here. A neighbour's
    /// phone shows no name at all (macOS only resolves the names of devices
    /// it knows), so when the paired list could not be read the name alone
    /// is enough.
    static func isOwnPhoneOrTablet(name: String?, pairedNames: [String]) -> Bool {
        guard let name, !name.isEmpty, kind(model: nil, name: name).isHeldByHublot else { return false }
        guard !pairedNames.isEmpty else { return true }
        let wanted = normalizedName(name)
        return pairedNames.contains { normalizedName($0) == wanted }
    }

    /// Paired iPhones and iPads Hublot does not know yet: worth a search.
    static func unknownPhonesOrTablets(pairedNames: [String], known: [String]) -> [String] {
        let knownNames = Set(known.map(normalizedName))
        return pairedNames.filter { kind(model: nil, name: $0).isHeldByHublot && !knownNames.contains(normalizedName($0)) }
    }

    /// The battery level characteristic (0x2A19): one byte, 0 to 100.
    static func batteryLevel(_ bytes: [UInt8]) -> Int? {
        guard bytes.count == 1, bytes[0] <= 100 else { return nil }
        return Int(bytes[0])
    }

    /// The panel's list: the devices Hublot reads itself, then the
    /// accessories macOS reports (AirPods, mice, keyboards) not already
    /// listed under the same name. Nearby first, then by kind and name.
    static func panelDevices(own: [Device], accessories: [PeripheralBatteryDevice]) -> [Device] {
        var names = Set(own.map { normalizedName($0.name) })
        var all = own
        for accessory in accessories where names.insert(normalizedName(accessory.name)).inserted {
            all.append(Device(id: accessory.id, name: accessory.name,
                              kind: kind(model: nil, name: accessory.name, accessory: accessory.kind),
                              percent: accessory.percent, isNearby: true, lastSeen: nil))
        }
        return all.sorted {
            if $0.isNearby != $1.isNearby { return $0.isNearby }
            if $0.kind.order != $1.kind.order { return $0.kind.order < $1.kind.order }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Juicy's order for the devices card: the ones in range first, the
    /// lowest battery first among them, then by name.
    static func ranked(_ devices: [Device]) -> [Device] {
        devices.sorted {
            if $0.isNearby != $1.isNearby { return $0.isNearby }
            let left = $0.percent ?? 101, right = $1.percent ?? 101
            if left != right { return left < right }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    enum RowTint: Equatable { case critical, low, normal, full }

    /// A device's row: red to 10 %, orange to 20 %, green when full, plain between.
    static func rowTint(_ percent: Int) -> RowTint {
        percent <= 10 ? .critical : percent <= 20 ? .low : percent >= 95 ? .full : .normal
    }

    /// The pinned device, by identifier or by name.
    static func pinned(in devices: [Device], pinned: String) -> Device? {
        guard !pinned.isEmpty else { return nil }
        return devices.first { $0.id == pinned } ?? devices.first { normalizedName($0.name) == normalizedName(pinned) }
    }

    /// Whole minutes since a device was last read, for « il y a 12 min ».
    static func minutesAgo(_ date: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }

    // MARK: - Levels

    enum Level: Equatable { case critical, low, normal }

    /// Red at 10 % and under, orange to 20 %, green above.
    static func level(_ percent: Int) -> Level {
        percent <= 10 ? .critical : percent <= 20 ? .low : .normal
    }

    /// The Mac's battery symbol for the menu bar.
    static func macSymbol(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// « 1 h 05 » or « 12 min » for a time left, nil when macOS does not know.
    static func duration(_ seconds: TimeInterval?) -> (hours: Int, minutes: Int)? {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 100 * 3600 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return (minutes / 60, minutes % 60)
    }

    // MARK: - Halo

    enum HaloSize: String, CaseIterable, Equatable {
        case thin, medium, large

        /// How far the glow reaches in from the edge of the screen, in points.
        var width: CGFloat {
            switch self {
            case .thin: return 24
            case .medium: return 50
            case .large: return 90
            }
        }
    }

    struct Band: Equatable {
        let inset: CGFloat
        let lineWidth: CGFloat
        let alpha: CGFloat
    }

    /// The glow as strokes from the edge inward: strongest at the edge, fading
    /// smoothly to nothing at `width`.
    static func haloBands(width: CGFloat, peak: CGFloat = 0.85, step: CGFloat = 2) -> [Band] {
        guard width > 0, step > 0 else { return [] }
        let count = max(1, Int((width / step).rounded(.up)))
        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return Band(inset: CGFloat(index) * step + step / 2, lineWidth: step, alpha: peak * pow(1 - t, 2.2))
        }
    }

    // MARK: - Sounds

    /// The charger's moments, each with its own sound. The alerts carry
    /// theirs in their rules (`ForkBatteryAlertRules.Rule.sound`).
    enum SoundEvent: String, CaseIterable, Equatable {
        case plugged, unplugged

        var defaultsKey: String {
            switch self {
            case .plugged: return DefaultsKey.forkPowerSoundPlugged
            case .unplugged: return DefaultsKey.forkPowerSoundUnplugged
            }
        }

        var defaultChoice: SoundChoice {
            self == .plugged ? .hublot(.plugged) : .hublot(.unplugged)
        }
    }

    /// What plays: nothing, one of Hublot's own sounds, a macOS alert sound
    /// by file name (`Glass`), or a sound imported by the user, by file name.
    /// Stored as `none`, `hublot.low`, `system.Glass`, `file.Gong.m4a`.
    enum SoundChoice: Equatable, Hashable {
        case none
        case hublot(ForkBatteryLogic.Sound)
        case system(String)
        case file(String)

        var stored: String {
            switch self {
            case .none: return "none"
            case .hublot(let sound): return "hublot.\(sound.rawValue)"
            case .system(let name): return "system.\(name)"
            case .file(let name): return "file.\(name)"
            }
        }
    }

    /// The stored choice, or `fallback` when it is missing or names a sound
    /// this Mac does not have (saved on another Mac, or deleted).
    static func soundChoice(stored: String?, fallback: SoundChoice, systemNames: [String], fileNames: [String] = []) -> SoundChoice {
        guard let stored else { return fallback }
        if stored == "none" { return .none }
        if stored.hasPrefix("hublot."), let sound = ForkBatteryLogic.Sound(rawValue: String(stored.dropFirst(7))) {
            return .hublot(sound)
        }
        if stored.hasPrefix("system.") {
            let name = String(stored.dropFirst(7))
            if systemNames.contains(name) { return .system(name) }
        }
        if stored.hasPrefix("file.") {
            let name = String(stored.dropFirst(5))
            if fileNames.contains(name) { return .file(name) }
        }
        return fallback
    }

    static func soundEvent(for change: ForkBatteryLogic.PowerChange) -> SoundEvent {
        change == .plugged ? .plugged : .unplugged
    }
}
