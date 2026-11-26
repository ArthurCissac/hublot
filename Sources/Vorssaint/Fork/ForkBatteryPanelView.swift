// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Lot 8, the panel the battery item opens, laid out like Juicy's on a dark
/// ground: the level large in its colour with the time left and a graduated
/// bar, then cards the user can fold and drag into another order (battery
/// information: health, temperature, power and electrical, capacity; the
/// connected devices, ranked by level; the level's history; the power flow
/// between charger, battery and Mac), and the menu rows at the bottom.
/// Springs throughout; macOS's « Reduce motion » keeps everything still.
struct ForkBatteryPanelView: View {
    typealias Logic = ForkBatteryPanelLogic
    typealias Details = ForkBatteryDetailsLogic
    typealias Menu = ForkBatteryMenuLogic

    @ObservedObject var model: ForkBatteryPanelModel
    @ObservedObject private var bluetooth = ForkBluetoothDevices.shared
    @StateObject private var access = ForkBluetoothAccess()
    @AppStorage(DefaultsKey.forkBatteryPanelOrder) private var storedOrder = ""
    @AppStorage(DefaultsKey.forkBatteryPanelCollapsed) private var storedCollapsed = ""
    @AppStorage(DefaultsKey.forkBatteryChartHours) private var chartHours = 12
    @AppStorage(DefaultsKey.forkPinnedBatteryDevices) private var storedPins = ""
    @AppStorage(DefaultsKey.forkPinnedBatteryDevice) private var legacyPin = ""
    @AppStorage(DefaultsKey.forkAppEnergyPeriod) private var energyPeriod = ForkAppEnergyLogic.Period.live.rawValue
    @ObservedObject private var energy = ForkAppEnergy.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var dragging: Menu.Card?
    @FocusState private var focused: Bool
    @State private var contentHeight: CGFloat = 480

