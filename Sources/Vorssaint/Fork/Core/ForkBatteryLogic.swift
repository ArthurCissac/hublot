// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 8, the battery as Juicy did it: alerts at several levels with a
/// coloured halo and a sound, a sound when the charger comes and goes, and a
/// device's battery pinned in the menu bar. Pure: readings come in, what to
/// show and play goes out. The sounds are made here, note by note, not taken
/// from anywhere.
enum ForkBatteryLogic {
    enum AlertColor: Equatable {
        case orange, yellow, red, green
    }

    struct Alert: Equatable {
        enum Kind: Equatable { case low, charged }
        let kind: Kind
        let percent: Int
        let color: AlertColor
        let halo: Bool
        let sound: Sound
    }

    /// The alerts, as set in Juicy (docs/reference/juicy.md): three low
    /// levels with a halo, and the charge reaching 80 % without one.
    static let alerts: [Alert] = [
        Alert(kind: .low, percent: 20, color: .orange, halo: true, sound: .low),
        Alert(kind: .low, percent: 15, color: .yellow, halo: true, sound: .low),
        Alert(kind: .low, percent: 5, color: .red, halo: true, sound: .critical),
        Alert(kind: .charged, percent: 80, color: .green, halo: false, sound: .charged),
    ]

    /// The Mac's battery, as read.
    struct Reading: Equatable {
        let percent: Int
        let onPower: Bool
    }

    /// The alert a change of reading crosses: on battery, the lowest level
    /// just gone under; on power, 80 % just reached. Nothing at the first
    /// reading, nor while the level stays on one side.
    static func alert(from previous: Reading?, to current: Reading) -> Alert? {
        guard let previous else { return nil }
        if current.onPower {
            return alerts.first { $0.kind == .charged && previous.percent < $0.percent && current.percent >= $0.percent }
        }
        // Falling past several levels at once (after sleep, say) shows the lowest.
        return alerts
            .filter { $0.kind == .low && previous.percent > $0.percent && current.percent <= $0.percent }
            .min { $0.percent < $1.percent }
    }

    enum PowerChange: Equatable { case plugged, unplugged }

    static func powerChange(from previous: Reading?, to current: Reading) -> PowerChange? {
        guard let previous, previous.onPower != current.onPower else { return nil }
        return current.onPower ? .plugged : .unplugged
    }

    // MARK: - Pinned device

    /// The pinned device's battery for the menu bar, in place of the lowest
    /// one: found by its identifier, or by its name; nil when none is pinned
    /// or it is not around.
    static func pinnedMetric(devices: [PeripheralBatteryDevice], pinned: String) -> (label: String, value: String)? {
        guard !pinned.isEmpty,
              let device = devices.first(where: { $0.id == pinned }) ?? devices.first(where: { $0.name == pinned })
        else { return nil }
        return (label(for: device), "\(device.percent)%")
    }

    /// A short label: the kind of Apple device when its name tells it.
    static func label(for device: PeripheralBatteryDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("ipad") { return "IPD" }
        if name.contains("iphone") { return "IPH" }
        if name.contains("watch") { return "WCH" }
        return device.kind.menuLabel
    }

    // MARK: - Sounds

    enum Sound: Equatable {
        case low, critical, charged, plugged, unplugged
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
