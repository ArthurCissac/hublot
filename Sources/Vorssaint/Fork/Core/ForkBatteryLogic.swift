// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 8, the battery as Juicy does it: the Mac's readings, the charger
/// coming and going, the pinned device, and Hublot's own sounds. The alerts
/// themselves are rules, in `ForkBatteryAlertRules`. Pure: readings come in,
/// what to show and play goes out. The sounds are made here, note by note,
/// not taken from anywhere.
enum ForkBatteryLogic {
    /// The Mac's battery, as read.
    struct Reading: Equatable {
        let percent: Int
        let onPower: Bool
        /// Filling now. On power is not enough: a weak charger, or a charge
        /// paused at a limit, leaves it on power without charging.
        let charging: Bool

        init(percent: Int, onPower: Bool, charging: Bool? = nil) {
            self.percent = percent
            self.onPower = onPower
            self.charging = charging ?? onPower
        }
    }

    enum PowerChange: Equatable, CaseIterable { case plugged, unplugged }

    static func powerChange(from previous: Reading?, to current: Reading) -> PowerChange? {
        guard let previous, previous.onPower != current.onPower else { return nil }
        return current.onPower ? .plugged : .unplugged
    }

    // MARK: - Pinned device

    /// What the menu bar shows for a pinned device that is not around.
    static let awayValue = "—"

    /// The pinned device's battery for the menu bar, in place of the lowest
    /// one: found by its identifier, or by its name; nil when none is pinned.
    /// Out of range, or with Bluetooth off, it keeps its place with a dash
    /// instead of the level, so the menu bar does not jump to another device.
    static func pinnedMetric(devices: [PeripheralBatteryDevice], pinned: String) -> (label: String, value: String)? {
        guard !pinned.isEmpty else { return nil }
        guard let device = devices.first(where: { $0.id == pinned }) ?? devices.first(where: { $0.name == pinned }) else {
            return (label(name: pinned, kind: .device), awayValue)
        }
        return (label(for: device), "\(device.percent)%")
    }

    /// A short label: the kind of Apple device when its name tells it.
    static func label(for device: PeripheralBatteryDevice) -> String {
        label(name: device.name, kind: device.kind)
    }

    static func label(name: String, kind: PeripheralBatteryKind) -> String {
        let name = name.lowercased()
        if name.contains("ipad") { return "IPD" }
        if name.contains("iphone") { return "IPH" }
        if name.contains("watch") { return "WCH" }
        return kind.menuLabel
    }

    /// How often the batteries of connected devices are read over Bluetooth:
    /// upstream's five minutes, two while a device is pinned so the menu bar
    /// keeps up with an iPhone or an iPad. Each read is a connection of about
    /// a second per device.
    static func bluetoothRefreshInterval(pinned: String) -> TimeInterval {
        pinned.isEmpty ? 300 : 120
    }

    static var bluetoothRefreshInterval: TimeInterval {
        bluetoothRefreshInterval(pinned: UserDefaults.standard.string(forKey: DefaultsKey.forkPinnedBatteryDevice) ?? "")
    }

    // MARK: - Bluetooth access

    /// Whether macOS lets the app use Bluetooth, as `CBManager.authorization` says.
    enum BluetoothAccess: Equatable { case notAsked, refused, allowed }

    /// The Bluetooth radio, as a central manager sees it once allowed.
    enum BluetoothRadio: Equatable { case on, off, unknown }

    /// What the settings say about reading an iPhone or an iPad.
    enum BluetoothStatus: Equatable {
        /// macOS has not asked yet: a button asks.
        case askNeeded
        /// Refused in System Settings: a button opens them.
        case refused
        /// Allowed, but Bluetooth is off.
        case off
        /// Allowed and on, or not known yet: nothing to say.
        case ready
    }

    static func bluetoothStatus(access: BluetoothAccess, radio: BluetoothRadio) -> BluetoothStatus {
        switch access {
        case .notAsked: return .askNeeded
        case .refused: return .refused
        case .allowed: return radio == .off ? .off : .ready
        }
    }

    // MARK: - Sounds

    /// Hublot's own sounds, composed here. The first five are the defaults of
    /// the alerts and the charger; all of them can be chosen for any moment.
    enum Sound: String, Equatable, Hashable, CaseIterable {
        case low, critical, charged, plugged, unplugged, chime, ping
    }

    struct Tone: Equatable {
        let frequency: Double
        let duration: Double
    }

    /// Each sound as a few short notes: falling when something runs out or
    /// goes, rising when it fills or comes.
    static func tones(for sound: Sound) -> [Tone] {
        switch sound {
        case .plugged: return [Tone(frequency: 660, duration: 0.07), Tone(frequency: 990, duration: 0.09)]
        case .unplugged: return [Tone(frequency: 990, duration: 0.07), Tone(frequency: 660, duration: 0.09)]
        case .low: return [Tone(frequency: 784, duration: 0.13), Tone(frequency: 587, duration: 0.18)]
        case .critical:
            return [Tone(frequency: 880, duration: 0.12), Tone(frequency: 659, duration: 0.12), Tone(frequency: 523, duration: 0.22)]
        case .charged:
            return [Tone(frequency: 523, duration: 0.1), Tone(frequency: 659, duration: 0.1), Tone(frequency: 784, duration: 0.18)]
        case .chime:
            return [Tone(frequency: 1319, duration: 0.09), Tone(frequency: 988, duration: 0.09), Tone(frequency: 1319, duration: 0.2)]
        case .ping:
            return [Tone(frequency: 1760, duration: 0.16)]
        }
    }

    /// The notes as samples from -1 to 1: a soft sine with a quick start and
    /// a fading end, a short silence between notes, at most `peak` loud.
    static func samples(for tones: [Tone], sampleRate: Double, peak: Float = 0.35) -> [Float] {
        guard sampleRate > 0 else { return [] }
        var samples: [Float] = []
        let gap = Int(0.02 * sampleRate)
        for (index, tone) in tones.enumerated() {
            let count = max(0, Int(tone.duration * sampleRate))
            let attack = max(1, Int(0.008 * sampleRate))
            for n in 0..<count {
                let rise = min(1, Double(n) / Double(attack))
                let fade = exp(-4 * Double(n) / Double(max(1, count)))
                let value = sin(2 * .pi * tone.frequency * Double(n) / sampleRate) * rise * fade
                samples.append(Float(value) * peak)
            }
            if index < tones.count - 1 { samples.append(contentsOf: repeatElement(0, count: gap)) }
        }
        return samples
    }

    /// The samples as a WAV file, 16-bit mono, which `NSSound` plays from memory.
    static func wavData(_ samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let payload = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + payload))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(payload))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        return data
    }
}
