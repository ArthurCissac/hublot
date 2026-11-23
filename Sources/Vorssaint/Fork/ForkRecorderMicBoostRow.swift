// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// Under the microphone's lane in the video editor: how much louder than
/// 100 % it is made, up to four times. One line of upstream's editor view.
struct ForkRecorderMicBoostRow: View {
    @ObservedObject var model: RecorderEditorModel
    /// The value while the slider is held; the edit takes it when it is let go.
    @State private var draft: Double?

    var body: some View {
        if model.hasAudio(.microphone) {
            let text = ForkStrings.current
            let boost = draft ?? ForkRecorderAudioBoost.boost(in: model.document)
            HStack(spacing: 10) {
                Text(text.micBoostLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                    .lineLimit(1)
                Slider(value: Binding(get: { boost }, set: { draft = $0 }), in: ForkRecorderAudioBoost.range) { editing in
                    guard !editing, let draft else { return }
                    self.draft = nil
                    var next = model.document
                    next.forkMicrophoneBoost = draft > 1.001 ? draft : nil
                    model.document = next
                }
                .frame(width: 180)
                .disabled(!model.keepsAudio(.microphone))
                .help(text.micBoostHelp)
                .accessibilityLabel(text.micBoostLabel)
                Text("\(Int((boost * 100).rounded()))%")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(boost > 1.001 ? Color.orange : Color.secondary)
                    .frame(width: 40, alignment: .leading)
                Spacer()
            }
            .frame(height: 22)
        }
    }
}
