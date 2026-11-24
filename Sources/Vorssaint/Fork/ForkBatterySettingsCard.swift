// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// Lot 8's settings, on the Monitor page: the battery alerts and their halo,
/// the charger sounds, and the device pinned in the menu bar.
struct ForkBatterySettingsCard: View {
    @AppStorage(DefaultsKey.forkBatteryAlerts) private var alerts = true
    @AppStorage(DefaultsKey.forkBatteryHalo) private var halo = true
    @AppStorage(DefaultsKey.forkPowerSounds) private var powerSounds = true
    @AppStorage(DefaultsKey.forkPinnedBatteryDevice) private var pinned = ""
    @AppStorage(DefaultsKey.menuBarPeripheralBattery) private var peripheralInMenuBar = false
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        if AppFeature.monitorPower.isAvailable {
            let text = ForkBatteryStrings.current
            VStack(alignment: .leading, spacing: 10) {
                Label(text.title, systemImage: "battery.75").font(.headline)
                if PowerSampler.hasInternalBattery {
                    Toggle(text.alerts, isOn: $alerts)
                    caption(text.alertsCaption)
                    Toggle(text.halo, isOn: $halo).disabled(!alerts)
                    Toggle(text.powerSounds, isOn: $powerSounds)
                    Divider()
                }
                Picker(text.pinned, selection: $pinned) {
                    Text(text.none).tag("")
                    ForEach(choices, id: \.self) { name in Text(name).tag(name) }
                }
                Toggle(text.showInMenuBar, isOn: $peripheralInMenuBar)
                caption(text.pinnedCaption)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }

    /// The devices seen now, and the pinned one even while it is away.
    private var choices: [String] {
        var names = PeripheralBatterySupport.sorted(monitor.snapshot.peripheralBatteries).map(\.name)
        if !pinned.isEmpty, !names.contains(pinned) { names.append(pinned) }
        return names
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
