// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The shelf's settings, placed by one line in upstream's clipboard settings,
/// under the shortcut that opens the history: the shelf itself, Liquid Glass,
/// and the colour it is tinted with.
struct ForkClipboardSettingsSection: View {
    @AppStorage(DefaultsKey.forkClipboardShelf) private var shelf = true
    @AppStorage(DefaultsKey.forkClipboardShelfGlass) private var glass = true
    @AppStorage(DefaultsKey.forkClipboardShelfTint) private var tintHex = ForkShelfTint.defaultHex
    @AppStorage(DefaultsKey.forkClipboardShelfTintIntensity) private var intensity = ForkShelfTint.defaultIntensity
    @AppStorage(DefaultsKey.forkClipboardCopySound) private var copySound = ForkClipboardCopySound.defaultSound

    var body: some View {
        let text = ForkStrings.current
        Section {
            Toggle(text.clipboardShelfToggle, isOn: $shelf)
            caption(text.clipboardShelfCaption)
            Picker(text.copySoundLabel, selection: $copySound) {
                Text(text.copySoundNone).tag("")
                ForEach(ForkClipboardCopySound.sounds, id: \.self) { name in Text(name).tag(name) }
            }
            .onChange(of: copySound) { _, name in
                if let sound = ForkClipboardCopySound.sound(stored: name) { ForkClipboardCopySoundPlayer.shared.play(sound) }
            }
            if shelf {
                if #available(macOS 26.0, *) {
                    Toggle(text.shelfGlassToggle, isOn: $glass)
                }
                Toggle(text.shelfTintToggle, isOn: Binding(
                    get: { ForkShelfTint.components(tintHex) != nil },
                    set: { tintHex = $0 ? ForkShelfTint.defaultHex : "" }))
                if ForkShelfTint.components(tintHex) != nil {
                    ColorPicker(text.shelfTintColor, selection: color, supportsOpacity: false)
                    LabeledContent(text.shelfTintIntensity) {
                        Slider(value: $intensity, in: ForkShelfTint.intensityRange)
                            .frame(maxWidth: 220)
                    }
                }
            }
        }
    }

    /// The stored colour as a colour well's value, and back.
    private var color: Binding<Color> {
        Binding(
            get: {
                let rgb = ForkShelfTint.components(tintHex) ?? (0.24, 0.48, 1)
                return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                tintHex = ForkShelfTint.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
            })
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
