// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The background sounds, made sample by sample from noise: coloured noises
/// filtered from white noise, rain from hiss and droplets, the ocean from
/// deep noise swelling in waves, wind from noise through a wandering
/// resonant filter, a fire from a low rumble and crackles. No recording is
/// used. Safe for the audio thread: no allocation and no lock once made.
struct ForkAmbientSynth {
    typealias Sound = ForkAmbientLogic.Sound

    /// A small, fast random source (xorshift).
    struct Random {
        private var state: UInt64

        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

        mutating func unit() -> Float {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(state >> 40) / Float(1 << 24)
        }

        /// From -1 to 1.
        mutating func signed() -> Float { unit() * 2 - 1 }
    }

    /// One channel of one sound, with all the state its filters keep.
    struct Channel {
        var random: Random
        var pink: (Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0)
        var brown: Float = 0
        var drop: Float = 0
        var dropTone: Float = 0
        var low: Float = 0
        var band: Float = 0
        var crackle: Float = 0
        var previous: Float = 0

        init(seed: UInt64) { random = Random(seed: seed) }

        mutating func white() -> Float { random.signed() }

        /// Paul Kellet's pink filter: equal energy per octave.
        mutating func pinkNoise() -> Float {
            let w = white()
            pink.0 = 0.99886 * pink.0 + w * 0.0555179
            pink.1 = 0.99332 * pink.1 + w * 0.0750759
            pink.2 = 0.96900 * pink.2 + w * 0.1538520
            pink.3 = 0.86650 * pink.3 + w * 0.3104856
            pink.4 = 0.55000 * pink.4 + w * 0.5329522
            pink.5 = -0.7616 * pink.5 - w * 0.0168980
            let out = pink.0 + pink.1 + pink.2 + pink.3 + pink.4 + pink.5 + pink.6 + w * 0.5362
            pink.6 = w * 0.115926
            return out * 0.11
        }

        /// Integrated white noise with a leak: deep, like distant surf.
        mutating func brownNoise() -> Float {
            brown = (brown + 0.02 * white()) / 1.02
            return brown * 3.5
        }
    }

    /// Slow movements shared by both channels: waves, gusts.
    struct Motion {
        var wave: Double = 0
        var waveLength: Double = 8
        var gust: Float = 0.5
        var gustTarget: Float = 0.5
        var countdown = 0
    }

