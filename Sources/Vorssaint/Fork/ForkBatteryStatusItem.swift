// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Carbon.HIToolbox
import Combine
import IOKit
import IOKit.ps
import SwiftUI

/// Lot 8, Juicy's menu: a battery item of its own in the menu bar, the Mac's
/// level with the pinned device's beside it; a click opens a panel with the
/// Mac's battery in detail and every device's level (`ForkBatteryPanelView`).
/// Shown while its setting is on and the Power metrics are available. Gone
/// otherwise, with the Bluetooth links and the accessory reads. Main thread only.
final class ForkBatteryStatusItem: NSObject, NSPopoverDelegate {
    static let shared = ForkBatteryStatusItem()
    typealias Logic = ForkBatteryPanelLogic

    let model = ForkBatteryPanelModel()
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var powerSource: CFRunLoopSource?
    /// ⌃⌥J by default; out of upstream's quick-tool range and after the fork's others.
    private let hotkey = QuickToolHotkey(id: 9_140)
    static let defaultShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.control, .option])
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }

    private override init() {
        super.init()
    }

    func start() {
        resync.schedule()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            // Never from inside the notification: see ForkCoalescedMainAction.
            self?.resync.schedule()
        })
        // Low Power Mode turned on or off: the battery changes colour.
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.powerChanged()
        })
        // Back from System Settings, Bluetooth may have been allowed.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.resync.schedule()
        })
    }

    func closePanel() {
        popover?.performClose(nil)
    }

    private var wanted: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.forkBatteryStatusItem) && AppFeature.monitorPower.isAvailable
    }

    private func sync() {
        if wanted { install() } else { remove() }
        if item != nil { ForkBluetoothDevices.shared.setActive(true) }
        syncHotkey()
        refreshTitle()
    }

    /// The shortcut, only while the battery item shows.
    private func syncHotkey() {
        let defaults = UserDefaults.standard
        hotkey.onPress = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.togglePanel()
        }
        let shortcut = GlobalShortcut(storageValue: defaults.string(forKey: DefaultsKey.forkBatteryShortcut) ?? "") ?? Self.defaultShortcut
        hotkey.sync(enabled: item != nil && defaults.bool(forKey: DefaultsKey.forkBatteryShortcutEnabled),
                    shortcut: shortcut, storageKey: DefaultsKey.forkBatteryShortcut)
    }

    private func install() {
        guard item == nil else { return }
        migrateOnce()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel(ForkBatteryStrings.current.statusItem)
        self.item = item

        // The level and the charger: macOS says when they change.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<ForkBatteryStatusItem>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        ForkBluetoothDevices.shared.setActive(true)
        model.start()
        model.$devices.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshTitle() }
        }.store(in: &cancellables)
    }

    private func remove() {
        guard let item else { return }
        popover?.performClose(nil)
        popover = nil
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        cancellables.removeAll()
        model.stop()
        ForkBluetoothDevices.shared.setActive(false)
    }

    /// The battery item takes over the device figure of the combined menu bar
    /// item (plan of 26/11/2026, question 2), once; it can be turned back on.
    private func migrateOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.forkBatteryStatusItemMigrated) else { return }
        defaults.set(true, forKey: DefaultsKey.forkBatteryStatusItemMigrated)
        defaults.set(false, forKey: DefaultsKey.menuBarPeripheralBattery)
    }

    private func powerChanged() {
        model.refreshMac()
        refreshTitle()
    }

    // MARK: - The item

    private func refreshTitle() {
        guard let button = item?.button else { return }
        let defaults = UserDefaults.standard
        let style = IconStyle(
            colored: defaults.bool(forKey: DefaultsKey.forkBatteryIconColors),
            number: defaults.bool(forKey: DefaultsKey.forkBatteryIconNumber),
            text: Menu.IconText(rawValue: defaults.string(forKey: DefaultsKey.forkBatteryIconText) ?? "") ?? .percent,
            large: defaults.bool(forKey: DefaultsKey.forkBatteryIconLarge))
        let text = ForkBatteryStrings.current
        var parts: [IconPart] = []
        // The pinned devices on the left, the Mac's battery on the right.
        let pins = Menu.pinnedNames(stored: defaults.string(forKey: DefaultsKey.forkPinnedBatteryDevices) ?? "",
                                    legacy: defaults.string(forKey: DefaultsKey.forkPinnedBatteryDevice) ?? "")
        for name in pins {
            let device = Logic.pinned(in: model.devices, pinned: name)
            let percent = device?.isNearby == true ? device?.percent : nil
            parts.append(.device(symbol: (device?.kind ?? Logic.kind(model: nil, name: name)).symbol,
                                 percent: percent, label: percent.map(text.percent) ?? "—",
                                 tint: percent.map { Menu.iconTint(percent: $0, charging: device?.isCharging ?? false) } ?? .normal))
        }
        if let mac = model.mac {
            let texts = Menu.iconTexts(percent: mac.percent, minutesLeft: mac.charging ? mac.minutesToFull : mac.minutesToEmpty,
                                       mode: style.text, showNumber: style.number)
            // Plugged in reads as charging: a bolt on the left, the battery green.
            let plugged = mac.onPower || mac.charging
            parts.append(.battery(percent: mac.percent, plugged: plugged, inside: texts.inside, beside: texts.beside,
                                  tint: Menu.iconTint(percent: mac.percent, charging: plugged, lowPower: model.lowPower)))
        }
        if parts.isEmpty { parts.append(.plug) }
        button.image = Self.iconImage(parts, style: style)
        button.toolTip = text.statusItem
    }

    private typealias Menu = ForkBatteryMenuLogic

    private struct IconStyle {
        let colored: Bool
        let number: Bool
        let text: Menu.IconText
        let large: Bool
    }

    private enum IconPart {
        case battery(percent: Int, plugged: Bool, inside: String?, beside: String?, tint: Menu.IconTint)
        case device(symbol: String, percent: Int?, label: String, tint: Menu.IconTint)
        case plug
    }

    /// The menu bar label as one image, as in Arthur's reference capture:
    /// each pinned device as its outline, its level, and a thin bar under
    /// both; then the Mac's battery, an outline with the level filled in its
    /// colour and the number inside. Colours resolve when drawn, so light
    /// and dark menu bars both read; without colours it is a template image
    /// tinted by the menu bar.
    private static func iconImage(_ parts: [IconPart], style: IconStyle) -> NSImage {
        // 20 pt tall: room for a device's icon and level to sit clear of its
        // bar (Arthur, 26/11/2026); everything else stays centred.
        let height: CGFloat = 20
        let gap: CGFloat = 8
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: style.large ? 13 : 12, weight: .regular)
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: style.large ? 13 : 12, weight: .medium)
        func symbol(_ name: String) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig)
        }
        let boltWidth: CGFloat = style.large ? 8 : 7
        func textWidth(_ string: String) -> CGFloat {
            NSAttributedString(string: string, attributes: [.font: labelFont]).size().width
        }
        func width(_ part: IconPart) -> CGFloat {
            switch part {
            case let .battery(_, plugged, inside, beside, _):
                var total = Menu.iconBodyWidth(for: inside, large: style.large) + 3
                if plugged { total += boltWidth + 2 }
                if let beside { total += textWidth(beside) + 4 }
                return total
            case let .device(name, _, label, _):
                return (symbol(name)?.size.width ?? 10) + 4 + textWidth(label)
            case .plug:
                return symbol("powerplug")?.size.width ?? 14
            }
        }
        let total = parts.map(width).reduce(0, +) + gap * CGFloat(max(0, parts.count - 1))
        let image = NSImage(size: NSSize(width: max(1, ceil(total)), height: height), flipped: false) { _ in
            let label: NSColor = style.colored ? .labelColor : .black
            func color(_ tint: Menu.IconTint) -> NSColor {
                style.colored ? ForkBatteryLevelPalette.nsColor(tint) : label
            }
            var x: CGFloat = 0
            for (index, part) in parts.enumerated() {
                switch part {
                case let .device(name, percent, text, tint):
                    let start = x
                    // Icon and level sit a little high, leaving room for the bar.
                    if let image = symbol(name) {
                        let size = image.size
                        let rect = NSRect(x: x, y: (height - size.height) / 2 + 2, width: size.width, height: size.height)
                        image.draw(in: rect)
                        if style.colored {
                            label.set()
                            rect.fill(using: .sourceAtop)
                        }
                        x += size.width + 4
                    }
                    let string = NSAttributedString(string: text, attributes: [.font: labelFont, .foregroundColor: label])
                    let size = string.size()
                    string.draw(at: NSPoint(x: x, y: (height - size.height) / 2 + 2))
                    x += size.width
                    // The bar under the icon and the level, filled to it.
                    let track = NSRect(x: start, y: 0.5, width: x - start, height: 2)
                    label.withAlphaComponent(style.colored ? 0.28 : 0.35).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
                    if let percent {
                        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * Menu.iconFill(percent: percent), height: track.height)
                        (tint == .normal ? label : color(tint)).setFill()
                        NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
                    }
                case let .battery(percent, plugged, inside, beside, tint):
                    if plugged, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: style.large ? 11 : 10, weight: .bold)) {
                        let boltHeight: CGFloat = style.large ? 12 : 11
                        let rect = NSRect(x: x, y: (height - boltHeight) / 2, width: boltWidth, height: boltHeight)
                        bolt.draw(in: rect)
                        if style.colored {
                            color(.green).set()
                            rect.fill(using: .sourceAtop)
                        }
                        x += boltWidth + 2
                    }
                    if let beside {
                        let string = NSAttributedString(string: beside, attributes: [.font: labelFont, .foregroundColor: label])
                        let size = string.size()
                        string.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
                        x += size.width + 4
                    }
                    let bodyWidth = Menu.iconBodyWidth(for: inside, large: style.large)
                    drawBattery(at: x, height: height, bodyWidth: bodyWidth, bodyHeight: Menu.iconBodyHeight(large: style.large),
                                percent: percent, text: inside, tint: tint, fill: color(tint), label: label,
                                colored: style.colored, fontSize: Menu.iconNumberSize(large: style.large))
                    x += bodyWidth + 3
                case .plug:
                    if let image = symbol("powerplug") {
                        image.draw(in: NSRect(x: x, y: (height - image.size.height) / 2, width: image.size.width, height: image.size.height))
                        x += image.size.width
                    }
                }
                if index < parts.count - 1 { x += gap }
            }
            return true
        }
        image.isTemplate = !style.colored
        return image
    }

    /// The Mac's battery, as in Arthur's reference of 26/11/2026: a thin
    /// outline in the state's colour, a little air, then the inside tinted
    /// the same colour almost clear, the level filled solid over it, the
    /// number in white. The usual (muted) state draws its outline like the
    /// menu bar's text. Without colours: a plain outline and the number.
    private static func drawBattery(at x: CGFloat, height: CGFloat, bodyWidth: CGFloat, bodyHeight: CGFloat, percent: Int,
                                    text: String?, tint: Menu.IconTint, fill: NSColor, label: NSColor, colored: Bool,
                                    fontSize: CGFloat) {
        let body = NSRect(x: x, y: (height - bodyHeight) / 2, width: bodyWidth, height: bodyHeight)
        let radius = bodyHeight * 0.36
        let usual = tint == .normal
        let edge: NSColor = !colored ? label.withAlphaComponent(0.6) : usual ? label.withAlphaComponent(0.8) : fill.withAlphaComponent(0.8)
        let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.6, dy: 0.6), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1.2
        edge.setStroke()
        outline.stroke()
        let nub = NSRect(x: body.maxX + 0.8, y: body.midY - bodyHeight * 0.18, width: 1.6, height: bodyHeight * 0.36)
        edge.setFill()
        NSBezierPath(roundedRect: nub, xRadius: 0.8, yRadius: 0.8).fill()

        let inner = body.insetBy(dx: 2.4, dy: 2.4)
        let innerRadius = max(1, radius - 2)
        let fillWidth = inner.width * Menu.iconFill(percent: percent)
        if colored {
            // The whole inside, faintly tinted; the level solid over it.
            (usual ? label.withAlphaComponent(0.16) : fill.withAlphaComponent(0.26)).setFill()
            NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius).fill()
            if fillWidth > 0 {
                fill.setFill()
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height),
                             xRadius: innerRadius, yRadius: innerRadius).fill()
            }
        } else if text == nil, fillWidth > 0 {
            label.setFill()
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height),
                         xRadius: innerRadius, yRadius: innerRadius).fill()
        }
        if let text {
            // Heavy figures, white on a coloured battery with a soft dark
            // edge: readable from a distance.
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: colored && !usual ? NSColor.white : label]
            if colored {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
                shadow.shadowBlurRadius = 1.2
                shadow.shadowOffset = .zero
                attributes[.shadow] = shadow
            }
            let string = NSAttributedString(string: text, attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: inner.midX - size.width / 2, y: inner.midY - size.height / 2))
        }
    }

    // MARK: - The panel

    @objc func togglePanel() {
        guard let button = item?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = self.popover ?? makePopover()
        self.popover = popover
        model.panelOpened()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: ForkBatteryPanelView(model: model))
        // The popover follows the panel's height as « More details » opens.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelClosed()
    }
}

