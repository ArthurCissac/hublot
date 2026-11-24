// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The setting in the Energy page, under upstream's closed-lid options,
/// placed by one line in `EnergySettings`.
struct ForkLidDisplaySleepRow: View {
    @AppStorage(DefaultsKey.forkLidSleepsDisplays) private var enabled = true

    var body: some View {
        let text = ForkEnergyStrings.current
        ForkOptionRow(symbol: "display", title: text.lidSleepsDisplaysTitle,
                      caption: text.lidSleepsDisplaysCaption) {
            Toggle(text.lidSleepsDisplaysTitle, isOn: $enabled)
                .labelsHidden()
        }
    }
}

/// The same setting in the menu bar panel's Keep Awake card, under "Keep
/// awake with the lid closed", drawn like that card's own option rows.
/// Placed by one line in `MenuPanelView`; shown only when that mode is wanted.
struct ForkLidDisplaySleepMenuRow: View {
    let clamshellPreferred: Bool
    @AppStorage(DefaultsKey.forkLidSleepsDisplays) private var enabled = true

    var body: some View {
        if clamshellPreferred {
            let text = ForkEnergyStrings.current
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.lidSleepsDisplaysTitle)
                        .font(.system(size: 12))
                    Text(text.lidSleepsDisplaysShortCaption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
                Toggle(text.lidSleepsDisplaysTitle, isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
    }
}
