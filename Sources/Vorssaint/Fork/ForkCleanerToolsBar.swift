// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// Lot 9's way in, at the top of the Cleaner page: the one-click scan first,
/// then the disk map, the antivirus and maintenance, each in a window of its
/// own. When the page is too narrow for every label, the three tools keep
/// their symbol, with their name as a tooltip and for VoiceOver. Hidden when
/// its setting is off.
struct ForkCleanerToolsBar: View {
    @AppStorage(DefaultsKey.forkCleanerTools) private var enabled = true
    @Environment(\.forkInCareHub) private var inCareHub

    var body: some View {
        if enabled, !inCareHub {
            let text = ForkDiskToolsStrings.current
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { ForkSmartScanWindow.shared.show() } label: {
                        Label(ForkSmartScanStrings.current.title, systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    ViewThatFits(in: .horizontal) {
                        tools(text, labelled: true)
                        tools(text, labelled: false)
                    }
                    Spacer(minLength: 0)
                    Toggle(text.showTools, isOn: $enabled).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .accessibilityLabel(text.showTools)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private func tools(_ text: ForkDiskToolsStrings, labelled: Bool) -> some View {
        HStack(spacing: 10) {
            tool(text.diskMapTitle, symbol: "square.grid.3x3.square", labelled: labelled) { ForkDiskMapWindow.shared.show() }
            tool(text.antivirusTitle, symbol: "checkmark.shield", labelled: labelled) { ForkAntivirusWindow.shared.show() }
            tool(ForkMaintenanceStrings.current.title, symbol: "wrench.and.screwdriver", labelled: labelled) {
                ForkMaintenanceWindow.shared.show()
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func tool(_ title: String, symbol: String, labelled: Bool, action: @escaping () -> Void) -> some View {
        if labelled {
            Button(action: action) { Label(title, systemImage: symbol) }
        } else {
            Button(action: action) { Image(systemName: symbol) }
                .accessibilityLabel(title)
                .screenshotSafeHelp(title)
        }
    }
}
