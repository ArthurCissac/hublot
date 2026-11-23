// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The trackpad gesture's setting, placed by one line in upstream's switcher
/// settings, under its shortcuts.
struct ForkSwitcherGestureRow: View {
    let switcherEnabled: Bool
    @AppStorage(DefaultsKey.forkSwitcherTrackpadGesture) private var gesture = false

    var body: some View {
        let text = ForkStrings.current
        VStack(alignment: .leading, spacing: 6) {
            Toggle(text.switcherGestureToggle, isOn: $gesture)
                .disabled(!switcherEnabled)
            Text(text.switcherGestureCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if gesture, ForkTrackpadSwitcher.systemUsesThreeFingerSwipe {
                HStack(spacing: 8) {
                    Text(text.switcherGestureConflict)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(text.switcherGestureOpenTrackpad) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
