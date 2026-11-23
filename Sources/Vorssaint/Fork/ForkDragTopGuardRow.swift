// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The drag guard's setting, placed by one line in upstream's shelf settings.
struct ForkDragTopGuardRow: View {
    @AppStorage(DefaultsKey.forkDragTopGuard) private var enabled = true

    var body: some View {
        let text = ForkShelfStrings.current
        VStack(alignment: .leading, spacing: 3) {
            Toggle(text.dragTopGuardToggle, isOn: $enabled)
            Text(text.dragTopGuardCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
