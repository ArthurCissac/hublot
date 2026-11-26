// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 8: battery alerts, charger sounds, the pinned device.
enum ForkBatteryTests {
    typealias Logic = ForkBatteryLogic
    typealias Panel = ForkBatteryPanelLogic

    static func run(_ suite: TestSuite) {
        typealias Reading = Logic.Reading
        rules(suite)

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
        suite.expect(Logic.pinnedMetric(devices: devices, pinned: "") == nil,
                     "nothing pinned: the menu bar shows the lowest as before")
        suite.expect(Logic.pinnedMetric(devices: [], pinned: "iPad de Arthur").map { "\($0.label) \($0.value)" } == "IPD —"
            && Logic.pinnedMetric(devices: devices, pinned: "iPhone 15").map { "\($0.label) \($0.value)" } == "IPH —"
            && Logic.pinnedMetric(devices: devices, pinned: "Casque").map { "\($0.label) \($0.value)" } == "PER —",
                     "a pinned device out of range keeps its place with a dash, labelled from its name")

        suite.expect(Logic.bluetoothRefreshInterval(pinned: "") == 300
            && Logic.bluetoothRefreshInterval(pinned: "iPad de Arthur") == 120,
                     "devices are read over Bluetooth every five minutes, every two while one is pinned")

        suite.expect(Logic.bluetoothStatus(access: .notAsked, radio: .unknown) == .askNeeded
            && Logic.bluetoothStatus(access: .refused, radio: .on) == .refused
            && Logic.bluetoothStatus(access: .allowed, radio: .off) == .off
            && Logic.bluetoothStatus(access: .allowed, radio: .on) == .ready
            && Logic.bluetoothStatus(access: .allowed, radio: .unknown) == .ready,
                     "the settings ask for Bluetooth, point to System Settings when refused, and say when it is off")

        suite.expect(Logic.PowerChange.allCases.map(Panel.soundEvent(for:)) == [.plugged, .unplugged],
                     "the try buttons cover both charger sounds")
        panel(suite)
        details(suite)
        menu(suite)
        energy(suite)
        let trim = ForkMenuBarIconLogic.trimmedRect(ink: CGRect(x: 6, y: 3, width: 14, height: 14), canvas: CGSize(width: 26, height: 20), margin: 1)
        suite.expect(trim == CGRect(x: 5, y: 0, width: 16, height: 20)
            && ForkMenuBarIconLogic.trimmedRect(ink: CGRect(x: 0, y: 0, width: 26, height: 20), canvas: CGSize(width: 26, height: 20), margin: 1)
                == CGRect(x: 0, y: 0, width: 26, height: 20)
            && Defaults.registeredDefaults[DefaultsKey.forkTightMenuBarIcon] as? Bool == true,
                     "the Hublot icon keeps its ink and a point each side, at full height; a full-width mark stays whole")

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
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkBatteryAlerts] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkPowerSounds] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkPinnedBatteryDevice] as? String == "",
                     "alerts and charger sounds are on by default, nothing is pinned")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.forkBatteryAlerts, DefaultsKey.forkBatteryAlertRules,
                                                                        DefaultsKey.forkPowerSounds, DefaultsKey.forkPinnedBatteryDevice]),
                     "lot 8's settings travel in the settings backup")
    }

    /// The battery item, its panel, the devices Hublot connects to, the halo, the sounds.
    static func panel(_ suite: TestSuite) {
        suite.expect(Panel.kind(model: "iPad7,4", name: "Tablette") == .iPad
            && Panel.kind(model: "iPhone16,1", name: "x") == .iPhone
            && Panel.kind(model: nil, name: "iphone d\u{2019}arthur") == .iPhone
            && Panel.kind(model: nil, name: "Magic Mouse", accessory: .mouse) == .mouse
            && Panel.kind(model: nil, name: "AirPods Pro d\u{2019}arthur") == .audio,
                     "a device's kind comes from its model number, else its name, else what macOS says")

        let paired = ["AirPods Pro d\u{2019}arthur", "iPad d\u{2019}arthur", "iphone d\u{2019}arthur", "JBL BOOMBOX"]
        suite.expect(Panel.isOwnPhoneOrTablet(name: "iPad d\u{2019}arthur", pairedNames: paired)
            && Panel.isOwnPhoneOrTablet(name: "IPHONE D'ARTHUR", pairedNames: paired),
                     "a search keeps this Mac's own iPhone and iPad, names compared loosely")
        suite.expect(!Panel.isOwnPhoneOrTablet(name: nil, pairedNames: paired)
            && !Panel.isOwnPhoneOrTablet(name: "iPhone de Paul", pairedNames: paired)
            && !Panel.isOwnPhoneOrTablet(name: "AirPods Pro d\u{2019}arthur", pairedNames: paired),
                     "never a neighbour's phone (no name, or not paired), nor an accessory macOS already reads")
        suite.expect(Panel.isOwnPhoneOrTablet(name: "iPad d\u{2019}arthur", pairedNames: [])
            && !Panel.isOwnPhoneOrTablet(name: nil, pairedNames: []),
                     "without the paired list, a resolved iPhone or iPad name is enough")
        suite.expect(Panel.unknownPhonesOrTablets(pairedNames: paired, known: ["iPad d'arthur"]) == ["iphone d\u{2019}arthur"]
            && Panel.unknownPhonesOrTablets(pairedNames: paired, known: ["iPad d'arthur", "iphone d'arthur"]).isEmpty,
                     "a search runs while a paired iPhone or iPad is still unknown")

        let profiler = Data(#"{"SPBluetoothDataType":[{"controller_properties":{},"device_connected":[{"Clavier":{}}],"device_not_connected":[{"iPad d\u2019arthur":{}},{"iphone d\u2019arthur":{}}]}]}"#.utf8)
        suite.expect(Panel.pairedNames(fromSystemProfilerJSON: profiler) == ["Clavier", "iPad d\u{2019}arthur", "iphone d\u{2019}arthur"]
            && Panel.pairedNames(fromSystemProfilerJSON: Data()).isEmpty,
                     "the paired devices are read from system_profiler, connected or not")

        suite.expect(Panel.batteryLevel([84]) == 84 && Panel.batteryLevel([0]) == 0
            && Panel.batteryLevel([101]) == nil && Panel.batteryLevel([]) == nil && Panel.batteryLevel([1, 2]) == nil,
                     "the battery level characteristic is one byte from 0 to 100")

        let seen = Date(timeIntervalSince1970: 1_000_000)
        let own = [Panel.Device(id: "ipad", name: "iPad d\u{2019}arthur", kind: .iPad, percent: 84, isNearby: false, lastSeen: seen),
                   Panel.Device(id: "iphone", name: "iphone d\u{2019}arthur", kind: .iPhone, percent: 97, isNearby: true, lastSeen: seen)]
        let accessories = [PeripheralBatteryDevice(id: "m", name: "Magic Mouse", percent: 40, kind: .mouse),
                           PeripheralBatteryDevice(id: "g", name: "iphone d'arthur", percent: 96, kind: .device)]
        let listed = Panel.panelDevices(own: own, accessories: accessories)
        suite.expect(listed.map(\.id) == ["iphone", "m", "ipad"],
                     "the panel lists nearby devices first, iPhone before accessories, and a device once")
        suite.expect(Panel.pinned(in: listed, pinned: "iPad d'arthur")?.id == "ipad"
            && Panel.pinned(in: listed, pinned: "m")?.id == "m"
            && Panel.pinned(in: listed, pinned: "") == nil,
                     "the pinned device is found by name or identifier")
        suite.expect(Panel.minutesAgo(seen, now: seen.addingTimeInterval(12 * 60 + 30)) == 12
            && Panel.minutesAgo(seen, now: seen.addingTimeInterval(-60)) == 0,
                     "an away device says how long ago it was read")

        suite.expect(Panel.level(5) == .critical && Panel.level(10) == .critical && Panel.level(20) == .low && Panel.level(21) == .normal,
                     "levels: red to 10 %, orange to 20 %, green above")
        suite.expect(Panel.macSymbol(percent: 50, charging: true) == "battery.100percent.bolt"
            && Panel.macSymbol(percent: 95, charging: false) == "battery.100percent"
            && Panel.macSymbol(percent: 70, charging: false) == "battery.75percent"
            && Panel.macSymbol(percent: 50, charging: false) == "battery.50percent"
            && Panel.macSymbol(percent: 20, charging: false) == "battery.25percent"
            && Panel.macSymbol(percent: 5, charging: false) == "battery.0percent",
                     "the menu bar symbol follows the Mac's level, with a bolt while charging")
        suite.expect(Panel.duration(65 * 60).map { "\($0.hours):\($0.minutes)" } == "1:5"
            && Panel.duration(nil) == nil && Panel.duration(-1) == nil,
                     "a time left reads as hours and minutes, nothing when macOS does not know")

        let large = Panel.haloBands(width: Panel.HaloSize.large.width)
        suite.expect(Panel.HaloSize.thin.width < Panel.HaloSize.medium.width && Panel.HaloSize.medium.width < Panel.HaloSize.large.width
            && Panel.HaloSize.large.width >= 80,
                     "the halo comes thin, medium or large, large reaching far into the screen")
        suite.expect(abs((large.first?.alpha ?? 0) - 0.85) < 0.001
            && zip(large, large.dropFirst()).allSatisfy { $0.alpha > $1.alpha && $1.inset > $0.inset }
            && (large.last?.alpha ?? 1) < 0.01
            && (large.last.map { $0.inset + $0.lineWidth / 2 } ?? 0) >= Panel.HaloSize.large.width,
                     "the glow is strongest at the edge and fades smoothly to nothing across its width")

        let systemNames = ["Glass", "Tink"]
        suite.expect(Panel.SoundEvent.allCases.allSatisfy {
            Panel.soundChoice(stored: nil, fallback: $0.defaultChoice, systemNames: systemNames) == $0.defaultChoice
                && Defaults.registeredDefaults[$0.defaultsKey] as? String == $0.defaultChoice.stored
        }, "the charger's moments have their own Hublot sounds by default, registered")
        suite.expect(Panel.soundChoice(stored: "system.Glass", fallback: .hublot(.low), systemNames: systemNames) == .system("Glass")
            && Panel.soundChoice(stored: "hublot.chime", fallback: .hublot(.low), systemNames: systemNames) == .hublot(.chime)
            && Panel.soundChoice(stored: "file.Gong.m4a", fallback: .hublot(.low), systemNames: systemNames, fileNames: ["Gong.m4a"]) == .file("Gong.m4a")
            && Panel.soundChoice(stored: "none", fallback: .hublot(.low), systemNames: systemNames) == Panel.SoundChoice.none,
                     "a moment can play a macOS sound, another Hublot sound, an imported sound, or nothing")
        suite.expect(Panel.soundChoice(stored: "system.Absent", fallback: .hublot(.critical), systemNames: systemNames) == .hublot(.critical)
            && Panel.soundChoice(stored: "file.Deleted.wav", fallback: .hublot(.plugged), systemNames: systemNames) == .hublot(.plugged)
            && Panel.soundChoice(stored: "hublot.absent", fallback: .hublot(.plugged), systemNames: systemNames) == .hublot(.plugged),
                     "a sound this Mac does not have falls back to the moment's own")
        suite.expect(Panel.SoundChoice.system("Glass").stored == "system.Glass" && Panel.SoundChoice.hublot(.low).stored == "hublot.low"
            && Panel.SoundChoice.file("Gong.m4a").stored == "file.Gong.m4a",
                     "choices are stored as plain text")
        suite.expect(Logic.Sound.allCases.allSatisfy { !Logic.tones(for: $0).isEmpty },
                     "every Hublot sound has notes")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkBatteryStatusItem] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryHaloSize] as? String == "large"
            && Defaults.registeredDefaults[DefaultsKey.forkBluetoothDeviceCache] == nil
            && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkBluetoothDeviceCache),
                     "the battery item is on, the halo large; this Mac's devices stay out of backups")
    }

    /// The panel's details of the Mac's battery, its last 24 hours, the figures' format.
    static func details(_ suite: TestSuite) {
        typealias Details = ForkBatteryDetailsLogic
        let read = Details.details(from: [
            "Voltage": NSNumber(value: 11398),
            "InstantAmperage": NSNumber(value: UInt64(18_446_744_073_709_549_972)),
            "CycleCount": NSNumber(value: 222),
            "DesignCycleCount9C": NSNumber(value: 1000),
            "AdapterDetails": ["Watts": NSNumber(value: 70), "Name": "70W USB-C Power Adapter"] as [String: Any],
        ])
        suite.expect(read.voltage == 11.398 && read.amperage == -1.644 && read.cycles == 222 && read.designCycles == 1000
            && read.adapterWatts == 70 && read.adapterName == "70W USB-C Power Adapter",
                     "the battery's registry entry gives voltage, current (negative from its unsigned bit pattern), cycles, charger")
        suite.expect(abs((read.watts ?? 0) + 18.738) < 0.01 && read.cycleShare == 0.222,
                     "power is voltage times current, the cycles a share of the designed ones")
        suite.expect(Details.details(from: ["Amperage": NSNumber(value: -1644)]).amperage == -1.644
            && Details.details(from: ["Voltage": true, "CycleCount": "222"]) == Details.Details()
            && Details.details(from: ["AdapterDetails": ["FamilyCode": NSNumber(value: 0)] as [String: Any]]).adapterWatts == nil,
                     "a signed current reads as is; booleans, strings and an empty charger read as nothing")

        let start = Date(timeIntervalSince1970: 2_000_000)
        func at(_ minutes: Double, _ percent: Int, _ charging: Bool = false) -> Details.Sample {
            Details.Sample(time: start.addingTimeInterval(minutes * 60), percent: percent, charging: charging)
        }
        var history = Details.recording(at(0, 50), in: [])
        history = Details.recording(at(2, 50), in: history)
        suite.expect(history.count == 1, "the same level within five minutes is not recorded again")
        history = Details.recording(at(3, 49), in: history)
        history = Details.recording(at(4, 49, true), in: history)
        history = Details.recording(at(10, 49, true), in: history)
        suite.expect(history.map(\.percent) == [50, 49, 49, 49],
                     "a new level, the charger coming, or five minutes passing are recorded")
        let later = Details.recording(at(24 * 60 + 3.5, 80), in: history)
        suite.expect(later.map(\.percent) == [49, 49, 80],
                     "nothing older than 24 hours is kept")
        suite.expect(Details.recording(at(1, 40), in: history).last?.percent == 40
            && Details.recording(at(1, 40), in: history).count == 2,
                     "readings after a clock set back are dropped")

        let charging = [at(0, 50), at(10, 52, true), at(20, 60, true), at(30, 61), at(40, 61, true)]
        let spans = Details.chargingSpans(charging, now: start.addingTimeInterval(50 * 60))
        suite.expect(spans.count == 2 && spans[0] == start.addingTimeInterval(600)...start.addingTimeInterval(1800)
            && spans[1].lowerBound == start.addingTimeInterval(2400) && spans[1].upperBound == start.addingTimeInterval(3000),
                     "the chart's charging bands run from charging to unplugging, the last one to now")

        let fr = Locale(identifier: "fr_FR"), en = Locale(identifier: "en_US"), thin = "\u{202F}"
        suite.expect(Details.signed(-18.738, unit: "W", locale: fr, space: thin) == "\u{2212}18,7\u{202F}W"
            && Details.signed(45, unit: "W", locale: fr, space: thin) == "+45,0\u{202F}W"
            && Details.signed(0.01, unit: "W", locale: fr, space: thin) == "0,0\u{202F}W"
            && Details.number(11.398, digits: 2, unit: "V", locale: fr, space: thin) == "11,40\u{202F}V"
            && Details.signed(-1.644, digits: 2, unit: "A", locale: fr, space: thin) == "\u{2212}1,64\u{202F}A"
            && Details.signed(-18.738, unit: "W", locale: en, space: " ") == "\u{2212}18.7 W",
                     "figures use the language's decimal mark, a true minus sign, a plus when power flows in")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkBatteryHistory] == nil
            && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkBatteryHistory),
                     "the 24-hour history stays on this Mac, out of backups")
    }

    /// Juicy's alerts as rules: which one a change crosses, what its pill says.
    static func rules(_ suite: TestSuite) {
        typealias Rules = ForkBatteryAlertRules
        typealias Reading = Logic.Reading
        let rules = Rules.defaultRules
        func mac(_ from: Reading?, _ to: Reading) -> Rules.Rule? { Rules.macRule(from: from, to: to, rules: rules) }

        suite.expect(rules.filter { $0.target == .mac && $0.kind == .low }.map(\.percent) == [20, 15, 5]
            && rules.filter { $0.target == .mac && $0.kind == .low }.map(\.tint) == [.orange, .yellow, .red]
            && rules.filter { $0.target == .mac && $0.kind == .low }.allSatisfy(\.glow)
            && rules.first { $0.target == .mac && $0.kind == .charged }.map { $0.percent == 80 && $0.tint == .green && !$0.glow } == true,
                     "by default, Arthur's Juicy alerts: 20 % orange, 15 % yellow, 5 % red with a halo, 80 % reached in green")
        suite.expect(mac(nil, Reading(percent: 10, onPower: false)) == nil
            && mac(Reading(percent: 21, onPower: false), Reading(percent: 20, onPower: false))?.tint == .orange
            && mac(Reading(percent: 6, onPower: false), Reading(percent: 5, onPower: false))?.tint == .red
            && mac(Reading(percent: 19, onPower: false), Reading(percent: 18, onPower: false)) == nil,
                     "on battery, each level shows once as it is reached; nothing at the first reading, nor between levels")
        suite.expect(mac(Reading(percent: 30, onPower: false), Reading(percent: 12, onPower: false))?.percent == 15,
                     "falling past two levels at once, after sleep, shows the lower on waking")
        suite.expect(mac(Reading(percent: 21, onPower: true), Reading(percent: 20, onPower: true)) == nil
            && mac(Reading(percent: 21, onPower: true, charging: false), Reading(percent: 20, onPower: true, charging: false))?.percent == 20,
                     "while charging, low levels say nothing; plugged into a charger too weak, they do")
        suite.expect(mac(Reading(percent: 79, onPower: true), Reading(percent: 80, onPower: true))?.kind == .charged
            && mac(Reading(percent: 80, onPower: true), Reading(percent: 81, onPower: true)) == nil,
                     "charging to 80 % says so, once")
        var off = rules
        off[0].enabled = false
        suite.expect(Rules.macRule(from: Reading(percent: 21, onPower: false), to: Reading(percent: 20, onPower: false), rules: off) == nil,
                     "a rule turned off says nothing")

        suite.expect(Rules.deviceRule(from: 21, to: 20, rules: rules)?.target == .device
            && Rules.deviceRule(from: nil, to: 10, rules: rules) == nil
            && Rules.deviceRule(from: 99, to: 100, rules: rules) == nil,
                     "a device falling to 20 % alerts; the full one is off by default")
        var full = rules
        full[5].enabled = true
        suite.expect(Rules.deviceRule(from: 99, to: 100, rules: full)?.kind == .charged
            && Rules.deviceRule(from: 100, to: 99, rules: full) == nil,
                     "a device rising to its full level alerts once turned on")

        suite.expect(Rules.decode("") == rules && Rules.decode("not json") == rules
            && Rules.decode(Rules.encode(Array(rules.prefix(2)))) == Array(rules.prefix(2)),
                     "rules are stored as JSON; nothing usable gives the defaults")
        var wild = rules[0]
        wild.percent = 200
        suite.expect(Rules.clamped(wild).percent == 95 && Rules.range(for: .charged) == 50...100,
                     "a low threshold stays between 1 and 95 %, a charge one between 50 and 100 %")
        let added = Rules.newRule(target: .mac, kind: .low, after: rules)
        suite.expect(added.percent == 1 || added.percent < 5,
                     "a new low alert goes under the lowest one")
        suite.expect(Rules.newRule(target: .mac, kind: .charged, after: rules).percent == 85,
                     "a new charge alert goes above the highest one")

        let low = Rules.pill(for: rules[0], percent: 20, minutesLeft: 95, minutesToFull: nil)
        suite.expect(low.message == .low(percent: 20, minutesLeft: 95) && low.tint == .orange && low.glow
            && abs(low.outline - 0.2) < 0.001 && low.sound == "hublot.low",
                     "a low pill says the level and the time left, its outline lit to the level")
        suite.expect(Rules.pill(for: rules[2], percent: 4, minutesLeft: 9, minutesToFull: nil).message == .critical(percent: 4)
            && Rules.pill(for: rules[2], percent: 4, minutesLeft: 9, minutesToFull: nil).sticky,
                     "at 5 % and under the pill asks for the charger, and waits for a click")
        suite.expect(Rules.pluggedPill(percent: 50, watts: 15, minutesToFull: nil, sound: nil).tint == .orange
            && Rules.pluggedPill(percent: 50, watts: 15, minutesToFull: nil, sound: nil).message == .plugged(percent: 50, watts: 15, slow: true, minutesToFull: nil)
            && Rules.pluggedPill(percent: 50, watts: 70, minutesToFull: 40, sound: nil).tint == .green,
                     "plugging in shows the charger's watts, amber when it is too slow")
        suite.expect(Rules.chargerAnnouncement(lastAnnounced: false, onPower: true) == .plugged
            && Rules.chargerAnnouncement(lastAnnounced: true, onPower: false) == .unplugged
            && Rules.chargerAnnouncement(lastAnnounced: true, onPower: true) == nil
            && Rules.chargerAnnouncement(lastAnnounced: nil, onPower: true) == nil
            && Rules.chargerSettle < 0.5 && Rules.wattsSettle >= 1.5,
                     "the charger is announced at once, a flicker back to the last state saying nothing; its watts are read again later")
        suite.expect(Rules.pluggedPill(percent: 50, watts: 15, minutesToFull: nil, sound: nil, settled: false).message
                        == .plugged(percent: 50, watts: nil, slow: false, minutesToFull: nil)
            && Rules.pluggedPill(percent: 50, watts: 15, minutesToFull: nil, sound: nil, settled: false).tint == .green
            && Rules.pluggedPill(percent: 50, watts: 96, minutesToFull: nil, sound: nil, settled: false).message
                        == .plugged(percent: 50, watts: 96, slow: false, minutesToFull: nil)
            && Rules.unpluggedPill(percent: 37, minutesLeft: 220, sound: nil).message == .unplugged(percent: 37, minutesLeft: 220),
                     "before the charger agrees on its power, a low figure is left out rather than called slow")
        suite.expect(Rules.outline(percent: 0) > 0 && Rules.outline(percent: 150) == 1,
                     "the outline always shows a sliver, never more than the whole")
        suite.expect(Rules.PillSize.allCases.map(\.scale) == Rules.PillSize.allCases.map(\.scale).sorted()
            && Rules.PillSize.standard.scale == 1,
                     "pills come from extra small to large, default at full size")
        suite.expect(Rules.isImportableSound(fileName: "Gong.m4a", bytes: 200_000)
            && !Rules.isImportableSound(fileName: "Gong.exe", bytes: 200_000)
            && !Rules.isImportableSound(fileName: "Long.wav", bytes: 6 * 1024 * 1024)
            && !Rules.isImportableSound(fileName: ".hidden.wav", bytes: 10)
            && !Rules.isImportableSound(fileName: "Empty.wav", bytes: 0),
                     "an imported sound must be audio, 5 MB at most, with a plain name")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkBatteryAlertRules] as? String == ""
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryPillSize] as? String == "standard"
            && Defaults.registeredDefaults[DefaultsKey.forkPowerAlertPill] as? Bool == true,
                     "the alert rules start from Juicy's defaults, pills at their usual size, charger pills on")
    }

    /// Juicy's menu bar icon, pinned devices, panel cards, and the battery
    /// information the panel shows.
    static func menu(_ suite: TestSuite) {
        typealias Menu = ForkBatteryMenuLogic
        typealias Details = ForkBatteryDetailsLogic
        suite.expect(Menu.iconTint(percent: 55, charging: false) == .normal && Menu.iconTint(percent: 19, charging: false) == .red
            && Menu.iconTint(percent: 20, charging: false) == .normal && Menu.iconTint(percent: 55, charging: false, lowPower: true) == .orange
            && Menu.iconTint(percent: 10, charging: false, lowPower: true) == .red
            && Menu.iconTint(percent: 10, charging: true, lowPower: true) == .green,
                     "the battery is green while charging, red under 20 %, orange in Low Power Mode, muted otherwise")
        typealias PanelLogic = ForkBatteryPanelLogic
        let moment = Date(timeIntervalSince1970: 4_000_000)
        suite.expect(PanelLogic.isCharging(lastRise: moment.addingTimeInterval(-300), lastFall: nil, now: moment)
            && PanelLogic.isCharging(lastRise: moment.addingTimeInterval(-300), lastFall: moment.addingTimeInterval(-900), now: moment)
            && !PanelLogic.isCharging(lastRise: moment.addingTimeInterval(-900), lastFall: moment.addingTimeInterval(-300), now: moment)
            && !PanelLogic.isCharging(lastRise: moment.addingTimeInterval(-1200), lastFall: nil, now: moment)
            && !PanelLogic.isCharging(lastRise: nil, lastFall: nil, now: moment),
                     "an iPhone or iPad whose level just rose counts as charging, for a quarter of an hour, until it falls")
        suite.expect(Menu.shortTime(minutes: 90) == "1:30" && Menu.shortTime(minutes: 5) == "0:05" && Menu.shortTime(minutes: nil) == nil,
                     "a time left reads 1:30")
        suite.expect(Menu.iconTexts(percent: 32, minutesLeft: 90, mode: .percent, showNumber: true) == ("32", nil)
            && Menu.iconTexts(percent: 32, minutesLeft: 90, mode: .time, showNumber: true) == ("1:30", nil)
            && Menu.iconTexts(percent: 32, minutesLeft: nil, mode: .time, showNumber: true) == ("32", nil)
            && Menu.iconTexts(percent: 32, minutesLeft: 90, mode: .both, showNumber: true) == ("32", "1:30")
            && Menu.iconTexts(percent: 32, minutesLeft: 90, mode: .percent, showNumber: false).inside == nil,
                     "the battery holds the percent or the time; both puts the time beside it; the number can be hidden")
        suite.expect(Menu.iconBodyWidth(for: "100", large: false) > Menu.iconBodyWidth(for: "75", large: false)
            && Menu.iconBodyWidth(for: "1:30", large: false) > Menu.iconBodyWidth(for: "100", large: false)
            && Menu.iconBodyWidth(for: "75", large: true) > Menu.iconBodyWidth(for: "75", large: false)
            && Menu.iconNumberSize(large: false) >= 10.5 && Menu.iconBodyHeight(large: false) >= 15
            && Menu.iconBodyHeight(large: true) <= 16
            && Menu.iconBodyHeight(large: false) - 2 * 2.4 >= Menu.iconNumberSize(large: false) * 0.9,
                     "the battery grows with what it holds, and with the large icon")

        suite.expect(Menu.pinnedNames(stored: "", legacy: "iPad") == ["iPad"]
            && Menu.pinnedNames(stored: Menu.encodePinned(["iPad", "iPhone", "iPad", ""]), legacy: "x") == ["iPad", "iPhone"]
            && Menu.pinnedNames(stored: "", legacy: "").isEmpty,
                     "several devices can be pinned, each once; the first version's single pin still counts")
        suite.expect(Menu.togglingPin("AirPods", in: ["iPad"]) == ["iPad", "AirPods"] && Menu.togglingPin("iPad", in: ["iPad"]).isEmpty
            && Menu.movingPin(["a", "b", "c"], from: 2, by: -1) == ["a", "c", "b"] && Menu.movingPin(["a", "b"], from: 0, by: -1) == ["a", "b"],
                     "pins are added, removed and moved in the menu bar")
        suite.expect(Menu.cardOrder(stored: "") == [.info, .devices, .apps, .history, .flow]
            && Menu.cardOrder(stored: "flow,info,flow,bogus") == [.flow, .info, .devices, .apps, .history]
            && Menu.moving(.flow, onto: .info, in: [.info, .devices, .history, .flow]) == [.flow, .info, .devices, .history]
            && Menu.cardOrder(stored: "history,flow,info,devices") == [.history, .flow, .info, .devices, .apps],
                     "the panel's cards keep the order they were dragged into, each once, new ones after")

        let read = Details.details(from: [
            "AppleRawCurrentCapacity": NSNumber(value: 2751), "AppleRawMaxCapacity": NSNumber(value: 5772),
            "DesignCapacity": NSNumber(value: 6249),
            "PowerTelemetryData": ["SystemLoad": NSNumber(value: 11171), "SystemPowerIn": NSNumber(value: 0),
                                   "BatteryPower": NSNumber(value: UInt64(18_446_744_073_709_540_445))] as [String: Any],
        ])
        suite.expect(read.remainingCapacity == 2751 && read.fullCapacity == 5772 && read.designCapacity == 6249
            && abs((read.healthPercent ?? 0) - 92.37) < 0.01,
                     "capacities come in mAh; health is today's full charge against the design")
        suite.expect(read.systemLoad == 11.171 && read.systemPowerIn == 0 && abs((read.batteryPower ?? 0) + 11.171) < 0.001,
                     "the power telemetry gives what the Mac uses and what the battery gives, in watts")
        suite.expect(Details.health(92) == .good && Details.health(74) == .fair && Details.health(55) == .poor,
                     "health is good from 80 %, fair from 60 %, poor under")
        suite.expect(Details.warmth(30.9) == .normal && Details.warmth(42) == .warm && Details.warmth(50) == .hot && Details.warmth(5) == .cold
            && abs(Details.fahrenheit(30.9) - 87.62) < 0.01
            && Details.batteryTemperature([0, 30.9, 29.5, 150]) == 30.9 && Details.batteryTemperature([]) == nil,
                     "the temperature is the warmest plausible sensor, judged against 10 to 40 °C")

        var timing = Details.Details()
        timing.remainingCapacity = 2000
        timing.fullCapacity = 5000
        timing.voltage = 12
        timing.systemLoad = 12
        timing.amperage = 1.5
        suite.expect(Details.estimatedMinutes(charging: false, onPower: false, minutesToEmpty: 95, minutesToFull: nil, details: timing) == 95
            && Details.estimatedMinutes(charging: false, onPower: true, minutesToEmpty: nil, minutesToFull: nil, details: timing) == 120
            && Details.estimatedMinutes(charging: false, onPower: false, minutesToEmpty: nil, minutesToFull: nil, details: timing) == 120
            && Details.estimatedMinutes(charging: true, onPower: true, minutesToEmpty: nil, minutesToFull: 40, details: timing) == 40
            && Details.estimatedMinutes(charging: true, onPower: true, minutesToEmpty: nil, minutesToFull: nil, details: timing) == 120
            && Details.estimatedMinutes(charging: false, onPower: true, minutesToEmpty: nil, minutesToFull: nil, details: Details.Details()) == nil,
                     "the time left is macOS's own, else an estimate: 24 Wh at 12 W last 2 h, 3 Ah at 1.5 A fill in 2 h; plugged in but paused too")
        let onBattery = Details.flow(read, onPower: false)
        suite.expect(abs(onBattery.batteryToMac - 11.171) < 0.001 && onBattery.chargerToMac == 0 && onBattery.chargerToBattery == 0
            && onBattery.macLoad == 11.171,
                     "on battery, power flows from the battery to the Mac")
        var charging = Details.Details()
        charging.systemPowerIn = 60
        charging.systemLoad = 15
        charging.batteryPower = 40
        let plugged = Details.flow(charging, onPower: true)
        suite.expect(plugged.chargerToBattery == 40 && plugged.chargerToMac == 15 && plugged.batteryToMac == 0,
                     "plugged in, the charger feeds the Mac and fills the battery")

        let legacy = Data(#"[{"time":0,"percent":50,"charging":true}]"#.utf8)
        suite.expect((try? JSONDecoder().decode([Details.Sample].self, from: legacy))?.first?.onPower == true,
                     "history saved before « on power » was recorded still reads")
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        func sample(_ minutes: Double, _ percent: Int, charging: Bool = false, onPower: Bool = false) -> Details.Sample {
            Details.Sample(time: t0.addingTimeInterval(minutes * 60), percent: percent, charging: charging, onPower: onPower)
        }
        let draining = [sample(0, 60), sample(10, 58, onPower: true), sample(20, 56, onPower: true), sample(30, 55, onPower: true),
                        sample(40, 55, onPower: true), sample(50, 57, charging: true, onPower: true)]
        let amber = Details.drainingOnPowerSpans(draining)
        suite.expect(amber.count == 1 && amber[0] == t0.addingTimeInterval(600)...t0.addingTimeInterval(1800),
                     "plugged in while the level still falls shows amber on the chart, a paused charge does not")
        let day = (0..<10).map { sample(Double($0) * 120, 50 + $0) }
        let now = t0.addingTimeInterval(18 * 60 * 60)
        suite.expect(Details.visible(day, hours: 6, now: now).first?.time == t0.addingTimeInterval(10 * 3600)
            && Details.visible(day, hours: 24, now: now).count == 10,
                     "the chart keeps the chosen hours, from the reading just before them")
        suite.expect(Details.grouped(5585, locale: Locale(identifier: "en_US")) == "5,585"
            && Details.grouped(5585, locale: Locale(identifier: "fr_FR")).filter(\.isNumber) == "5585"
            && Details.grouped(5585, locale: Locale(identifier: "fr_FR")).count == 5,
                     "thousands are grouped as the language does")

        typealias Panel = ForkBatteryPanelLogic
        let rows = [Panel.Device(id: "a", name: "Keyboard", kind: .keyboard, percent: 17, isNearby: true, lastSeen: nil),
                    Panel.Device(id: "b", name: "Mouse", kind: .mouse, percent: 10, isNearby: true, lastSeen: nil),
                    Panel.Device(id: "c", name: "iPad", kind: .iPad, percent: 5, isNearby: false, lastSeen: nil),
                    Panel.Device(id: "d", name: "AirPods", kind: .audio, percent: 100, isNearby: true, lastSeen: nil)]
        suite.expect(Panel.ranked(rows).map(\.id) == ["b", "a", "d", "c"],
                     "devices are ranked by level, the lowest first, the ones out of range last")
        suite.expect(Panel.rowTint(10) == .critical && Panel.rowTint(17) == .low && Panel.rowTint(67) == .normal && Panel.rowTint(100) == .full,
                     "a device's row is red, orange, plain or green with its level")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkBatteryIconColors] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryIconNumber] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryIconText] as? String == "percent"
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryChartHours] as? Int == 12,
                     "by default the icon shows the level inside, in colour; the chart shows 12 hours")
    }

    /// Juicy's energy per app: processes counted for their app, the hours
    /// and days kept, the rows and sparklines, an app drawing a lot.
    static func energy(_ suite: TestSuite) {
        typealias Energy = ForkAppEnergyLogic
        suite.expect(Energy.appBundle(executable: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)")
                        == "/Applications/Google Chrome.app"
            && Energy.appBundle(executable: "/usr/libexec/trustd") == nil
            && Energy.name(bundle: "/Applications/Google Chrome.app") == "Google Chrome",
                     "a helper's energy counts for the app around it; processes outside an app are left out")

        let first = [Energy.Process(pid: 1, bundle: "A.app", energy: 5_000_000_000)]
        suite.expect(Energy.joules(previous: nil, current: first).isEmpty,
                     "the first reading only sets the baseline")
        let second = [Energy.Process(pid: 1, bundle: "A.app", energy: 8_000_000_000),
                      Energy.Process(pid: 2, bundle: "A.app", energy: 1_000_000_000),
                      Energy.Process(pid: 3, bundle: "B.app", energy: 2_000_000_000)]
        let joules = Energy.joules(previous: [1: 5_000_000_000, 3: 2_000_000_000], current: second)
        suite.expect(joules == ["A.app": 4], "a process adds what it used since; a new one all of its own; an idle one nothing")
        suite.expect(Energy.joules(previous: [1: 9_000_000_000], current: [Energy.Process(pid: 1, bundle: "A.app", energy: 2_000_000_000)])
                        == ["A.app": 2],
                     "a pid reused by a new process counts from zero")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(0)
        let hour = Energy.hourStart(noon, calendar: calendar)
        var store = Energy.adding(["A.app": 3600, "B.app": 1800], at: noon, to: Energy.Store(), calendar: calendar)
        store = Energy.adding(["A.app": 3600], at: noon.addingTimeInterval(3600), to: store, calendar: calendar)
        suite.expect(store.hours[hour]?["A.app"] == 1 && store.hours[hour]?["B.app"] == 0.5
            && store.days[Energy.dayStart(noon, calendar: calendar)]?["A.app"] ?? 0 >= 1,
                     "joules become watt-hours in their hour and their day")
        let later = Energy.adding(["A.app": 3600], at: noon.addingTimeInterval(25 * 3600), to: store, calendar: calendar)
        suite.expect(later.hours[hour] == nil, "hours older than a day are dropped")
        let crowded = Dictionary(uniqueKeysWithValues: (0..<40).map { ("App\($0).app", Double($0 + 1) * 3600) })
        let trimmed = Energy.adding(crowded, at: noon, to: Energy.Store(), calendar: calendar)
        suite.expect(trimmed.hours[hour]?.count == Energy.keptApps && trimmed.hours[hour]?["App39.app"] != nil,
                     "a bucket keeps its 30 biggest apps")

        let liveRows = Energy.rows(period: .live, live: ["A.app": 6, "B.app": 2, "C.app": 0.001], store: Energy.Store(), now: noon)
        suite.expect(liveRows.map(\.bundle) == ["A.app", "B.app"] && abs((liveRows.first?.share ?? 0) - 0.75) < 0.001,
                     "the live view lists the apps drawing now, the biggest first, with their share")
        let dayRows = Energy.rows(period: .day, live: [:], store: store, now: noon.addingTimeInterval(3600), calendar: calendar)
        suite.expect(dayRows.first?.bundle == "A.app" && dayRows.first?.value == 2 && dayRows.first?.spark.count == 24
            && dayRows.first?.spark.suffix(2) == [1, 1],
                     "24 hours add up each app's watt-hours, with a sparkline of the hours")
        suite.expect(Energy.rows(period: .week, live: [:], store: store, now: noon, calendar: calendar).first?.spark.count == 7
            && Energy.rows(period: .month, live: [:], store: store, now: noon, calendar: calendar).first?.spark.count == 30,
                     "7 and 30 days have one point a day")
        suite.expect(Energy.sparkPoints([0, 2, 4]) == [0, 0.5, 1] && Energy.sparkPoints([0, 0]) == [0, 0],
                     "sparklines are scaled to their highest point")

        var recent: [String: [Double]] = [:]
        for watts in [9.0, 8.0, 7.5] { recent = Energy.remembering(["Chrome.app": watts, "Mail.app": 0.2], in: recent) }
        suite.expect(Energy.drifting(recent: recent, threshold: 6, onBattery: true, lastAlert: [:], now: noon) == ["Chrome.app"],
                     "an app above the threshold for three readings on battery is pointed out")
        suite.expect(Energy.drifting(recent: recent, threshold: 6, onBattery: false, lastAlert: [:], now: noon).isEmpty
            && Energy.drifting(recent: recent, threshold: 6, onBattery: true, lastAlert: ["Chrome.app": noon.addingTimeInterval(-600)], now: noon).isEmpty
            && Energy.drifting(recent: recent, threshold: 10, onBattery: true, lastAlert: [:], now: noon).isEmpty,
                     "not while plugged in, not twice within the hour, not under the threshold")
        let quiet = Energy.remembering([:], in: ["Old.app": [0, 0, 0]])
        suite.expect(quiet["Old.app"] == nil && (recent["Chrome.app"]?.count ?? 0) == Energy.driftReadings,
                     "only the last three readings are kept, and an app gone quiet is forgotten")
        suite.expect(ForkBatteryAlertRules.appDriftPill(name: "Chrome", watts: 9).message == .appDrift(name: "Chrome", watts: 9)
            && ForkBatteryAlertRules.appDriftPill(name: "Chrome", watts: 9).tint == .orange,
                     "the alert names the app and its watts, in orange")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkAppEnergyAlerts] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkAppEnergyThreshold] as? Double == 6
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryShortcutEnabled] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkBatteryShortcut] as? String == "",
                     "app alerts from 6 W are on, and the panel's shortcut starts at its default")
    }
}
