// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The background sounds made of tones and events (see `ForkAmbientSynth`):
/// binaural beats and a 40 Hz pulse, birds over leaves, a babbling stream,
/// distant thunder, slow lo-fi chords, a deep drone and singing bowls, plus
/// the soft chime that marks Pomodoro's phases. All synthesised, no
/// recording. Arrays are made once; nothing allocates while sounding.
struct ForkAmbientTone {
    typealias Sound = ForkAmbientLogic.Sound

    var random: ForkAmbientSynth.Random
    var phases = [Double](repeating: 0, count: 12)
    var envelopes = [Float](repeating: 0, count: 6)
    var decays = [Float](repeating: 0, count: 6)
    var frequencies = [Double](repeating: 0, count: 6)
    var glides = [Double](repeating: 1, count: 6)
    var slot = 0
    var countdown = 0
    var clock: Double = 0
    var eventLeft = 0
    var eventLength = 1
    var chirpStart: Double = 0
    var chirpEnd: Double = 0
    var pan: Float = 0.5
    var low: Float = 0
    var band: Float = 0
    var deep: Float = 0

    init(seed: UInt64) { random = ForkAmbientSynth.Random(seed: seed) }

    static let twoPi = 2 * Double.pi

    /// Am7, Fmaj7, C, G: four notes each, eight seconds per chord.
    static let chordNotes: [Double] = [220.00, 261.63, 329.63, 392.00,
                                       174.61, 220.00, 261.63, 329.63,
                                       130.81, 196.00, 261.63, 329.63,
                                       196.00, 246.94, 293.66, 392.00]
    static let chordLength: Double = 8

    /// A bowl's partials: inharmonic, the higher ones dying first.
    static let bowlRatios: [Double] = [1, 2.76, 5.40]
    static let bowlDecays: [Double] = [9, 5, 2.5]
    static let bowlAmplitudes: [Float] = [0.5, 0.25, 0.12]
    static let bowlNotes: [Double] = [196.00, 220.00, 261.63, 329.63]

    @inline(__always)
    static func oscillate(_ phase: inout Double, _ frequency: Double, _ rate: Double) -> Float {
        phase += frequency / rate
        if phase >= 1 { phase -= phase.rounded(.down) }
        return Float(sin(twoPi * phase))
    }

    static func sample(_ sound: Sound, tone t: inout ForkAmbientTone, sampleRate r: Double) -> (Float, Float) {
        switch sound {
        case .alpha: return binaural(&t, carrier: 200, beat: 10, r)
        case .beta: return binaural(&t, carrier: 220, beat: 18, r)
        case .gamma: return gamma(&t, r)
        case .chords: return chords(&t, r)
        case .drone: return drone(&t, r)
        case .bowls: return bowls(&t, r)
        case .forest: return forest(&t, r)
        case .stream: return stream(&t, r)
        case .thunder: return thunder(&t, r)
        default: return (0, 0)
        }
    }

    /// A tone in each ear, a few hertz apart: the brain hears the difference
    /// as a slow beat (10 Hz alpha, calm; 18 Hz beta, attention).
    static func binaural(_ t: inout ForkAmbientTone, carrier: Double, beat: Double, _ r: Double) -> (Float, Float) {
        (oscillate(&t.phases[0], carrier, r) * 0.22, oscillate(&t.phases[1], carrier + beat, r) * 0.22)
    }

    /// A soft tone pulsing forty times a second, the same in both ears:
    /// heard without headphones too.
    static func gamma(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        let carrier = oscillate(&t.phases[0], 330, r)
        let gate = 0.5 + 0.5 * oscillate(&t.phases[1], 40, r)
        let value = carrier * gate * gate * 0.3
        return (value, value)
    }

    /// Four warm notes per chord, fading in and out, spread left and right.
    static func chords(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        t.clock += 1 / r
        let chord = Int(t.clock / chordLength) % 4
        let local = t.clock.truncatingRemainder(dividingBy: chordLength)
        let envelope = Float(min(1, local / 1.8) * min(1, (chordLength - local) / 1.6))
        var left: Float = 0
        var right: Float = 0
        for note in 0..<4 {
            let vibrato = 1 + 0.002 * sin(twoPi * (t.clock * 0.3 + Double(note) * 0.25))
            let frequency = chordNotes[chord * 4 + note] * vibrato
            let value = oscillate(&t.phases[note], frequency, r) + 0.3 * oscillate(&t.phases[4 + note], frequency * 2, r)
            let side: Float = note % 2 == 0 ? 0.35 : 0.65
            left += value * (1 - side)
            right += value * side
        }
        let gain = envelope * 0.12
        return (left * gain, right * gain)
    }

    /// A low A with its fifth and octave, slightly detuned so it slowly breathes.
    static func drone(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        t.clock += 1 / r
        let swell = Float(0.75 + 0.25 * sin(twoPi * t.clock * 0.07))
        let root = oscillate(&t.phases[0], 55, r) + oscillate(&t.phases[1], 55.18, r)
        let fifth = 0.6 * oscillate(&t.phases[2], 82.5, r) + 0.6 * oscillate(&t.phases[3], 82.71, r)
        let octave = 0.4 * oscillate(&t.phases[4], 110, r) + 0.2 * oscillate(&t.phases[5], 165.1, r)
        let gain = 0.12 * swell
        return ((root + fifth * 0.9 + octave) * gain, (root * 0.9 + fifth + octave) * gain)
    }