    let sampleRate: Double
    /// The sounds, kept once: reading `allCases` builds a new array each time.
    private let sounds = Sound.allCases
    /// Which sounds are made of tones (ForkAmbientTone), kept once too.
    private let tonal = Sound.allCases.map(\.isTonal)
    private var left: [Channel]
    private var right: [Channel]
    private var tones: [ForkAmbientTone]
    /// Pomodoro's chime, heard whatever the volume of the mix.
    private var bell = ForkAmbientTone(seed: 77)
    private var motion = Motion()
    private var shared = Random(seed: 0xA5A5_1234)
    /// Each sound's level now and where it is going, gliding to avoid clicks.
    private var levels: [Float]
    private var targets: [Float]
    private var master: Float = 0
    private var masterTarget: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let count = Sound.allCases.count
        left = (0..<count).map { Channel(seed: UInt64(1_000 + $0 * 7)) }
        right = (0..<count).map { Channel(seed: UInt64(9_000 + $0 * 13)) }
        tones = (0..<count).map { ForkAmbientTone(seed: UInt64(5_000 + $0 * 31)) }
        levels = Array(repeating: 0, count: count)
        targets = Array(repeating: 0, count: count)
    }

    mutating func setLevel(_ level: Double, for sound: Sound) {
        guard let index = sounds.firstIndex(of: sound) else { return }
        targets[index] = Float(min(1, max(0, level)))
    }

    mutating func setMaster(_ level: Double) {
        masterTarget = Float(min(1, max(0, level)))
    }

    var isSilent: Bool { master < 0.0001 && masterTarget == 0 }

    /// Rings the chime once.
    mutating func ringChime() {
        ForkAmbientTone.chime(&bell, sampleRate)
    }

    /// Fills both channels with `frames` samples.
    mutating func render(left out0: UnsafeMutablePointer<Float>, right out1: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let sample = next()
            out0[frame] = sample.0
            out1[frame] = sample.1
        }
    }

    /// One stereo sample of the whole mix.
    mutating func next() -> (Float, Float) {
        advanceMotion()
        master += (masterTarget - master) * 0.0004
        var sumLeft: Float = 0
        var sumRight: Float = 0
        // Silent and staying so (a pause, a Pomodoro break): nothing to make.
        let quiet = master < 0.00001 && masterTarget == 0
        for index in 0..<levels.count {
            levels[index] += (targets[index] - levels[index]) * 0.0004
            let level = levels[index]
            guard !quiet, level > 0.0001 else { continue }
            let sound = sounds[index]
            if tonal[index] {
                let value = ForkAmbientTone.sample(sound, tone: &tones[index], sampleRate: sampleRate)
                sumLeft += level * value.0
                sumRight += level * value.1
                continue
            }
            let motion = self.motion
            sumLeft += level * Self.sample(sound, channel: &left[index], motion: motion, sampleRate: sampleRate, phaseOffset: 0)
            sumRight += level * Self.sample(sound, channel: &right[index], motion: motion, sampleRate: sampleRate,
                                            phaseOffset: 0.03)
        }
        let chime = ForkAmbientTone.ring(&bell, sampleRate)
        // A soft ceiling instead of clipping when several sounds add up.
        return (Self.soften(sumLeft * master + chime.0 * 0.5), Self.soften(sumRight * master + chime.1 * 0.5))
    }

    /// Stays within -1…1 however many sounds add up, gently.
    static func soften(_ value: Float) -> Float {
        tanh(value)
    }

    private mutating func advanceMotion() {
        motion.wave += 1 / (motion.waveLength * sampleRate)
        if motion.wave >= 1 {
            motion.wave -= 1
            // Every wave a little different, between 6 and 11 seconds.
            motion.waveLength = 6 + Double(shared.unit()) * 5
        }
        if motion.countdown <= 0 {
            motion.gustTarget = 0.25 + shared.unit() * 0.75
            motion.countdown = Int(sampleRate * (0.6 + Double(shared.unit()) * 1.4))
        }
        motion.countdown -= 1
        motion.gust += (motion.gustTarget - motion.gust) * 0.00002
    }

    private static func sample(_ sound: Sound, channel: inout Channel, motion: Motion, sampleRate: Double,
                               phaseOffset: Double) -> Float {
        switch sound {
        case .white:
            return channel.white() * 0.35
        case .pink:
            return channel.pinkNoise() * 1.1
        case .brown:
            return channel.brownNoise() * 0.9
        case .rain:
            // A soft hiss, and droplets: short bright ticks at random.
            let hiss = channel.pinkNoise() * 0.55
            if channel.random.unit() < Float(55 / sampleRate) {
                channel.drop = max(channel.drop, 0.25 + channel.random.unit() * 0.6)
            }
            channel.drop *= Float(exp(-1 / (0.003 * sampleRate)))
            let w = channel.white()
            let tick = (w - channel.dropTone) * channel.drop
            channel.dropTone = w
            return hiss + tick * 0.45
        case .ocean:
            // Deep noise swelling and ebbing with each wave, a brighter wash at its crest.
            let phase = (motion.wave + phaseOffset).truncatingRemainder(dividingBy: 1)
            let swell = Float(pow(0.5 - 0.5 * cos(2 * Double.pi * phase), 1.6))
            let envelope = 0.25 + 0.75 * swell
            return channel.brownNoise() * envelope * 1.0 + channel.pinkNoise() * swell * swell * 0.35
        case .wind:
            // Noise through a resonant filter whose centre wanders with the gusts.
            let centre = 250 + 650 * Double(motion.gust)
            let f = Float(2 * sin(Double.pi * centre / sampleRate))
            let input = channel.white()
            channel.low += f * channel.band
            let high = input - channel.low - 0.55 * channel.band
            channel.band += f * high
            return channel.band * (0.25 + motion.gust * 0.75) * 0.5
        case .fire:
            // A low rumble, and crackles: very short, sharp clicks.
            let rumble = channel.brownNoise() * 0.45
            if channel.random.unit() < Float(9 / sampleRate) {
                channel.crackle = max(channel.crackle, 0.3 + channel.random.unit() * 0.7)
            }
            channel.crackle *= Float(exp(-1 / (0.0015 * sampleRate)))
            let w = channel.white()
            let click = (w - channel.previous) * channel.crackle
            channel.previous = w
            return rumble + click * 0.7
        default:
            // Made of tones: see ForkAmbientTone.
            return 0
        }
    }
}