    var body: some View {
        let text = ForkBatteryStrings.current
        let order = Menu.cardOrder(stored: storedOrder)
        // Taller than the screen, the panel scrolls instead of being cut off.
        let maxHeight = max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 48)
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 10) {
            if let mac = model.mac {
                reveal(0) { ForkBatteryTopCard(mac: mac, lowPower: model.lowPower, battery: model.battery, text: text, live: appeared) }
            }
            ForEach(Array(order.enumerated()), id: \.element) { index, card in
                reveal(index + 1) { self.card(card, text: text) }
                    .onDrag {
                        dragging = card
                        return NSItemProvider(object: card.rawValue as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: ForkCardDrop(card: card, dragging: $dragging, order: order) { next in
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                            storedOrder = Menu.encodeOrder(next)
                        }
                    })
            }
            reveal(order.count + 1) { menuRows(text) }
        }
        .padding(12)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ForkPanelHeightKey.self, value: geometry.size.height)
        })
        }
        .scrollIndicators(.automatic)
        .frame(width: 348, height: min(contentHeight, maxHeight))
        .onPreferenceChange(ForkPanelHeightKey.self) { contentHeight = $0 }
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        // As in Juicy: I opens the battery information, D the devices.
        .onKeyPress(characters: CharacterSet(charactersIn: "iIdD")) { press in
            show(press.characters.lowercased() == "i" ? .info : .devices)
            return .handled
        }
        .onAppear {
            access.start()
            appeared = true
            focused = true
        }
        .onDisappear {
            access.stop()
            appeared = false
        }
    }

    /// One section, coming in after the ones above it.
    private func reveal<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82).delay(0.04 * Double(index)),
                       value: appeared)
    }

    // MARK: - Cards

    @ViewBuilder
    private func card(_ card: Menu.Card, text: ForkBatteryStrings) -> some View {
        switch card {
        case .info:
            ForkPanelCard(title: text.infoCard, symbol: "info.circle.fill", tint: .blue, folded: isFolded(.info), toggle: { fold(.info) }) {
                ForkBatteryInfoSections(model: model, text: text, live: appeared)
            }
        case .devices:
            ForkPanelCard(title: text.connectedDevices, symbol: "macbook.and.iphone", tint: .secondary, folded: isFolded(.devices),
                          toggle: { fold(.devices) }, accessory: { searchButton(text) }) {
                devices(text)
            }
        case .apps:
            ForkPanelCard(title: text.appsCard, symbol: "flame.fill", tint: .orange, folded: isFolded(.apps),
                          toggle: { fold(.apps) }) {
                // Under the title, so the title keeps to one line.
                periodPicker(text)
                ForkAppEnergyList(energy: energy, period: ForkAppEnergyLogic.Period(rawValue: energyPeriod) ?? .live,
                                  now: model.now, text: text)
            }
        case .history:
            ForkPanelCard(title: text.historyTitle, symbol: "chart.xyaxis.line", tint: .green, folded: isFolded(.history),
                          toggle: { fold(.history) }, accessory: { hoursPicker(text) }) {
                history(text)
            }
        case .flow:
            ForkPanelCard(title: text.flowTitle, symbol: "bolt.horizontal.circle.fill", tint: .orange, folded: isFolded(.flow),
                          toggle: { fold(.flow) }) {
                ForkPowerFlowView(flow: Details.flow(model.battery, onPower: model.mac?.onPower ?? false),
                                  hasBattery: model.mac != nil, text: text, live: appeared)
            }
        }
    }

    private func periodPicker(_ text: ForkBatteryStrings) -> some View {
        Picker("", selection: $energyPeriod) {
            ForEach(ForkAppEnergyLogic.Period.allCases, id: \.self) { Text(text.periodName($0)).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    /// Opens one of the battery information and the devices, folding the other.
    private func show(_ card: Menu.Card) {
        var folded = Set(storedCollapsed.split(separator: ",").map(String.init))
        folded.remove(card.rawValue)
        folded.insert(card == .info ? Menu.Card.devices.rawValue : Menu.Card.info.rawValue)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
            storedCollapsed = Menu.Card.allCases.map(\.rawValue).filter(folded.contains).joined(separator: ",")
        }
    }

    private func isFolded(_ card: Menu.Card) -> Bool {
        storedCollapsed.split(separator: ",").contains(Substring(card.rawValue))
    }

    private func fold(_ card: Menu.Card) {
        var folded = Set(storedCollapsed.split(separator: ",").map(String.init))
        if folded.contains(card.rawValue) { folded.remove(card.rawValue) } else { folded.insert(card.rawValue) }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
            storedCollapsed = Menu.Card.allCases.map(\.rawValue).filter(folded.contains).joined(separator: ",")
        }
    }

    // MARK: - Devices

    private var pins: [String] { Menu.pinnedNames(stored: storedPins, legacy: legacyPin) }

    private func togglePin(_ name: String) {
        let next = Menu.togglingPin(name, in: pins)
        storedPins = Menu.encodePinned(next)
        legacyPin = next.first ?? ""
    }

    private func searchButton(_ text: ForkBatteryStrings) -> some View {
        Button { bluetooth.search() } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .symbolEffect(.variableColor.iterative.reversing, isActive: bluetooth.isSearching && !reduceMotion)
        }
        .buttonStyle(.borderless)
        .disabled(bluetooth.isSearching || access.status != .ready)
        .help(bluetooth.isSearching ? text.searching : text.search)
    }

    @ViewBuilder
    private func devices(_ text: ForkBatteryStrings) -> some View {
        accessRow(text)
        let ranked = Logic.ranked(model.devices)
        if ranked.isEmpty {
            if bluetooth.isSearching {
                VStack(spacing: 8) {
                    ForkSkeletonRow()
                    ForkSkeletonRow()
                }
            } else {
                Text(text.noDevices)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { Divider().opacity(0.5) }
                    ForkDeviceRow(device: device, now: model.now, isPinned: pins.contains(device.name), text: text,
                                  live: appeared, delay: 0.2 + 0.05 * Double(index)) { togglePin(device.name) }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: ranked.map(\.id))
        }
    }

    @ViewBuilder
    private func accessRow(_ text: ForkBatteryStrings) -> some View {
        switch access.status {
        case .askNeeded:
            HStack(alignment: .firstTextBaseline) {
                Text(text.bluetoothAsk).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button(text.bluetoothAllow) { access.ask() }.controlSize(.small)
            }
        case .refused:
            HStack(alignment: .firstTextBaseline) {
                Text(text.bluetoothRefused).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button(text.openSettings) { access.openSettings() }.controlSize(.small)
            }
        case .off:
            Label {
                Text(text.bluetoothOff).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }
        case .ready:
            EmptyView()
        }
    }

    // MARK: - History

    private func hoursPicker(_ text: ForkBatteryStrings) -> some View {
        Picker("", selection: $chartHours) {
            ForEach(Menu.chartHours, id: \.self) { Text(text.hoursName($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(width: 110)
    }

    @ViewBuilder
    private func history(_ text: ForkBatteryStrings) -> some View {
        let samples = Details.visible(model.history, hours: chartHours, now: model.now)
        if samples.count < 2 {
            Text(text.chartEmpty)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 70)
        } else {
            ForkBatteryHistoryChart(history: samples, hours: chartHours, now: model.now, live: appeared)
                .frame(height: 90)
        }
    }

    // MARK: - Menu rows

    private func menuRows(_ text: ForkBatteryStrings) -> some View {
        VStack(spacing: 0) {
            ForkMenuRow(symbol: "gearshape.fill", title: text.settingsRow) {
                ForkBatteryStatusItem.shared.closePanel()
                SettingsRouter.shared.page = .monitor
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            }
            Divider().opacity(0.5)
            ForkMenuRow(symbol: "battery.100percent", title: text.macBatterySettings) {
                ForkBatteryStatusItem.shared.closePanel()
                if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider().opacity(0.5)
            ForkMenuRow(symbol: "eye.slash", title: text.hideItem, chevron: false) {
                ForkBatteryStatusItem.shared.closePanel()
                UserDefaults.standard.set(false, forKey: DefaultsKey.forkBatteryStatusItem)
            }
        }
        .background(ForkPanelCardBackground())
    }
}

/// The panel's natural height, so it can scroll once taller than the screen.
private struct ForkPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A card dragged over another takes its place.
private struct ForkCardDrop: DropDelegate {
    let card: ForkBatteryMenuLogic.Card
    @Binding var dragging: ForkBatteryMenuLogic.Card?
    let order: [ForkBatteryMenuLogic.Card]
    let reorder: ([ForkBatteryMenuLogic.Card]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != card else { return }
        reorder(ForkBatteryMenuLogic.moving(dragging, onto: card, in: order))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Building blocks

/// The cards' ground: a little lighter than the panel, a fine edge.
struct ForkPanelCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

/// A card with a header that folds it, and room for a control on the right.
private struct ForkPanelCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let folded: Bool
    let toggle: () -> Void
    let accessory: Accessory
    let content: Content

    init(title: String, symbol: String, tint: Color, folded: Bool, toggle: @escaping () -> Void,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.folded = folded
        self.toggle = toggle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if !folded { accessory }
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            if !folded {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(ForkPanelCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A menu row like the ones at the bottom of Juicy's panel.
private struct ForkMenuRow: View {
    let symbol: String
    let title: String
    var chevron = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hovering ? 0.07 : 0)).padding(3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The top of the panel: the level large in its colour, the state, the time
/// left, and a graduated bar that fills as the panel opens.
private struct ForkBatteryTopCard: View {
    typealias Menu = ForkBatteryMenuLogic

    let mac: ForkBatteryPanelModel.MacBattery
    let lowPower: Bool
    let battery: ForkBatteryDetailsLogic.Details
    let text: ForkBatteryStrings
    let live: Bool
    @State private var shown: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = ForkBatteryLevelPalette.color(Menu.iconTint(percent: mac.percent, charging: mac.charging, lowPower: lowPower))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(mac.percent)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(mac.percent)))
                            .animation(.snappy, value: mac.percent)
                        Text("%").font(.system(size: 20, weight: .semibold, design: .rounded)).opacity(0.85)
                    }
                    .foregroundStyle(tint)
                    HStack(spacing: 7) {
                        ForkMiniBattery(percent: mac.percent, tint: tint)
                        Text(state).font(.system(size: 13, weight: .medium))
                        if mac.charging {
                            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(tint)
                                .symbolEffect(.pulse, isActive: !reduceMotion)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(mac.charging ? text.timeToFullCaps : text.timeLeftCaps)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(timeText ?? "—")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.top, 6)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(6, geometry.size.width * shown))
                        .overlay {
                            if mac.charging && !reduceMotion { ForkChargeSweep() }
                        }
                        .clipShape(Capsule())
                    ForEach([0.25, 0.5, 0.75], id: \.self) { mark in
                        Rectangle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 1.5, height: 6)
                            .offset(x: geometry.size.width * mark)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(ForkPanelCardBackground())
        .onAppear { fill(animated: live) }
        .onChange(of: live) { _, isLive in
            if isLive { fill(animated: true) } else { shown = 0 }
        }
        .onChange(of: mac.percent) { _, _ in fill(animated: true) }
    }

    private var state: String {
        if mac.charging { return text.chargingShort }
        if mac.onPower { return text.onPowerNotCharging }
        return text.onBatteryShort
    }

    /// macOS's time when it has one, else an estimate: until full while
    /// charging, until empty otherwise (plugged in but paused included).
    private var timeText: String? {
        let minutes = ForkBatteryDetailsLogic.estimatedMinutes(charging: mac.charging, onPower: mac.onPower,
                                                               minutesToEmpty: mac.minutesToEmpty,
                                                               minutesToFull: mac.minutesToFull, details: battery)
        return ForkBatteryPanelLogic.duration(minutes.map { TimeInterval($0 * 60) }).map(text.duration)
    }

    private func fill(animated: Bool) {
        let target = ForkBatteryMenuLogic.iconFill(percent: mac.percent)
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { shown = target }
        } else {
            shown = target
        }
    }
}

/// Red, orange or green for the Mac's level and the menu bar icon.
enum ForkBatteryLevelPalette {
    /// In the panel, the usual state reads green, as in Juicy.
    static func color(_ tint: ForkBatteryMenuLogic.IconTint) -> Color {
        Color(nsColor: tint == .normal ? .systemGreen : nsColor(tint))
    }

    /// In the menu bar, the usual state is a muted green-grey (Arthur's
    /// reference capture), the others macOS's own colours.
    static func nsColor(_ tint: ForkBatteryMenuLogic.IconTint) -> NSColor {
        switch tint {
        case .normal: return NSColor(calibratedRed: 0.34, green: 0.54, blue: 0.36, alpha: 0.75)
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .green: return .systemGreen
        }
    }
}

/// A small battery outline filled to the level.
struct ForkMiniBattery: View {
    let percent: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(tint.opacity(0.9), lineWidth: 1.2)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: max(2, 15 * CGFloat(max(0, min(100, percent))) / 100), height: 6)
                    .padding(.leading, 2)
            }
            .frame(width: 20, height: 10)
            RoundedRectangle(cornerRadius: 0.5).fill(tint.opacity(0.9)).frame(width: 1.5, height: 4)
        }
    }
}

