// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// The video editor's two additions for music: a button beside upstream's
/// "add text" and "add picture", and a lane on the timeline with the music's
/// name, its volume and a way to remove it. Each is one line in upstream's
/// editor view. What the music does to the video is in `ForkRecorderMusic`.
struct ForkRecorderMusicButton: View {
    @ObservedObject var model: RecorderEditorModel

    var body: some View {
        let text = ForkStrings.current
        Button {
            guard let url = ForkRecorderMusicFiles.choose() else { return }
            let take = model.take
            Task { @MainActor in
                guard let track = await ForkRecorderMusicFiles.importMusic(from: url, into: take) else {
                    QuickToolHUD.show(icon: "music.note", message: text.musicImportFailed)
                    return
                }
                // One edit: undo takes the music away again.
                var next = model.document
                next.forkMusic = track
                model.document = next
            }
        } label: {
            Label(text.addMusicButton, systemImage: "music.note")
                .font(.system(size: 12, weight: .medium))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .screenshotSafeHelp(text.addMusicButton)
        .accessibilityLabel(text.addMusicButton)
        .foregroundStyle(Color(white: 0.8))
    }
}

/// The music's lane: nothing at all while the edit has no music.
struct ForkRecorderMusicLane: View {
    @ObservedObject var model: RecorderEditorModel
    /// The volume while the slider is held; the edit takes it when it is let go.
    @State private var draft: Double?

    var body: some View {
        if let music = model.document.forkMusic {
            let text = ForkStrings.current
            // Laid out like upstream's timeline rows: a title, then the lane.
            HStack(spacing: 10) {
                Text(text.musicLaneLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                    .lineLimit(1)
                lane(music, text: text)
                    .frame(height: 32)
            }
        }
    }

    private func lane(_ music: ForkRecorderMusic.Track, text: ForkStrings) -> some View {
        let gain = draft ?? ForkRecorderMusic.volume(music.gain)
        let share = ForkRecorderMusic.coveredShare(music: music.duration, video: model.outputDuration)
        return HStack(spacing: 8) {
            // How much of the video the music covers, with its name on it.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.green.opacity(0.32))
                        .frame(width: max(4, proxy.size.width * share))
                    Label(music.name, systemImage: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                }
                .frame(height: proxy.size.height)
            }
            .frame(maxWidth: .infinity)

            Slider(value: Binding(get: { gain }, set: { draft = $0 }),
                   in: ForkRecorderMusic.gainRange) { editing in
                guard !editing, let draft else { return }
                self.draft = nil
                var next = model.document
                next.forkMusic?.gain = draft
                model.document = next
            }
            .frame(width: 92)
            .screenshotSafeHelp(text.musicVolume)
            .accessibilityLabel(text.musicVolume)

            Text("\(Int((gain * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            Button {
                // The copy stays beside the recording, so undo brings the music back.
                var next = model.document
                next.forkMusic = nil
                model.document = next
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.secondary)
            .screenshotSafeHelp(text.removeMusic)
            .accessibilityLabel(text.removeMusic)
        }
        .padding(.horizontal, 8)
        .background(Color.green.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Choosing a sound file and copying it beside the recording.
enum ForkRecorderMusicFiles {
    /// Larger than any song; a file past this is refused rather than copied.
    private static let largestFile = 300 * 1_024 * 1_024

    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Copies the file into the recording's own folder, which upstream deletes
    /// with the recording, and reads its length. Nil for anything that is not
    /// a readable sound: the type and the size are checked here, not trusted
    /// from the panel.
    static func importMusic(from url: URL, into take: RecorderTakeStore.Take) async -> ForkRecorderMusic.Track? {
        await Task.detached(priority: .userInitiated) { () -> ForkRecorderMusic.Track? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size > 0, size <= largestFile,
                  values.contentType?.conforms(to: .audio) == true
            else { return nil }
            let fileExtension = url.pathExtension.isEmpty ? "audio" : url.pathExtension
            let copy = take.folder.appendingPathComponent("fork-music-\(UUID().uuidString).\(fileExtension)")
            do {
                try FileManager.default.copyItem(at: url, to: copy)
            } catch {
                return nil
            }
            let asset = AVURLAsset(url: copy)
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
                  let length = try? await asset.load(.duration), length.isNumeric, length.seconds > 0
            else {
                try? FileManager.default.removeItem(at: copy)
                return nil
            }
            return ForkRecorderMusic.Track(path: copy.path, name: url.lastPathComponent, duration: length.seconds)
        }.value
    }
}
