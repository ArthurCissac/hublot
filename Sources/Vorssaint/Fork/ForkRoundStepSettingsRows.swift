// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The round 5 % steps of the volume and brightness keys, placed by one line
/// in upstream's island feedback settings, under the cards that turn the
/// volume and brightness feedback on. A row shows only while its card is on.
struct ForkRoundStepSettingsRows: View {
    let volume: Bool
    let brightness: Bool
    @AppStorage(DefaultsKey.forkVolumeRoundSteps) private var volumeSteps = true
    @AppStorage(DefaultsKey.forkBrightnessRoundSteps) private var brightnessSteps = true

    var body: some View {
        let text = ForkRoundStepStrings.current
        if volume || brightness {
            VStack(alignment: .leading, spacing: 8) {
                if volume {
                    ForkOptionRow(symbol: "speaker.wave.2", title: text.volumeToggle, caption: brightness ? nil : text.caption) {
                        Toggle(text.volumeToggle, isOn: $volumeSteps).labelsHidden().toggleStyle(.switch)
                    }
                }
                if brightness {
                    ForkOptionRow(symbol: "sun.max", title: text.brightnessToggle, caption: text.caption) {
                        Toggle(text.brightnessToggle, isOn: $brightnessSteps).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
        }
    }
}