/// The battery information: health, temperature, power and electrical,
/// capacity, each a section with its figures in mono type.
private struct ForkBatteryInfoSections: View {
    typealias Details = ForkBatteryDetailsLogic

    @ObservedObject var model: ForkBatteryPanelModel
    let text: ForkBatteryStrings
    let live: Bool

    var body: some View {
        let battery = model.battery
        if let health = battery.healthPercent ?? model.details.healthPercent {
            healthSection(health)
            Divider().opacity(0.5)
        }
        if let celsius = model.temperature {
            temperatureSection(celsius)
            Divider().opacity(0.5)
        }
        powerSection(battery)
        if battery.remainingCapacity != nil || battery.fullCapacity != nil || battery.designCapacity != nil {
            Divider().opacity(0.5)
            capacitySection(battery)
        }
    }

    private func header(_ title: String, symbol: String, tint: Color, help: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Image(systemName: "info.circle").foregroundStyle(.tertiary).help(help)
        }
    }

    private func healthSection(_ percent: Double) -> some View {
        let health = Details.health(percent)
        let tint: Color = health == .good ? .green : health == .fair ? .yellow : .red
        let symbol = health == .good ? "checkmark.circle.fill" : health == .fair ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"
        return VStack(alignment: .leading, spacing: 8) {
            header(text.healthTitle, symbol: symbol, tint: tint, help: text.healthHelp)
            HStack(alignment: .firstTextBaseline) {
                Text(text.percent(Int(percent.rounded())))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(text.healthName(health)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                Spacer()
                if let cycles = model.battery.cycles {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(model.battery.designCycles.map { "\(cycles)/\($0)" } ?? "\(cycles)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text(text.cyclesCaption).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            ForkLevelBar(fraction: percent / 100, tint: tint, live: live)
            if health != .good {
                Text(health == .fair ? text.healthAdvice : text.healthAdvicePoor)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func temperatureSection(_ celsius: Double) -> some View {
        let warmth = Details.warmth(celsius)
        let tint: Color = warmth == .normal ? .green : warmth == .cold ? .cyan : warmth == .warm ? .orange : .red
        let symbol = warmth == .normal ? "checkmark.circle.fill" : warmth == .cold ? "snowflake" : "exclamationmark.triangle.fill"
        let locale = Locale(identifier: L10n.shared.language == .fr ? "fr_FR" : "en_US")
        return VStack(alignment: .leading, spacing: 8) {
            header(text.temperatureTitle, symbol: symbol, tint: tint, help: text.temperatureHelp)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium").foregroundStyle(tint)
                        Text(Details.number(celsius, unit: "°C", locale: locale, space: "\u{202F}"))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .contentTransition(.numericText(value: celsius))
                    }
                    Text(Details.number(Details.fahrenheit(celsius), unit: "°F", locale: locale, space: "\u{202F}"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label(text.warmthName(warmth), systemImage: warmth == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(text.warmthAdvice(warmth)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func powerSection(_ battery: Details.Details) -> some View {
        let watts = battery.batteryPower ?? battery.watts
        let draining = (watts ?? 0) < -0.2
        let charging = (watts ?? 0) > 0.2
        return VStack(alignment: .leading, spacing: 8) {
            header(text.powerTitle, symbol: "bolt.circle.fill", tint: .orange, help: text.powerHelp)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    figure(text.usage, (battery.systemLoad ?? watts.map(abs)).map { text.watts($0).replacingOccurrences(of: "+", with: "") })
                    figure(text.voltage, battery.voltage.map(text.volts), trailing: true)
                }
                GridRow {
                    HStack(spacing: 4) {
                        figure(text.current, battery.amperage.map { text.milliamps(abs($0) * 1000) })
                        if draining || charging {
                            Image(systemName: draining ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundStyle(draining ? .orange : .green)
                                .padding(.top, 12)
                        }
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(draining ? text.discharging : charging ? text.chargingShort : text.idle, systemImage: "circle.fill")
                            .labelStyle(ForkDotLabelStyle())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(draining ? .orange : charging ? .green : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func capacitySection(_ battery: Details.Details) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(text.capacityTitle, symbol: "battery.100percent", tint: .blue, help: text.capacityHelp)
            capacityLine(text.remaining, battery.remainingCapacity, tint: .green)
            capacityLine(text.currentFull, battery.fullCapacity, tint: .blue)
            capacityLine(text.designCapacity, battery.designCapacity, tint: .secondary)
        }
    }

    private func capacityLine(_ title: String, _ value: Int?, tint: Color) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value.map(text.milliampHours) ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private func figure(_ title: String, _ value: String?, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

private struct ForkDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

/// A thin bar that fills as the panel opens.
private struct ForkLevelBar: View {
    let fraction: Double
    let tint: Color
    let live: Bool
    @State private var shown: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: geometry.size.width * shown)
            }
        }
        .frame(height: 5)
        .onAppear { fill(animated: live) }
        .onChange(of: live) { _, isLive in
            if isLive { fill(animated: true) } else { shown = 0 }
        }
        .onChange(of: fraction) { _, _ in fill(animated: true) }
    }

    private func fill(animated: Bool) {
        let target = CGFloat(max(0, min(1, fraction)))
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.2)) { shown = target }
        } else {
            shown = target
        }
    }
}

/// A device's row, as in Juicy: its icon and level in the level's colour, a
/// bar under the name, out of range greyed with when it was last read.
private struct ForkDeviceRow: View {
    typealias Logic = ForkBatteryPanelLogic

    let device: Logic.Device
    let now: Date
    let isPinned: Bool
    let text: ForkBatteryStrings
    let live: Bool
    let delay: Double
    let togglePin: () -> Void
    @State private var hovering = false
    @State private var shown: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = color
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(device.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    if hovering || isPinned {
                        Button(action: togglePin) {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 10))
                                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                                .symbolEffect(.bounce, value: isPinned)
                        }
                        .buttonStyle(.plain)
                        .help(isPinned ? text.unpin : text.pin)
                    }
                    Text(device.percent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(tint).frame(width: geometry.size.width * shown)
                    }
                }
                .frame(height: 3.5)
                if !device.isNearby {
                    Text(text.away(device.lastSeen.map { Logic.minutesAgo($0, now: now) }))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(device.isNearby ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onAppear { fill(animated: live) }
        .onChange(of: live) { _, isLive in
            if isLive { fill(animated: true) } else { shown = 0 }
        }
        .onChange(of: device.percent) { _, _ in fill(animated: true) }
    }

    private var color: Color {
        guard device.isNearby, let percent = device.percent else { return .secondary }
        switch Logic.rowTint(percent) {
        case .critical: return .red
        case .low: return .orange
        case .full: return .green
        case .normal: return .primary
        }
    }

    private func fill(animated: Bool) {
        let target = CGFloat(device.percent ?? 0) / 100
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(delay)) { shown = target }
        } else {
            shown = target
        }
    }
}

/// A placeholder row while a search runs, a light passing over it.
private struct ForkSkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: 34)
            .overlay { if !reduceMotion { ForkChargeSweep().opacity(0.4) } }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A band of light crossing what it lies on, again and again.
struct ForkChargeSweep: View {
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { context in
                let period = 1.8
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                let band = max(14, geometry.size.width * 0.35)
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: (geometry.size.width + band) * phase - band)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The level over the chosen hours, charging in green, plugged-in-yet-falling
/// in amber, drawn from left to right as the panel opens.
private struct ForkBatteryHistoryChart: View {
    typealias Details = ForkBatteryDetailsLogic

    let history: [Details.Sample]
    let hours: Int
    let now: Date
    let live: Bool
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let start = now.addingTimeInterval(-Double(hours) * 3600)
        Chart {
            ForEach(Details.chargingSpans(history, now: now), id: \.lowerBound) { span in
                RectangleMark(xStart: .value("Start", max(span.lowerBound, start)), xEnd: .value("End", span.upperBound),
                              yStart: .value("Low", 0), yEnd: .value("High", 100))
                    .foregroundStyle(Color.green.opacity(0.14))
            }
            ForEach(Details.drainingOnPowerSpans(history), id: \.lowerBound) { span in
                RectangleMark(xStart: .value("Start", max(span.lowerBound, start)), xEnd: .value("End", span.upperBound),
                              yStart: .value("Low", 0), yEnd: .value("High", 100))
                    .foregroundStyle(Color.orange.opacity(0.18))
            }
            ForEach(history, id: \.time) { sample in
                AreaMark(x: .value("Time", max(sample.time, start)), y: .value("Level", sample.percent))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.3), Color.green.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", max(sample.time, start)), y: .value("Level", sample.percent))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: start...now)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let level = value.as(Int.self) { Text("\(level)").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: max(1, hours / 4))) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel(format: .dateTime.hour(), centered: false).font(.system(size: 9))
            }
        }
        .mask(alignment: .leading) {
            GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * drawn) }
        }
        .onAppear { draw(animated: live) }
        .onChange(of: live) { _, isLive in
            if isLive { draw(animated: true) } else { drawn = 0 }
        }
        .onChange(of: hours) { _, _ in
            drawn = 0
            draw(animated: true)
        }
        .accessibilityHidden(true)
    }

    private func draw(animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) { drawn = 1 }
        } else {
            drawn = 1
        }
    }
}

