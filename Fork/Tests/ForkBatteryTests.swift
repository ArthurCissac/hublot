// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 8: battery alerts, charger sounds, the pinned device.
enum ForkBatteryTests {
    typealias Logic = ForkBatteryLogic

    static func run(_ suite: TestSuite) {
        typealias Reading = Logic.Reading
        suite.expect(Logic.alert(from: nil, to: Reading(percent: 10, onPower: false)) == nil,
                     "no alert at the first reading")
        suite.expect(Logic.alert(from: Reading(percent: 21, onPower: false), to: Reading(percent: 20, onPower: false))?.color == .orange
            && Logic.alert(from: Reading(percent: 16, onPower: false), to: Reading(percent: 15, onPower: false))?.color == .yellow
            && Logic.alert(from: Reading(percent: 6, onPower: false), to: Reading(percent: 5, onPower: false))?.color == .red,
                     "on battery, each level shows once as it is reached: 20 % orange, 15 % yellow, 5 % red")
        suite.expect(Logic.alert(from: Reading(percent: 19, onPower: false), to: Reading(percent: 18, onPower: false)) == nil,
                     "between two levels, nothing")
        suite.expect(Logic.alert(from: Reading(percent: 30, onPower: false), to: Reading(percent: 12, onPower: false))?.percent == 15,
                     "falling past two levels at once, after sleep, shows the lower")
        suite.expect(Logic.alert(from: Reading(percent: 21, onPower: true), to: Reading(percent: 20, onPower: true)) == nil,
                     "on power, low levels say nothing")
        let charged = Logic.alert(from: Reading(percent: 79, onPower: true), to: Reading(percent: 80, onPower: true))
        suite.expect(charged?.kind == .charged && charged?.color == .green && charged?.halo == false,
                     "charging to 80 % says so, in green, without a halo")
        suite.expect(Logic.alert(from: Reading(percent: 80, onPower: true), to: Reading(percent: 81, onPower: true)) == nil,
                     "and only once")
        suite.expect(Logic.alerts.filter { $0.kind == .low }.allSatisfy(\.halo),
                     "the low levels come with a halo")

        suite.expect(Logic.powerChange(from: Reading(percent: 50, onPower: false), to: Reading(percent: 50, onPower: true)) == .plugged
            && Logic.powerChange(from: Reading(percent: 50, onPower: true), to: Reading(percent: 50, onPower: false)) == .unplugged
            && Logic.powerChange(from: nil, to: Reading(percent: 50, onPower: true)) == nil
            && Logic.powerChange(from: Reading(percent: 50, onPower: true), to: Reading(percent: 51, onPower: true)) == nil,
                     "the charger coming and going is heard, not the level moving")

        let devices = [PeripheralBatteryDevice(id: "a", name: "Magic Mouse", percent: 12, kind: .mouse),
                       PeripheralBatteryDevice(id: "b", name: "iPad de Arthur", percent: 64, kind: .device),
                       PeripheralBatteryDevice(id: "c", name: "iPhone", percent: 81, kind: .device)]
        suite.expect(Logic.pinnedMetric(devices: devices, pinned: "b").map { "\($0.label) \($0.value)" } == "IPD 64%"
            && Logic.pinnedMetric(devices: devices, pinned: "iPhone").map { "\($0.label) \($0.value)" } == "IPH 81%",
                     "the pinned device shows in place of the lowest, found by identifier or name")
        suite.expect(Logic.pinnedMetric(devices: devices, pinned: "") == nil
            && Logic.pinnedMetric(devices: devices, pinned: "gone") == nil,
                     "nothing pinned, or not around: the menu bar shows the lowest as before")

        let samples = Logic.samples(for: Logic.tones(for: .charged), sampleRate: 44_100)
        let peak = samples.map(abs).max() ?? 0
        suite.expect(samples.count > 44_100 / 3 && samples.count < 44_100 && peak > 0.2 && peak <= 0.35,
                     "a sound is a few hundred milliseconds long, soft, never clipping")
        suite.expect(abs(samples.first ?? 1) < 0.01 && abs(samples.last ?? 1) < 0.05,
                     "it starts and ends quietly, with no click")
        suite.expect(Logic.tones(for: .plugged).first!.frequency < Logic.tones(for: .plugged).last!.frequency
            && Logic.tones(for: .unplugged).first!.frequency > Logic.tones(for: .unplugged).last!.frequency,
                     "plugging in rises, unplugging falls")
        let wav = Logic.wavData(samples, sampleRate: 44_100)
        suite.expect(wav.count == 44 + samples.count * 2 && wav.prefix(4) == Data("RIFF".utf8)
            && wav[8..<12] == Data("WAVE".utf8),
                     "the sound is played from a WAV made in memory")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkBatteryAlerts] as? Bool == false
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryHalo] as? Bool == false
            && Defaults.registeredDefaults[DefaultsKey.forkPowerSounds] as? Bool == false,
                     "alerts, halo and charger sounds wait to be turned on (lot 8 was set aside)")
    }
}