    /// Starts a bowl ringing in one of two slots, so a new strike lets the last one fade.
    static func strike(_ t: inout ForkAmbientTone, fundamental: Double, loudness: Float, decayScale: Double, _ r: Double) {
        t.slot = (t.slot + 1) % 2
        for partial in 0..<3 {
            let index = t.slot * 3 + partial
            t.frequencies[index] = fundamental * bowlRatios[partial]
            t.envelopes[index] = bowlAmplitudes[partial] * loudness
            t.decays[index] = Float(exp(-1 / (bowlDecays[partial] * decayScale * r)))
        }
    }

    static func ring(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0
        for index in 0..<6 where t.envelopes[index] > 0.0001 {
            let value = oscillate(&t.phases[index], t.frequencies[index], r)
                + 0.5 * oscillate(&t.phases[6 + index], t.frequencies[index] * 1.003, r)
            let level = value * t.envelopes[index]
            t.envelopes[index] *= t.decays[index]
            if index < 3 { left += level * 0.65; right += level * 0.35 } else { left += level * 0.35; right += level * 0.65 }
        }
        return (left, right)
    }

    /// A bowl struck every ten to eighteen seconds, ringing long.
    static func bowls(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        if t.countdown <= 0 {
            let note = bowlNotes[Int(t.random.unit() * Float(bowlNotes.count)) % bowlNotes.count]
            strike(&t, fundamental: note, loudness: 1, decayScale: 1, r)
            t.countdown = Int(r * (10 + Double(t.random.unit()) * 8))
        }
        t.countdown -= 1
        let sound = ring(&t, r)
        return (sound.0 * 0.35, sound.1 * 0.35)
    }

    /// Pomodoro's chime: a small bright bowl, short.
    static func chime(_ t: inout ForkAmbientTone, _ r: Double) {
        strike(&t, fundamental: 523.25, loudness: 0.9, decayScale: 0.3, r)
    }

    /// Leaves rustling, and birds: short gliding chirps in little phrases,
    /// each phrase from its own place left or right.
    static func forest(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        let noise = t.random.signed()
        t.low += (noise - t.low) * 0.08
        let rustle = (noise - t.low) * 0.03
        if t.eventLeft <= 0 {
            if t.countdown <= 0 {
                t.eventLength = max(1, Int(r * (0.06 + Double(t.random.unit()) * 0.14)))
                t.eventLeft = t.eventLength
                t.chirpStart = 2500 + Double(t.random.unit()) * 2500
                t.chirpEnd = t.chirpStart * (0.6 + Double(t.random.unit()))
                if t.random.unit() < 0.6 {
                    t.countdown = Int(r * (0.04 + Double(t.random.unit()) * 0.06))
                } else {
                    t.countdown = Int(r * (0.8 + Double(t.random.unit()) * 2.5))
                    t.pan = t.random.unit()
                }
            } else {
                t.countdown -= 1
            }
        }
        var chirp: Float = 0
        if t.eventLeft > 0 {
            let progress = 1 - Double(t.eventLeft) / Double(t.eventLength)
            let frequency = t.chirpStart + (t.chirpEnd - t.chirpStart) * progress
            let flutter = 1 + 0.03 * Double(oscillate(&t.phases[1], 30, r))
            let envelope = Float(sin(Double.pi * progress))
            chirp = oscillate(&t.phases[0], frequency * flutter, r) * envelope * envelope * 0.22
            t.eventLeft -= 1
        }
        return (rustle + chirp * (1 - t.pan), rustle + chirp * t.pan)
    }

    /// Water over stones: a band of noise and many small rising bubbles.
    static func stream(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        let noise = t.random.signed()
        let f = Float(2 * sin(Double.pi * 900 / r))
        t.low += f * t.band
        let high = noise - t.low - 0.7 * t.band
        t.band += f * high
        var left = t.band * 0.18
        var right = left
        if t.random.unit() < Float(35 / r) {
            t.slot = (t.slot + 1) % 6
            t.frequencies[t.slot] = 500 + Double(t.random.unit()) * 900
            t.envelopes[t.slot] = 0.08 + t.random.unit() * 0.12
            t.decays[t.slot] = Float(exp(-1 / (0.025 * r)))
            t.glides[t.slot] = pow(1.6, 1 / (0.025 * r))
        }
        for index in 0..<6 where t.envelopes[index] > 0.0005 {
            t.frequencies[index] *= t.glides[index]
            let bubble = oscillate(&t.phases[index], t.frequencies[index], r) * t.envelopes[index]
            t.envelopes[index] *= t.decays[index]
            if index % 2 == 0 { left += bubble * 0.7; right += bubble * 0.3 } else { left += bubble * 0.3; right += bubble * 0.7 }
        }
        return (left, right)
    }

    /// A low rumble far away, and every twelve to thirty-five seconds a
    /// roll of thunder swelling and dying over a few seconds.
    static func thunder(_ t: inout ForkAmbientTone, _ r: Double) -> (Float, Float) {
        let noise = t.random.signed()
        t.deep = (t.deep + 0.02 * noise) / 1.02
        t.low += (t.deep * 3.5 - t.low) * 0.01
        if t.countdown <= 0 {
            t.eventLength = Int(r * 6)
            t.eventLeft = t.eventLength
            t.countdown = Int(r * (12 + Double(t.random.unit()) * 23))
        }
        t.countdown -= 1
        var envelope: Float = 0.12
        var crack: Float = 0
        if t.eventLeft > 0 {
            let seconds = Double(t.eventLength - t.eventLeft) / r
            let roll = min(1, seconds / 0.35) * exp(-seconds / 1.8)
            envelope += Float(roll) * 1.2
            if seconds < 0.4 { crack = noise * Float(roll) * 0.12 }
            t.eventLeft -= 1
        }
        let value = t.low * envelope + crack
        return (value, value * 0.95)
    }
}
