// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import MediaToolbox

/// The microphone made louder than upstream's 100 %. A mix's volume stops
/// at 1, so above it an audio processing tap multiplies the microphone's
/// samples, rounding off the peaks rather than clipping them hard. The same
/// mix serves the editor's playback and the export, so both hear it.
/// Called from one line of upstream's mix.
enum ForkRecorderAudioBoost {
    static let range: ClosedRange<Double> = 1...4
    /// Below this, samples pass as they are multiplied; above it they are rounded off.
    static let knee: Float = 0.8

    static func boost(in document: RecorderEditDocument) -> Double {
        guard let value = document.forkMicrophoneBoost, value.isFinite else { return 1 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// One sample, made louder and kept within -1...1 without a hard edge.
    static func shaped(_ sample: Float, gain: Float) -> Float {
        let louder = sample * gain
        let magnitude = abs(louder)
        guard magnitude > knee else { return louder }
        let room = 1 - knee
        let rounded = knee + room * Float(tanh(Double((magnitude - knee) / room)))
        return louder < 0 ? -rounded : rounded
    }

    /// Adds the tap to the microphone's track when it is to be louder than 100 %.
    static func apply(to parameters: AVMutableAudioMixInputParameters, source: RecorderAudioSource,
                      document: RecorderEditDocument) {
        guard source == .microphone, document.keepsMicrophone else { return }
        let gain = boost(in: document)
        guard gain > 1.001 else { return }
        parameters.audioTapProcessor = makeTap(gain: Float(gain))
    }

    /// What the tap carries from one call to the next.
    private final class State {
        let gain: Float
        var isFloat = false
        init(gain: Float) { self.gain = gain }
    }

    static func makeTap(gain: Float) -> MTAudioProcessingTap? {
        let state = Unmanaged.passRetained(State(gain: gain))
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: state.toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<State>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let state = Unmanaged<State>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                state.isFloat = format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
                    && format.pointee.mBitsPerChannel == 32
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr
                else { return }
                let state = Unmanaged<State>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                guard state.isFloat else { return }
                for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = data.assumingMemoryBound(to: Float.self)
                    for index in 0..<count { samples[index] = ForkRecorderAudioBoost.shaped(samples[index], gain: state.gain) }
                }
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                         kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr
        else {
            state.release()
            return nil
        }
        return tap
    }
}
