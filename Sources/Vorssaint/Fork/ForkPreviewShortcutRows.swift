// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The capture previews' two shortcuts, on the fork's capture page: reopen
/// the last card put away, hide every card. Each can be switched off or set
/// to another combination.
struct ForkPreviewShortcutRows: View {
    @ObservedObject private var cards = ForkPreviewCards.shared

    var body: some View {
        let text = ForkPreviewStrings.current
        ForkShortcutField(title: text.reopenToggle,
                          caption: text.reopenCaption,
                          enabledKey: DefaultsKey.forkReopenPreviewShortcutEnabled,
                          shortcutKey: DefaultsKey.forkReopenPreviewShortcut,
                          fallback: ForkPreviewCardGestures.reopenShortcut,
                          unavailable: cards.unavailableShortcuts.contains(DefaultsKey.forkReopenPreviewShortcut))
        ForkShortcutField(title: text.hideToggle,
                          caption: text.hideCaption,
                          enabledKey: DefaultsKey.forkHidePreviewsShortcutEnabled,
                          shortcutKey: DefaultsKey.forkHidePreviewsShortcut,
                          fallback: ForkPreviewCardGestures.hideShortcut,
                          unavailable: cards.unavailableShortcuts.contains(DefaultsKey.forkHidePreviewsShortcut))
    }
}

/// A global shortcut the fork adds: a switch, the combination (click to
/// record another), what it does, and a word when macOS refused it.
struct ForkShortcutField: View {
    @ObservedObject private var l10n = L10n.shared
    let title: String
    let caption: String
    let fallback: GlobalShortcut
    let unavailable: Bool
    @AppStorage private var enabled: Bool
    @AppStorage private var shortcutRaw: String
    @State private var error: String?

    init(title: String, caption: String, enabledKey: String, shortcutKey: String, fallback: GlobalShortcut, unavailable: Bool) {
        self.title = title
        self.caption = caption
        self.fallback = fallback
        self.unavailable = unavailable
        _enabled = AppStorage(wrappedValue: true, enabledKey)
        _shortcutRaw = AppStorage(wrappedValue: fallback.storageValue, shortcutKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(title, isOn: $enabled)
                Spacer()
                ShortcutRecorderButton(shortcut: GlobalShortcut(storageValue: shortcutRaw) ?? fallback,
                                       isEnabled: enabled,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       invalidAction: { error = l10n.s.shortcutInvalid },
                                       captureAction: { captured in
                                           shortcutRaw = captured.storageValue
                                           error = nil
                                       })
                    .frame(width: 140, height: 24)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = error ?? (enabled && unavailable ? ForkPreviewStrings.current.shortcutTaken : nil) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
