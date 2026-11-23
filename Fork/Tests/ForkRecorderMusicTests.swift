// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import Foundation

/// A piece of music added to a recording in the video editor.
enum ForkRecorderMusicTests {
    typealias Music = ForkRecorderMusic

    static func run(_ suite: TestSuite) {
        // How long it plays.
        suite.expect(Music.playedDuration(music: 200, video: 30) == 30, "music longer than the video is cut at the video's end")
        suite.expect(Music.playedDuration(music: 12, video: 30) == 12, "shorter music simply ends: it is not looped")
        suite.expect(Music.playedDuration(music: .nan, video: 30) == 0 && Music.playedDuration(music: -4, video: 30) == 0,
               "a length that is no length plays nothing")

        // The fade at its end.
        let long = Music.fadeOut(endingAt: 30)
        suite.expect(long.start == 29 && long.duration == Music.fade, "the music fades out over its last second")
        let short = Music.fadeOut(endingAt: 1)
        suite.expect(short.start == 0.5 && short.duration == 0.5, "a very short piece fades over its second half only")
        suite.expect(Music.fadeOut(endingAt: 0).duration == 0, "nothing played, nothing to fade")

        // Its volume.
        suite.expect(Music.volume(0.4) == 0.4 && Music.volume(3) == 1 && Music.volume(-1) == 0
            && Music.volume(.nan) == Music.defaultGain,
               "the volume stays between silent and full; no value means the default")
        suite.expect(Music.defaultGain == 0.5, "music starts at half volume, under a voice")

        // Its lane.
        suite.expect(Music.coveredShare(music: 15, video: 30) == 0.5 && Music.coveredShare(music: 90, video: 30) == 1
            && Music.coveredShare(music: 15, video: 0) == 0,
               "the lane shows how much of the video the music covers")

        // In the edit.
        var document = RecorderEditDocument()
        suite.expect(document.forkMusic == nil && !Music.isPresent(in: document), "an edit starts without music")
        let plain = RecorderEditDocument.decoded(document.encoded())
        suite.expect(plain.forkMusic == nil && plain == document, "an edit without music is saved and read back as before")

        let track = Music.Track(path: "/tmp/take/fork-music-1.mp3", name: "theme.mp3", duration: 42)
        suite.expect(track.gain == Music.defaultGain, "added music takes the default volume")
        document.forkMusic = track
        suite.expect(Music.isPresent(in: document), "the edit now has music")
        suite.expect(RecorderEditDocument.decoded(document.encoded()).forkMusic == track,
               "the music is saved with the edit and read back")
        suite.expect(document.sanitized(duration: 60).forkMusic == track, "checking an edit keeps its music")

        let silent = RecorderEditDocument()
        suite.expect(silent.affectsTiming(document) && document.affectsTiming(silent),
               "adding or removing music rebuilds what the player plays")
        var louder = document
        louder.forkMusic?.gain = 0.9
        suite.expect(document.affectsAudio(louder) && !document.affectsTiming(louder),
               "changing the music's volume only changes the mix")
        suite.expect(!document.affectsPicture(louder), "music never redraws the picture")

        // The mix leaves an edit without music alone.
        suite.expect(Music.mixing(nil, in: nil, document: silent) == nil,
               "no music: upstream's mix is passed through untouched")
        let empty = AVMutableComposition()
        suite.expect(Music.mixing(nil, in: empty, document: document) == nil,
               "music in the edit but no music track in the timeline: nothing is added to the mix")

        // With a music track in the timeline, the mix carries its volume.
        if let added = empty.addMutableTrack(withMediaType: .audio, preferredTrackID: Music.trackID) {
            suite.expect(added.trackID == Music.trackID, "the music track keeps the identifier the mix looks for")
            let mix = Music.mixing(nil, in: empty, document: document)
            suite.expect(mix?.inputParameters.count == 1 && mix?.inputParameters.first?.trackID == Music.trackID,
                   "the mix gains one entry, for the music track")
            let upstream = AVMutableAudioMix()
            let other = AVMutableAudioMixInputParameters()
            other.trackID = 1
            upstream.inputParameters = [other]
            suite.expect(Music.mixing(upstream, in: empty, document: document)?.inputParameters.map(\.trackID)
                == [1, Music.trackID],
                   "upstream's own entries are kept, the music's comes after")
        } else {
            suite.expect(false, "a composition accepts a track with the music's identifier")
        }

        exportCarriesTheMusic(suite)
    }

