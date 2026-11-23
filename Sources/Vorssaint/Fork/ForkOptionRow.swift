// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// A settings line for the fork's own options, drawn like upstream's
/// `SettingsRow`: a tinted symbol, a title, a caption, a control on the
/// right. Upstream's Settings search indexes only upstream's own texts, and
/// its coverage test asks that every `SettingsRow` title be found there; the
/// fork's texts live in `ForkStrings.swift`, so its lines use this look-alike.
struct ForkOptionRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let caption: String?
    let accessory: Accessory

    init(symbol: String, title: String, caption: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}
