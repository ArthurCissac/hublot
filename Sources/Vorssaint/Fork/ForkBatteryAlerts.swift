// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import IOKit.ps
import os

/// Lot 8 (see `ForkBatteryLogic`): the Mac's battery is read whenever macOS
/// says its power sources changed. Reaching an alert level shows a banner,
/// a coloured halo round the screens for the low levels, and plays a sound;
/// the charger coming or going plays its own sound. Nothing runs while both
/// settings are off, or on a Mac without a battery. Main thread only.
final class ForkBatteryAlerts {
    static let shared = ForkBatteryAlerts()
    typealias Logic = ForkBatteryLogic

    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }
    private var last: Logic.Reading?
    private var halos: [NSWindow] = []
    private var sound: NSSound?
    /// What happened, for `log show --predicate 'category == "battery"'`.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "battery")

    private init() {}

    func start() {
        resync.schedule()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            // Never from inside the notification: see ForkCoalescedMainAction.
            self?.resync.schedule()
        })
    }

    private var wanted: Bool {
        let defaults = UserDefaults.standard
        return (defaults.bool(forKey: DefaultsKey.forkBatteryAlerts) || defaults.bool(forKey: DefaultsKey.forkPowerSounds))
            && AppFeature.monitorPower.isAvailable && PowerSampler.hasInternalBattery
    }

    private func sync() {
        if wanted {
            guard source == nil else { return }
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let created = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                Unmanaged<ForkBatteryAlerts>.fromOpaque(context).takeUnretainedValue().powerChanged()
            }, context)?.takeRetainedValue() else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
            source = created
            last = Self.reading()
        } else if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = nil
            last = nil
        }
    }

    private func powerChanged() {
        guard let current = Self.reading() else { return }
        let previous = last
        last = current
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.forkPowerSounds), let change = Logic.powerChange(from: previous, to: current) {
            play(change == .plugged ? .plugged : .unplugged)
        }
        if defaults.bool(forKey: DefaultsKey.forkBatteryAlerts), let alert = Logic.alert(from: previous, to: current) {
            show(alert)
        }
    }

    /// The internal battery's level and whether the charger is in.
    private static func reading() -> Logic.Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return Logic.Reading(percent: Int((Double(current) / Double(maximum) * 100).rounded()), onPower: onPower)
        }
        return nil
    }

    // MARK: - Showing an alert

    private func show(_ alert: Logic.Alert) {
        let text = ForkBatteryStrings.current
        let message = alert.kind == .charged ? text.charged(alert.percent) : text.low(alert.percent)
        let symbol = alert.kind == .charged ? "battery.100.bolt" : alert.percent <= 5 ? "battery.0" : "battery.25"
        QuickToolHUD.show(icon: symbol, message: message, swatch: Self.color(alert.color))
        if alert.halo, UserDefaults.standard.bool(forKey: DefaultsKey.forkBatteryHalo) { showHalo(Self.color(alert.color)) }
        play(alert.sound)
        log.notice("alert at \(alert.percent)%")
    }

    private static func color(_ color: Logic.AlertColor) -> NSColor {
        switch color {
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .green: return .systemGreen
        }
    }

    /// A glow round the edge of every screen, pulsing twice, taking no clicks.
    private func showHalo(_ color: NSColor) {
        halos.forEach { $0.orderOut(nil) }
        halos = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = HaloView(color: color)
            window.alphaValue = 0
            window.orderFrontRegardless()
            return window
        }
        let shown = halos
        // Two pulses, then gone.
        let steps: [(CGFloat, TimeInterval)] = [(1, 0.35), (0.35, 0.35), (1, 0.35), (0, 0.7)]
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

        init(color: NSColor) {
            self.color = color
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            // Layered strokes, strong at the edge and fading inward.
            for step in 0..<14 {
                let inset = CGFloat(step) * 3 + 1.5
                color.withAlphaComponent(0.55 * pow(0.78, CGFloat(step))).setStroke()
                let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
                path.lineWidth = 3
                path.stroke()
            }
        }
    }

    // MARK: - Sounds

    private func play(_ sound: Logic.Sound) {
        let rate = 44_100
        let samples = Logic.samples(for: Logic.tones(for: sound), sampleRate: Double(rate))
        self.sound?.stop()
        self.sound = NSSound(data: Logic.wavData(samples, sampleRate: rate))
        self.sound?.play()
    }
}