    // MARK: - A real export

    private enum Fixture: Error { case video, music }

    /// The proof that matters: a silent recording, a piece of music longer
    /// than it, and the file the exporter writes.
    private static func exportCarriesTheMusic(_ suite: TestSuite) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await export(suite)
            } catch {
                suite.expect(false, "the music export fixture is built: \(error)")
            }
            done.signal()
        }
        suite.expect(done.wait(timeout: .now() + 120) == .success, "the export with music finishes within its deadline")
    }

    private static func export(_ suite: TestSuite) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("fork-music-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let take = RecorderTakeStore.Take(id: UUID(), folder: folder)
        try await writeSilentVideo(to: take.videoURL, seconds: 2)
        let musicURL = folder.appendingPathComponent("fork-music-test.wav")
        try writeTone(to: musicURL, seconds: 5)

        var document = RecorderEditDocument()
        document.showsPointer = false
        document.zoomEnabled = false
        let plain = folder.appendingPathComponent("plain.mp4")
        let plainFailure = await RecorderExporter().export(take: take, document: document, output: .video,
                                                           to: plain, progress: { _ in })
        let plainAudio = try await AVURLAsset(url: plain).loadTracks(withMediaType: .audio)
        suite.expect(plainFailure == nil && plainAudio.isEmpty, "without music a silent recording exports without sound")

        document.forkMusic = Music.Track(path: musicURL.path, name: "tone.wav", duration: 5, gain: 1)
        let output = folder.appendingPathComponent("music.mp4")
        let failure = await RecorderExporter().export(take: take, document: document, output: .video,
                                                      to: output, progress: { _ in })
        suite.expect(failure == nil, "a silent recording with music exports")
        let asset = AVURLAsset(url: output)
        let video = try await asset.load(.duration).seconds
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first else {
            suite.expect(false, "the exported video has a sound track: the music")
            return
        }
        let length = try await audio.load(.timeRange).duration.seconds
        suite.expect(abs(video - 2) < 0.2 && abs(length - 2) < 0.25,
               "the music is cut at the video's end: video \(video) s, sound \(length) s")
        let peaks = try loudness(of: audio, in: asset, length: length)
        suite.expect(peaks.start > 0.3, "the music is heard at full volume at the start: peak \(peaks.start)")
        suite.expect(peaks.end < peaks.start * 0.5, "and fades out at the end: peak \(peaks.end) after \(peaks.start)")

        document.forkMusic?.gain = 0.25
        let quiet = folder.appendingPathComponent("quiet.mp4")
        _ = await RecorderExporter().export(take: take, document: document, output: .video, to: quiet, progress: { _ in })
        let quietAsset = AVURLAsset(url: quiet)
        if let track = try await quietAsset.loadTracks(withMediaType: .audio).first {
            let quietPeaks = try loudness(of: track, in: quietAsset, length: 2)
            suite.expect(quietPeaks.start < peaks.start * 0.5,
                   "a lower volume is a quieter export: \(quietPeaks.start) against \(peaks.start)")
        } else {
            suite.expect(false, "the quiet export has its sound track")
        }
    }

    /// The loudest sample in the first second, and in the last tenth of a second.
    private static func loudness(of track: AVAssetTrack, in asset: AVAsset, length: Double) throws -> (start: Float, end: Float) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw Fixture.music }
        var start: Float = 0
        var end: Float = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration = CMSampleBufferGetDuration(sample).seconds
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var values = [Float](repeating: 0, count: count)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: &values)
            for (index, value) in values.enumerated() {
                let moment = time + duration * Double(index) / Double(max(1, count))
                if moment < 1 { start = max(start, abs(value)) }
                if moment > length - 0.1 { end = max(end, abs(value)) }
            }
        }
        return (start, end)
    }

    private static func writeTone(to url: URL, seconds: Double) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(44_100 * seconds)),
              let channels = buffer.floatChannelData
        else { throw Fixture.music }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 44_100) * 0.8)
            channels[0][frame] = value
            channels[1][frame] = value
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func writeSilentVideo(to url: URL, seconds: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128,
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var created: CVPixelBuffer?
            guard let pool = adapter.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess,
                  let pixel = created
            else { throw Fixture.video }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let base = CVPixelBufferGetBaseAddress(pixel) {
                memset(base, 96, CVPixelBufferGetBytesPerRow(pixel) * CVPixelBufferGetHeight(pixel))
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            else { throw Fixture.video }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw Fixture.video }
    }
}
