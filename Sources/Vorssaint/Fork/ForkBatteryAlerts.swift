// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import IOKit.ps
import os

/// Lot 8, Juicy's alerts (rules in `ForkBatteryAlertRules`). The Mac's
/// battery is read whenever macOS says its power sources changed: a rule
/// crossed shows its pill, plays its sound and, when set, lights a halo round
/// the screen the pointer is on. The charger coming shows a pill with its
/// watts (amber when too slow), going shows one with the time left. The devices' levels, read while the
/// battery item shows, have rules of their own. Nothing runs while the
/// alerts and the charger sounds are off, or on a Mac without a battery.
/// Main thread only.
final class ForkBatteryAlerts {
    static let shared = ForkBatteryAlerts()
    typealias Logic = ForkBatteryLogic
    typealias Panel = ForkBatteryPanelLogic
    typealias Rules = ForkBatteryAlertRules

    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var deviceWatch: AnyCancellable?
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }
    private var last: Logic.Reading?
    private var deviceLevels: [String: Int] = [:]
    private var chargerPending: DispatchWorkItem?
    /// Plugged in or not, as last announced: a flicker back to it says nothing.
    private var lastChargerAnnounced: Bool?
    private var halos: [NSWindow] = []
    /// What happened, for `log show --predicate 'category == "battery"'`.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "battery")

    private init() {}

    func start() {
        // The island's own « Plugged in / On battery » doubles the charger
        // pills: turned off once, it can be turned back on in its settings.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.forkPowerAlertPill), !defaults.bool(forKey: DefaultsKey.forkNotchBatteryMigrated) {
            defaults.set(true, forKey: DefaultsKey.forkNotchBatteryMigrated)
            defaults.set(false, forKey: DefaultsKey.notchBattery)
        }
        resync.schedule()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            // Never from inside the notification: see ForkCoalescedMainAction.
            self?.resync.schedule()
        })
    }

    private var defaults: UserDefaults { .standard }

    private var rules: [Rules.Rule] {
        Rules.decode(defaults.string(forKey: DefaultsKey.forkBatteryAlertRules) ?? "")
    }

    private var wanted: Bool {
        (defaults.bool(forKey: DefaultsKey.forkBatteryAlerts) || defaults.bool(forKey: DefaultsKey.forkPowerSounds)
            || defaults.bool(forKey: DefaultsKey.forkPowerAlertPill))
            && AppFeature.monitorPower.isAvailable && PowerSampler.hasInternalBattery
    }

    private func sync() {
        if wanted {
            if source == nil {
                let context = Unmanaged.passUnretained(self).toOpaque()
                if let created = IOPSNotificationCreateRunLoopSource({ context in
                    guard let context else { return }
                    Unmanaged<ForkBatteryAlerts>.fromOpaque(context).takeUnretainedValue().powerChanged()
                }, context)?.takeRetainedValue() {
                    CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
                    source = created
                    last = Self.reading()
                    lastChargerAnnounced = last?.onPower
                }
            }
        } else if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = nil
            last = nil
            chargerPending?.cancel()
            lastChargerAnnounced = nil
        }
        // The devices: only while the alerts are on (their levels are read
        // while the battery item shows).
        let watchDevices = defaults.bool(forKey: DefaultsKey.forkBatteryAlerts) && AppFeature.monitorPower.isAvailable
        if watchDevices, deviceWatch == nil {
            deviceWatch = ForkBatteryStatusItem.shared.model.$devices.sink { [weak self] devices in
                DispatchQueue.main.async { self?.devicesChanged(devices) }
            }
        } else if !watchDevices, deviceWatch != nil {
            deviceWatch = nil
            deviceLevels = [:]
        }
    }

    // MARK: - The Mac

    private func powerChanged() {
        guard let mac = ForkBatteryPanelModel.readMac() else { return }
        let current = Logic.Reading(percent: mac.percent, onPower: mac.onPower, charging: mac.charging)
        let previous = last
        last = current
        if Logic.powerChange(from: previous, to: current) != nil { scheduleCharger() }
        if defaults.bool(forKey: DefaultsKey.forkBatteryAlerts), let rule = Rules.macRule(from: previous, to: current, rules: rules) {
            show(Rules.pill(for: rule, percent: mac.percent, minutesLeft: mac.minutesToEmpty, minutesToFull: mac.minutesToFull))
            log.notice("alert at \(mac.percent)%")
        }
    }

    /// The charger is announced once it has settled (`Rules.chargerSettle`).
    private func scheduleCharger() {
        chargerPending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.announceCharger() }
        chargerPending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Rules.chargerSettle, execute: work)
    }

    private func announceCharger() {
        guard let mac = ForkBatteryPanelModel.readMac(),
              let change = Rules.chargerAnnouncement(lastAnnounced: lastChargerAnnounced, onPower: mac.onPower) else { return }
        lastChargerAnnounced = mac.onPower
        chargerChanged(change, mac: mac)
    }

    /// The charger's watts once it has agreed on its power, in the pill
    /// still showing.
    private func refreshChargerWatts(shown: Int?) {
        guard lastChargerAnnounced == true, let mac = ForkBatteryPanelModel.readMac(), mac.onPower else { return }
        let watts = ForkBatteryPanelModel.readBattery().adapterWatts
        guard watts != shown else { return }
        ForkBatteryPillPresenter.shared.refresh(Rules.pluggedPill(percent: mac.percent, watts: watts,
                                                                  minutesToFull: mac.minutesToFull, sound: nil))
    }

    private func chargerChanged(_ change: Logic.PowerChange, mac: ForkBatteryPanelModel.MacBattery) {
        let event = Panel.soundEvent(for: change)
        let sound: String? = defaults.bool(forKey: DefaultsKey.forkPowerSounds)
            ? ForkBatterySounds.shared.choice(defaults.string(forKey: event.defaultsKey), fallback: event.defaultChoice).stored
            : nil
        guard defaults.bool(forKey: DefaultsKey.forkPowerAlertPill) else {
            if let sound { play(sound) }
            return
        }
        switch change {
        case .plugged:
            let watts = ForkBatteryPanelModel.readBattery().adapterWatts
            let pill = Rules.pluggedPill(percent: mac.percent, watts: watts, minutesToFull: mac.minutesToFull, sound: sound, settled: false)
            show(pill)
            let shown: Int? = { if case let .plugged(_, shownWatts, _, _) = pill.message { return shownWatts } else { return nil } }()
            DispatchQueue.main.asyncAfter(deadline: .now() + Rules.wattsSettle) { [weak self] in
                self?.refreshChargerWatts(shown: shown)
            }
        case .unplugged:
            show(Rules.unpluggedPill(percent: mac.percent, minutesLeft: mac.minutesToEmpty, sound: sound))
        }
    }

    /// The internal battery's level, the charger, whether it charges.
    private static func reading() -> Logic.Reading? {
        ForkBatteryPanelModel.readMac().map { Logic.Reading(percent: $0.percent, onPower: $0.onPower, charging: $0.charging) }
    }

    // MARK: - The devices

    private func devicesChanged(_ devices: [Panel.Device]) {
        let active = rules
        for device in devices {
            guard device.isNearby, let percent = device.percent else { continue }
            let previous = deviceLevels[device.id]
            deviceLevels[device.id] = percent
            guard let rule = Rules.deviceRule(from: previous, to: percent, rules: active) else { continue }
            show(Rules.devicePill(for: rule, name: device.name, symbol: device.kind.symbol, percent: percent))
            log.notice("device alert at \(percent)%")
        }
    }

    // MARK: - Showing

    /// Tries an alert from the settings: its pill, halo and sound, at a level
    /// a little past its threshold.
    func preview(_ rule: Rules.Rule) {
        let percent = rule.target == .device || rule.kind == .charged ? rule.percent : max(1, rule.percent)
        if rule.target == .device {
            show(Rules.devicePill(for: rule, name: ForkBatteryStrings.current.previewDevice, symbol: "iphone", percent: percent))
        } else {
            let mac = ForkBatteryPanelModel.readMac()
            show(Rules.pill(for: rule, percent: percent, minutesLeft: mac?.minutesToEmpty, minutesToFull: mac?.minutesToFull))
        }
    }

    /// Tries the charger's pill and sound from the settings.
    func preview(_ change: Logic.PowerChange) {
        let event = Panel.soundEvent(for: change)
        let sound = ForkBatterySounds.shared.choice(defaults.string(forKey: event.defaultsKey), fallback: event.defaultChoice).stored
        let mac = ForkBatteryPanelModel.readMac()
        let percent = mac?.percent ?? 80
        switch change {
        case .plugged:
            let battery = ForkBatteryPanelModel.readBattery()
            show(Rules.pluggedPill(percent: percent, watts: battery.adapterWatts ?? 70, minutesToFull: mac?.minutesToFull, sound: sound))
        case .unplugged:
            show(Rules.unpluggedPill(percent: percent, minutesLeft: mac?.minutesToEmpty, sound: sound))
        }
    }

    /// An app drawing a lot on battery (`ForkAppEnergy`).
    func showAppDrift(name: String, watts: Double) {
        show(Rules.appDriftPill(name: name, watts: watts))
        log.notice("app drawing \(Int(watts.rounded())) W")
    }

    private func show(_ pill: Rules.Pill) {
        let screen = Self.activeScreen
        ForkBatteryPillPresenter.shared.show(pill, on: screen)
        if pill.glow { showHalo(ForkBatteryTintPalette.nsColor(pill.tint), on: screen) }
        if let sound = pill.sound { play(sound) }
    }

    private func play(_ stored: String) {
        let sounds = ForkBatterySounds.shared
        sounds.play(sounds.choice(stored, fallback: .none))
    }

    /// The screen the pointer is on: the alert and its halo stay there.
    private static var activeScreen: NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - The halo

    /// The halo's reach, as set in the settings: large by default, like Juicy's.
    private static var haloSize: Panel.HaloSize {
        Panel.HaloSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.forkBatteryHaloSize) ?? "") ?? .large
    }

    /// A glow round the edge of the screen, pulsing, taking no clicks.
    private func showHalo(_ color: NSColor, on screen: NSScreen) {
        halos.forEach { $0.orderOut(nil) }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = HaloView(color: color, bands: Panel.haloBands(width: Self.haloSize.width))
        window.alphaValue = 0
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        halos = [window]
        let shown = halos
        // Three slow pulses, then gone.
        let steps: [(CGFloat, TimeInterval)] = [(1, 0.4), (0.45, 0.5), (1, 0.4), (0.45, 0.5), (1, 0.4), (0, 0.9)]
        func run(_ index: Int) {
            guard index < steps.count else {
                shown.forEach { $0.orderOut(nil) }
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = steps[index].1
                shown.forEach { $0.animator().alphaValue = steps[index].0 }
            }, completionHandler: { run(index + 1) })
        }
        run(0)
    }

    private final class HaloView: NSView {
        let color: NSColor
        let bands: [Panel.Band]

        init(color: NSColor, bands: [Panel.Band]) {
            self.color = color
            self.bands = bands
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            // Strokes from the edge inward, strong at the edge and fading to
            // nothing (ForkBatteryPanelLogic.haloBands).
            for band in bands {
                color.withAlphaComponent(band.alpha).setStroke()
                let path = NSBezierPath(rect: bounds.insetBy(dx: band.inset, dy: band.inset))
                path.lineWidth = band.lineWidth
                path.stroke()
            }
        }
    }
}