/// The power flow: the charger, the battery and the Mac as nodes, light
/// running along each path that carries power, faster when more flows, the
/// watts on it.
private struct ForkPowerFlowView: View {
    typealias Details = ForkBatteryDetailsLogic

    let flow: Details.Flow
    let hasBattery: Bool
    let text: ForkBatteryStrings
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let charger = CGPoint(x: 34, y: 30)
            let mac = CGPoint(x: size.width - 34, y: 30)
            let battery = CGPoint(x: size.width / 2, y: size.height - 26)
            ZStack {
                path(from: charger, to: mac, watts: flow.chargerToMac, tint: .green, labelOffset: CGSize(width: 0, height: -12))
                path(from: charger, to: battery, watts: flow.chargerToBattery, tint: .green, labelOffset: CGSize(width: -22, height: 0))
                path(from: battery, to: mac, watts: flow.batteryToMac, tint: .orange, labelOffset: CGSize(width: 22, height: 0))
                node(text.flowCharger, symbol: "powerplug.fill", active: flow.chargerToMac + flow.chargerToBattery > 0.2).position(charger)
                node(text.flowMac, symbol: "laptopcomputer", active: true,
                     caption: flow.macLoad.map { text.watts($0).replacingOccurrences(of: "+", with: "") }).position(mac)
                if hasBattery {
                    node(text.flowBattery, symbol: "battery.75percent", active: flow.chargerToBattery + flow.batteryToMac > 0.2).position(battery)
                }
            }
        }
        .frame(height: 128)
    }

    @ViewBuilder
    private func path(from start: CGPoint, to end: CGPoint, watts: Double, tint: Color, labelOffset: CGSize) -> some View {
        let active = watts > 0.2
        ZStack {
            Path { $0.move(to: start); $0.addLine(to: end) }
                .stroke(active ? tint.opacity(0.35) : Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: active ? [] : [3, 4]))
            if active && !reduceMotion && live {
                TimelineView(.animation) { context in
                    let period = max(0.6, 2.4 - min(1.8, watts / 40))
                    let base = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    ForEach(0..<3, id: \.self) { dot in
                        let t = (base + Double(dot) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .shadow(color: tint.opacity(0.8), radius: 3)
                            .position(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                    }
                }
            }
            if active {
                Text(text.watts(watts).replacingOccurrences(of: "+", with: ""))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .position(x: (start.x + end.x) / 2 + labelOffset.width, y: (start.y + end.y) / 2 + labelOffset.height)
            }
        }
    }

    private func node(_ title: String, symbol: String, active: Bool, caption: String? = nil) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(active ? 0.12 : 0.05)))
                .overlay(Circle().strokeBorder(Color.white.opacity(active ? 0.25 : 0.08)))
            Text(caption ?? title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .opacity(active ? 1 : 0.6)
    }
}

