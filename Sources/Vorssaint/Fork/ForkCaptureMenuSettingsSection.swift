// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The capture menu's own settings, on the fork's capture page: its shortcut,
/// what it shows first, what its Area item does, and which items its bar
/// shows, in which order.
struct ForkCaptureMenuSettingsSection: View {
    typealias Layout = ForkCaptureMenuLayout

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.forkCaptureMenuShortcutEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkCaptureMenuShortcut) private var shortcutRaw = Layout.defaultShortcut.storageValue
    @AppStorage(DefaultsKey.forkCaptureMenuOpening) private var opening = Layout.Opening.bar.rawValue
    @AppStorage(DefaultsKey.forkCaptureMenuAreaAtOnce) private var areaAtOnce = true
    @AppStorage(DefaultsKey.forkCaptureMenuItems) private var itemsRaw = ""
    @State private var shortcutError: String?

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: shortcutRaw) ?? Layout.defaultShortcut
    }

    private var items: [Layout.Item] { Layout.items(stored: itemsRaw) }

    var body: some View {
        let text = ForkCaptureMenuStrings.current
        Section(text.section(shortcut.displayString)) {
            LabeledContent(text.shortcut) {
                ShortcutRecorderButton(shortcut: shortcut,
                                       isEnabled: enabled,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       invalidAction: { shortcutError = l10n.s.shortcutInvalid },
                                       captureAction: { captured in
                                           shortcutRaw = captured.storageValue
                                           shortcutError = nil
                                       })
                    .frame(width: 160, height: 24)
            }
            if let shortcutError { warning(shortcutError) }

            Picker(text.opening, selection: $opening) {
                ForEach(Layout.Opening.allCases, id: \.self) { choice in
                    Text(text.name(of: choice)).tag(choice.rawValue)
                }
            }

            Toggle(text.areaAtOnce, isOn: $areaAtOnce)
            caption(text.areaAtOnceCaption)

            Text(text.items)
            ForEach(Array(items.enumerated()), id: \.element.mode) { index, item in
                HStack {
                    Toggle(name(of: item.mode), isOn: shownBinding(at: index))
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help(text.moveUp)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == items.count - 1)
                        .help(text.moveDown)
                }
            }
            HStack {
                caption(text.itemsCaption)
                Spacer()
                Button(text.defaultOrder) { itemsRaw = Layout.encoded(Layout.items(stored: nil)) }
                    .controlSize(.small)
            }
        }
    }

    private func shownBinding(at index: Int) -> Binding<Bool> {
        Binding(get: { items[index].shown }, set: { shown in
            var changed = items
            changed[index].shown = shown
            // At least one item stays: items(stored:) shows the first otherwise.
            itemsRaw = Layout.encoded(Layout.items(stored: Layout.encoded(changed)))
        })
    }

    private func move(_ index: Int, by offset: Int) {
        itemsRaw = Layout.encoded(Layout.moving(items, at: index, by: offset))
    }

    private func name(of mode: Layout.Mode) -> String {
        let text = ForkStrings.current
        switch mode {
        case .area: return text.captureMenuArea
        case .fullScreen: return text.captureMenuFullScreen
        case .window: return text.captureMenuWindow
        case .scrolling: return text.captureMenuScrolling
        case .timer: return text.captureMenuTimer
        case .text: return text.captureMenuText
        default: return text.captureMenuRecording
        }
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ string: String) -> some View {
        Label(string, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