/// What the battery panel shows, kept current while the item is in the menu
/// bar: the Mac's battery (macOS says when it changes) and its last 24 hours,
/// Hublot's own iPhones and iPads, and the accessories macOS reports, read
/// every minute. The details of the Mac's battery are read every 10 s while
/// the panel is open.
final class ForkBatteryPanelModel: ObservableObject {
    typealias Logic = ForkBatteryPanelLogic
    typealias Details = ForkBatteryDetailsLogic

    struct MacBattery: Equatable {
        let percent: Int
        let onPower: Bool
        let charging: Bool
        /// Minutes, while macOS knows.
        let minutesToEmpty: Int?
        let minutesToFull: Int?
    }

    @Published private(set) var mac: MacBattery?
    @Published private(set) var details = PowerReading()
    @Published private(set) var battery = Details.Details()
    @Published private(set) var history: [Details.Sample] = []
    @Published private(set) var temperature: Double?
    /// Low Power Mode: the battery turns orange.
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var devices: [Logic.Device] = []
    @Published private(set) var now = Date()

    private let powerSampler = PowerSampler(smc: nil)
    private let accessorySampler = PeripheralBatterySampler()
    private var accessories: [PeripheralBatteryDevice] = []
    private var accessoryTimer: Timer?
    private var panelTimer: Timer?
    private var historyTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        accessorySampler.onBluetoothRefresh = { [weak self] in
            DispatchQueue.main.async { self?.readAccessories() }
        }
    }

    func start() {
        history = Self.loadHistory()
        refreshMac()
        historyTimer = Timer.scheduledTimer(withTimeInterval: Details.sampleSpacing, repeats: true) { [weak self] _ in
            self?.refreshMac()
        }
        historyTimer?.tolerance = 30
        ForkBluetoothDevices.shared.$devices.sink { [weak self] _ in
            DispatchQueue.main.async { self?.mergeDevices() }
        }.store(in: &cancellables)
        accessorySampler.setEnabled(true)
        ForkAppEnergy.shared.setActive(true)
        readAccessories()
        accessoryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.readAccessories() }
        accessoryTimer?.tolerance = 10
    }

    func stop() {
        accessoryTimer?.invalidate()
        accessoryTimer = nil
        historyTimer?.invalidate()
        historyTimer = nil
        panelClosed()
        accessorySampler.setEnabled(false)
        ForkAppEnergy.shared.setActive(false)
        accessories = []
        cancellables.removeAll()
        mergeDevices()
    }

    func panelOpened() {
        ForkAppEnergy.shared.setLive(true)
        refreshMac()
        readDetails()
        readAccessories()
        panelTimer?.invalidate()
        panelTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshMac()
            self.readDetails()
        }
    }

    /// The battery's temperature sensors, opened once while the panel shows.
    private var smc: SMCClient?
    private var temperatureKeys: [SMCClient.Key]?

    private func readTemperature() -> Double? {
        if smc == nil { smc = SMCClient() }
        guard let smc else { return nil }
        if temperatureKeys == nil { temperatureKeys = ["TB0T", "TB1T", "TB2T"].compactMap(smc.key(named:)) }
        return Details.batteryTemperature((temperatureKeys ?? []).compactMap(smc.readValue))
    }

    private func readDetails() {
        details = powerSampler.sample()
        let next = Self.readBattery()
        if next != battery { battery = next }
        let celsius = readTemperature()
        if celsius != temperature { temperature = celsius }
        now = Date()
    }

    func panelClosed() {
        ForkAppEnergy.shared.setLive(false)
        panelTimer?.invalidate()
        panelTimer = nil
        smc = nil
        temperatureKeys = nil
    }

    func refreshMac() {
        let next = Self.readMac()
        if next != mac { mac = next }
        let saving = ProcessInfo.processInfo.isLowPowerModeEnabled
        if saving != lowPower { lowPower = saving }
        now = Date()
        if let next { record(next) }
    }

    /// The level for the 24-hour chart, kept on this Mac only.
    private func record(_ mac: MacBattery) {
        let recorded = Details.recording(Details.Sample(time: now, percent: mac.percent, charging: mac.charging, onPower: mac.onPower), in: history)
        guard recorded != history else { return }
        history = recorded
        if let data = try? JSONEncoder().encode(recorded) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.forkBatteryHistory)
        }
    }

    private static func loadHistory() -> [Details.Sample] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.forkBatteryHistory),
              let history = try? JSONDecoder().decode([Details.Sample].self, from: data) else { return [] }
        return history
    }

    /// The `AppleSmartBattery` registry entry: voltage, current, cycles, charger.
    static func readBattery() -> Details.Details {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return Details.Details() }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return Details.Details() }
        return Details.details(from: properties)
    }

    private func readAccessories() {
        accessories = accessorySampler.sample(now: ProcessInfo.processInfo.systemUptime).devices
        mergeDevices()
    }

    private func mergeDevices() {
        let next = Logic.panelDevices(own: ForkBluetoothDevices.shared.devices, accessories: accessories)
        if next != devices { devices = next }
        now = Date()
    }

    /// The internal battery as macOS's power sources describe it; nil on a
    /// Mac without one.
    static func readMac() -> MacBattery? {
        guard PowerSampler.hasInternalBattery,
              let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            func minutes(_ key: String) -> Int? {
                guard let value = description[key] as? Int, value > 0 else { return nil }
                return value
            }
            return MacBattery(percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                              onPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                              charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                              minutesToEmpty: minutes(kIOPSTimeToEmptyKey),
                              minutesToFull: minutes(kIOPSTimeToFullChargeKey))
        }
        return nil
    }
}