/// The apps that used the most energy over the chosen period: icon, name,
/// watts now or watt-hours, their share, and a sparkline of the hours or days.
private struct ForkAppEnergyList: View {
    typealias Logic = ForkAppEnergyLogic

    @ObservedObject var energy: ForkAppEnergy
    let period: Logic.Period
    let now: Date
    let text: ForkBatteryStrings

    var body: some View {
        let rows = Logic.rows(period: period, live: energy.live, store: energy.store, now: now)
        if rows.isEmpty {
            Text(text.appsEmpty)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().opacity(0.5) }
                    line(row)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: rows.map(\.bundle))
        }
    }

    private func line(_ row: Logic.Row) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: energy.icon(for: row.bundle))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Logic.name(bundle: row.bundle)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(period == .live ? text.watts(row.value).replacingOccurrences(of: "+", with: "") : text.wattHours(row.value))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                }
                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(Color.orange.opacity(0.85)).frame(width: geometry.size.width * row.share)
                        }
                    }
                    .frame(height: 3.5)
                    if !row.spark.isEmpty {
                        ForkSparkline(points: Logic.sparkPoints(row.spark)).frame(width: 64, height: 14)
                    }
                    Text("\(Int((row.share * 100).rounded()))\u{202F}%")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// A small line of values from 0 to 1, oldest on the left.
private struct ForkSparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard points.count > 1 else { return }
                let step = geometry.size.width / CGFloat(points.count - 1)
                for (index, value) in points.enumerated() {
                    let point = CGPoint(x: CGFloat(index) * step, y: geometry.size.height * (1 - CGFloat(value)))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
    }
}
