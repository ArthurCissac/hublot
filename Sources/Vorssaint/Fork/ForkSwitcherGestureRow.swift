// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The trackpad gesture's setting, placed by one line in upstream's switcher
/// settings, under its shortcuts.
struct ForkSwitcherGestureRow: View {
    let switcherEnabled: Bool
    @AppStorage(DefaultsKey.forkSwitcherTrackpadGesture) private var gesture = false
    @AppStorage(DefaultsKey.forkSwitcherTrackpadFingers) private var fingers = 4

    var body: some View {
        let text = ForkStrings.current
        let switcher = ForkSwitcherStrings.current
        VStack(alignment: .leading, spacing: 6) {
            Toggle(switcher.toggle(fingers == 3 ? 3 : 4), isOn: $gesture)
                .disabled(!switcherEnabled)
            Picker(switcher.fingers, selection: $fingers) {
                Text("3").tag(3)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .disabled(!switcherEnabled)
            Text(text.switcherGestureCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if gesture, ForkTrackpadSwitcher.systemUsesSwipe(fingers: fingers == 3 ? 3 : 4) {
                HStack(spacing: 8) {
                    Text(switcher.conflict(fingers == 3 ? 3 : 4))
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
