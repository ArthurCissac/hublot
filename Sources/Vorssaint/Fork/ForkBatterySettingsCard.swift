// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 8's settings, on the Monitor page: the battery item and the device
/// pinned beside it, with what Bluetooth allows; the battery alerts, their
/// halo and their sounds; the charger sounds. Each sound can be chosen and
/// heard, each alert tried.
struct ForkBatterySettingsCard: View {
    typealias Logic = ForkBatteryLogic
    typealias Panel = ForkBatteryPanelLogic

    @AppStorage(DefaultsKey.forkBatteryStatusItem) private var statusItem = true
    @AppStorage(DefaultsKey.forkBatteryAlerts) private var alerts = true
    @AppStorage(DefaultsKey.forkBatteryHaloSize) private var haloSize = Panel.HaloSize.large.rawValue
    @AppStorage(DefaultsKey.forkBatteryPillSize) private var pillSize = ForkBatteryAlertRules.PillSize.standard.rawValue
    @AppStorage(DefaultsKey.forkPowerSounds) private var powerSounds = true
    @AppStorage(DefaultsKey.forkPowerAlertPill) private var powerPill = true
    @AppStorage(DefaultsKey.forkPowerSoundPlugged) private var pluggedSound = Panel.SoundEvent.plugged.defaultChoice.stored
    @AppStorage(DefaultsKey.forkPowerSoundUnplugged) private var unpluggedSound = Panel.SoundEvent.unplugged.defaultChoice.stored
    @AppStorage(DefaultsKey.forkPinnedBatteryDevice) private var pinned = ""
    @AppStorage(DefaultsKey.forkPinnedBatteryDevices) private var storedPins = ""
    @AppStorage(DefaultsKey.forkBatteryIconNumber) private var iconNumber = true
    @AppStorage(DefaultsKey.forkBatteryIconColors) private var iconColors = true
    @AppStorage(DefaultsKey.forkBatteryIconText) private var iconText = ForkBatteryMenuLogic.IconText.percent.rawValue
    @AppStorage(DefaultsKey.forkBatteryIconLarge) private var iconLarge = false
    @AppStorage(DefaultsKey.forkTightMenuBarIcon) private var tightIcon = true
    @AppStorage(DefaultsKey.forkBatteryShortcutEnabled) private var shortcutOn = true
    @AppStorage(DefaultsKey.forkBatteryShortcut) private var storedShortcut = ""
    @AppStorage(DefaultsKey.forkAppEnergyAlerts) private var appAlerts = true
    @AppStorage(DefaultsKey.forkAppEnergyThreshold) private var appThreshold = 6.0
    @ObservedObject private var panel = ForkBatteryStatusItem.shared.model
    @StateObject private var bluetooth = ForkBluetoothAccess()

