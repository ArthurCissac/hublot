// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import Foundation

/// The microphone made louder than 100 % in the video editor.
enum ForkRecorderBoostTests {
    typealias Boost = ForkRecorderAudioBoost

    static func run(_ suite: TestSuite) {
        suite.expect(Boost.shaped(0.2, gain: 3) == 0.6000000238418579 || abs(Boost.shaped(0.2, gain: 3) - 0.6) < 0.0001,
               "a quiet sample is simply made louder")
        let loud = Boost.shaped(0.5, gain: 3)
        suite.expect(loud > 0.8 && loud < 1, "a sample pushed past full scale is rounded off below it, not clipped: \(loud)")
        suite.expect(Boost.shaped(-0.5, gain: 3) == -loud, "the same on both sides of silence")
        suite.expect(Boost.shaped(0.3, gain: 4) > Boost.shaped(0.25, gain: 4), "louder in stays louder out")
        suite.expect(Boost.shaped(0.5, gain: 1) == 0.5, "at 100 % nothing changes")

        var document = RecorderEditDocument()
        suite.expect(Boost.boost(in: document) == 1, "an edit starts at 100 %")
        document.forkMicrophoneBoost = 9
        suite.expect(Boost.boost(in: document) == Boost.range.upperBound, "the boost stops at four times")
        document.forkMicrophoneBoost = 2.5
        suite.expect(RecorderEditDocument.decoded(document.encoded()).forkMicrophoneBoost == 2.5,
               "the boost is saved with the edit and read back")
        suite.expect(RecorderEditDocument().affectsAudio(document) && !RecorderEditDocument().affectsPicture(document),
               "changing the boost changes the mix, never the picture")

        let parameters = AVMutableAudioMixInputParameters()
        Boost.apply(to: parameters, source: .system, document: document)
        suite.expect(parameters.audioTapProcessor == nil, "the Mac's sound is left alone")
        Boost.apply(to: parameters, source: .microphone, document: document)
        suite.expect(parameters.audioTapProcessor != nil, "the microphone gets the boost")
        var muted = document
        muted.keepsMicrophone = false
        let silent = AVMutableAudioMixInputParameters()
        Boost.apply(to: silent, source: .microphone, document: muted)
        suite.expect(silent.audioTapProcessor == nil, "a microphone left out of the edit is not processed")

        readsLouder(suite)
    }

    /// A real read through a mix: a quiet tone comes out louder with the tap.
    private static func readsLouder(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fork-boost-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tone.wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = 44_100
        for frame in 0..<44_100 { channel[frame] = Float(sin(2 * Double.pi * 440 * Double(frame) / 44_100) * 0.2) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        } catch {
            suite.expect(false, "the test tone is written: \(error)")
            return
        }
        func peak(gain: Float?) -> Float {
            let asset = AVURLAsset(url: url)
            let semaphore = DispatchSemaphore(value: 0)
            var tracks: [AVAssetTrack] = []
            Task.detached {
                tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                semaphore.signal()
            }
            semaphore.wait()
            guard let track = tracks.first, let reader = try? AVAssetReader(asset: asset) else { return -1 }
            let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            ])
            let parameters = AVMutableAudioMixInputParameters(track: track)
            if let gain { parameters.audioTapProcessor = Boost.makeTap(gain: gain) }
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            output.audioMix = mix
            reader.add(output)
            guard reader.startReading() else { return -1 }
            var loudest: Float = 0
            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
                var values = [Float](repeating: 0, count: count)
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: &values)
                loudest = max(loudest, values.map(abs).max() ?? 0)
            }
            return loudest
        }
        let plain = peak(gain: nil)
        let boosted = peak(gain: 3)
        suite.expect(abs(plain - 0.2) < 0.02, "the tone reads at its own level without the boost: \(plain)")
        suite.expect(abs(boosted - 0.6) < 0.05, "read through the boost, it is three times as loud: \(boosted)")
    }
}
