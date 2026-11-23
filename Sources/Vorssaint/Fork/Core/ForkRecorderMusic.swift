// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import Foundation

/// A piece of music added to a recording in the video editor. Upstream mixes
/// the two sounds it recorded, the Mac's and the microphone's; the fork adds
/// one more track, from a file.
///
/// The music starts with the video and plays at its own speed, whatever the
/// export speed. A piece longer than the video is cut at the video's end; a
/// shorter one simply ends. Either way it fades out over its last second.
/// The edit names a private copy of the file kept beside the recording, as
/// upstream does for pictures.
enum ForkRecorderMusic {
    struct Track: Codable, Equatable {
        /// The private copy, beside the recording.
        var path: String
        /// The chosen file's name, shown in the editor.
        var name: String
        /// The music's own length in seconds, read when it was added.
        var duration: Double
        var gain: Double

        init(path: String, name: String, duration: Double, gain: Double = ForkRecorderMusic.defaultGain) {
            self.path = path
            self.name = name
            self.duration = duration
            self.gain = gain
        }
    }

    /// Half volume: music under a voice, not over it.
    static let defaultGain: Double = 0.5
    static let gainRange: ClosedRange<Double> = 0...1
    /// The fade at the music's end, in seconds.
    static let fade: Double = 1
    /// The music's track in the composition, so the mix finds it again.
    static let trackID: CMPersistentTrackID = 7_071

    static func isPresent(in document: RecorderEditDocument) -> Bool {
        document.forkMusic != nil
    }

    static func volume(_ gain: Double) -> Double {
        guard gain.isFinite else { return defaultGain }
        return min(gainRange.upperBound, max(gainRange.lowerBound, gain))
    }

    /// How long the music plays: all of it, or as much as the video lasts.
    static func playedDuration(music: Double, video: Double) -> Double {
        guard music.isFinite, video.isFinite else { return 0 }
        return max(0, min(music, video))
    }

    /// The fade that ends when the music does. Never more than half of what
    /// plays, so a very short piece is not all fade.
    static func fadeOut(endingAt end: Double) -> (start: Double, duration: Double) {
        guard end.isFinite, end > 0 else { return (0, 0) }
        let duration = min(fade, end / 2)
        return (end - duration, duration)
    }

    /// The share of the video the music covers, for its lane on the timeline.
    static func coveredShare(music: Double, video: Double) -> Double {
        guard video.isFinite, video > 0 else { return 0 }
        return min(1, playedDuration(music: music, video: video) / video)
    }

    // MARK: - In the composition

    /// Adds the music to a finished timeline. Called after upstream has built
    /// and retimed it, so the music is never sped up with the video.
    static func add(to composition: AVMutableComposition, document: RecorderEditDocument, duration: CMTime) async {
        guard let music = document.forkMusic, duration.isNumeric, duration.seconds > 0 else { return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: music.path))
        guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
              let length = try? await asset.load(.duration), length.isNumeric, length.seconds > 0,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: trackID)
        else { return }
        let played = CMTime(seconds: playedDuration(music: length.seconds, video: duration.seconds),
                            preferredTimescale: 600)
        do {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: played), of: source, at: .zero)
        } catch {
            // A file that cannot be read leaves the video as it was, without music.
            composition.removeTrack(track)
        }
    }

    /// Upstream's mix, with the music's volume and its fade added. Unchanged
    /// when the edit has no music or the timeline has no music track.
    static func mixing(_ mix: AVAudioMix?, in asset: AVAsset?, document: RecorderEditDocument) -> AVAudioMix? {
        guard let music = document.forkMusic,
              let composition = asset as? AVComposition,
              let track = composition.tracks.first(where: { $0.trackID == trackID })
        else { return mix }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        let gain = Float(volume(music.gain))
        parameters.setVolume(gain, at: .zero)
        let fade = fadeOut(endingAt: track.timeRange.end.seconds)
        if fade.duration > 0 {
            parameters.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0,
                                     timeRange: CMTimeRange(
                                        start: CMTime(seconds: fade.start, preferredTimescale: 600),
                                        duration: CMTime(seconds: fade.duration, preferredTimescale: 600)))
        }
        let result = AVMutableAudioMix()
        result.inputParameters = (mix?.inputParameters ?? []) + [parameters]
        return result
    }
}