    var body: some View {
        if AppFeature.monitorPower.isAvailable {
            let text = ForkBatteryStrings.current
            VStack(alignment: .leading, spacing: 10) {
                Label(text.title, systemImage: "battery.75percent").font(.headline)
                Toggle(text.statusItem, isOn: $statusItem)
                caption(text.statusItemCaption)
                if statusItem {
                    iconSettings(text)
                    pinnedList(text)
                    bluetoothRow(text)
                    shortcutRow(text)
                    appEnergyRows(text)
                }
                caption(text.pinnedCaption)
                if PowerSampler.hasInternalBattery {
                    Divider()
                    Toggle(text.alerts, isOn: $alerts)
                    caption(text.alertsCaption)
                    if alerts {
                        ForkBatteryAlertsEditor(text: text)
                        HStack {
                            Text(text.pillSize).font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $pillSize) {
                                ForEach(ForkBatteryAlertRules.PillSize.allCases, id: \.self) { size in
                                    Text(text.pillSizeName(size)).tag(size.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        HStack {
                            Text(text.haloSize).font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $haloSize) {
                                ForEach(Panel.HaloSize.allCases, id: \.self) { size in
                                    Text(text.haloSizeName(size)).tag(size.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    Divider()
                    Label(text.powerAlerts, systemImage: "powerplug.fill").font(.subheadline.weight(.semibold))
                    Toggle(text.powerPill, isOn: $powerPill)
                    Toggle(text.powerSounds, isOn: $powerSounds)
                    HStack {
                        Text(text.plugged).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        ForkSoundPicker(selection: $pluggedSound, fallback: Panel.SoundEvent.plugged.defaultChoice, text: text)
                    }
                    .disabled(!powerSounds)
                    HStack {
                        Text(text.unplugged).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        ForkSoundPicker(selection: $unpluggedSound, fallback: Panel.SoundEvent.unplugged.defaultChoice, text: text)
                    }
                    .disabled(!powerSounds)
                    tryRow(text) {
                        ForEach(Logic.PowerChange.allCases, id: \.self) { change in
                            Button(change == .plugged ? text.plugged : text.unplugged) {
                                ForkBatteryAlerts.shared.preview(change)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
            .onAppear { bluetooth.start() }
            .onDisappear { bluetooth.stop() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                bluetooth.start()
            }
        }
    }

    private typealias MenuLogic = ForkBatteryMenuLogic

    private var pins: [String] { MenuLogic.pinnedNames(stored: storedPins, legacy: pinned) }

    private func savePins(_ names: [String]) {
        storedPins = MenuLogic.encodePinned(names)
        pinned = names.first ?? ""
    }

    private func shortcutRow(_ text: ForkBatteryStrings) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(text.shortcutToggle, isOn: $shortcutOn)
                Spacer()
                ShortcutRecorderButton(
                    shortcut: GlobalShortcut(storageValue: storedShortcut) ?? ForkBatteryStatusItem.defaultShortcut,
                    isEnabled: shortcutOn,
                    waitingTitle: text.shortcutWaiting,
                    invalidAction: {},
                    captureAction: { storedShortcut = $0.storageValue })
                    .frame(width: 120)
            }
            caption(text.shortcutCaption)
        }
    }

    private func appEnergyRows(_ text: ForkBatteryStrings) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(text.appAlerts, isOn: $appAlerts)
            HStack {
                Slider(value: $appThreshold, in: 3...15, step: 1).frame(maxWidth: 180)
                Text(text.appThreshold(Int(appThreshold.rounded()))).font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!appAlerts)
        }
    }

    private func iconSettings(_ text: ForkBatteryStrings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.iconSection).font(.subheadline.weight(.semibold))
            Toggle(text.iconNumber, isOn: $iconNumber)
            Toggle(text.iconColors, isOn: $iconColors)
            Picker(text.iconText, selection: $iconText) {
                ForEach(MenuLogic.IconText.allCases, id: \.self) { Text(text.iconTextName($0)).tag($0.rawValue) }
            }
            .disabled(!iconNumber)
            Toggle(text.iconLarge, isOn: $iconLarge)
            Toggle(text.tightIcon, isOn: $tightIcon)
        }
    }

    /// The pinned devices in their order, to move or remove, and a menu to pin
    /// another among the devices the battery item knows.
    private func pinnedList(_ text: ForkBatteryStrings) -> some View {
        let current = pins
        let others = panel.devices.map(\.name).filter { !current.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(text.pinnedDevices).font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(others, id: \.self) { name in
                        Button(name) { savePins(current + [name]) }
                    }
                } label: {
                    Label(text.pinAdd, systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(others.isEmpty)
            }
            if current.isEmpty {
                caption(text.noPinned)
            } else {
                ForEach(Array(current.enumerated()), id: \.element) { index, name in
                    HStack(spacing: 8) {
                        Image(systemName: ForkBatteryPanelLogic.kind(model: nil, name: name).symbol).frame(width: 18)
                        Text(name).lineLimit(1)
                        Spacer()
                        Button { savePins(MenuLogic.movingPin(current, from: index, by: -1)) } label: { Image(systemName: "arrow.left") }
                            .disabled(index == 0).help(text.moveUp)
                        Button { savePins(MenuLogic.movingPin(current, from: index, by: 1)) } label: { Image(systemName: "arrow.right") }
                            .disabled(index == current.count - 1).help(text.moveDown)
                        Button { savePins(current.filter { $0 != name }) } label: { Image(systemName: "pin.slash") }
                            .help(text.unpin)
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        }
    }

    private func tryRow<Buttons: View>(_ text: ForkBatteryStrings, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 6) {
            Text(text.tryLabel).font(.caption).foregroundStyle(.secondary)
            buttons()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func bluetoothRow(_ text: ForkBatteryStrings) -> some View {
        switch bluetooth.status {
        case .askNeeded:
            HStack(alignment: .firstTextBaseline) {
                caption(text.bluetoothAsk)
                Spacer(minLength: 8)
                Button(text.bluetoothAllow) { bluetooth.ask() }.controlSize(.small)
            }
        case .refused:
            HStack(alignment: .firstTextBaseline) {
                Label { caption(text.bluetoothRefused) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                }
                Spacer(minLength: 8)
                Button(text.openSettings) { bluetooth.openSettings() }.controlSize(.small)
            }
        case .off:
            Label { caption(text.bluetoothOff) } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }
        case .ready:
            EmptyView()
        }
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
