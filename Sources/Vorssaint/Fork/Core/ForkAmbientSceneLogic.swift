// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The little animated scene the island shows for what plays
/// (`forkAmbientScenes`): one drawing per sound, a ready-made ambience shown
/// by its emblem, any other mix by its loudest sound. Pure: which sound the
/// scene shows, how wide it draws, and the timings the drawings share.
extension ForkAmbientLogic {
    /// The sound standing for each ready-made ambience.
    static func emblem(of preset: Preset) -> Sound {
        switch preset {
        case .focus: return .rain
        case .deepFocus: return .beta
        case .calm: return .ocean
        case .nature: return .forest
        case .storm: return .thunder
        case .lofi: return .chords
        }
    }

    /// The scene for `mix`: the ambience's emblem, else the loudest sound
    /// (the first in the list on a tie), nil when nothing plays.
    static func sceneSound(for mix: Mix) -> Sound? {
        if let preset = preset(for: mix) { return emblem(of: preset) }
        var best: (sound: Sound, level: Double)?
        for sound in Sound.allCases {
            guard let level = mix[sound], level > 0 else { continue }
            if best == nil || level > best!.level { best = (sound, level) }
        }
        return best?.sound
    }

    /// Every scene is drawn in a box this many points wide for one tall.
    static let sceneAspect: CGFloat = 1.3
    /// The drawings' own units, scaled to the box.
    static let sceneCanvas = CGSize(width: 26, height: 20)

    /// Its corners round by this share of its height, so it clears the
    /// island's curve as a box this round would.
    static let sceneCornerShare: CGFloat = 0.25

    static func sceneWidth(height: CGFloat) -> CGFloat { (max(0, height) * sceneAspect).rounded(.up) }

    /// Where `time` stands in a cycle of `period` seconds, from 0 up to 1.
    static func cycle(_ time: Double, period: Double, offset: Double = 0) -> Double {
        guard period > 0, time.isFinite else { return 0 }
        let value = (time / period + offset).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }

    /// The storm's lightning, from 0 (dark) to 1: a flash, a flicker, a
    /// second flash fading, then dark for most of each 3.4 s.
    static func lightning(_ time: Double) -> Double {
        let phase = cycle(time, period: 3.4)
        if phase < 0.05 { return 1 }
        if phase < 0.08 { return 0.25 }
        if phase < 0.13 { return 0.85 }
        if phase < 0.22 { return 0.85 * (1 - (phase - 0.13) / 0.09) }
        return 0
    }

    /// The little bird sings for most of each 3.2 s, then rests.
    static func birdSings(_ time: Double) -> Bool { cycle(time, period: 3.2) < 0.65 }

    /// The television's snow: a steady pseudo-random brightness for one dot
    /// in one frame, from 0 to 1.
    static func grain(column: Int, row: Int, frame: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: column &* 73_856_093 ^ row &* 19_349_663 ^ frame &* 83_492_791)
        x ^= x >> 13
        x = x &* 0x5bd1_e995
        x ^= x >> 15
        return Double(x % 1000) / 999
    }

    /// Fades a moving piece in and out over its trip: 0 at both ends, 1 midway.
    static func trip(_ phase: Double) -> Double { max(0, sin(min(1, max(0, phase)) * .pi)) }
}
