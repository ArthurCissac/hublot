// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Lot 9j: the Care window's animated backgrounds (`ForkCareHubBackdrop`).
/// Where the picture sits, how lively the motion is, and the clock that keeps
/// it smooth when a tool starts or stops working.
enum ForkCareMotionLogic {
    /// The pictures are 16:9.
    static let pictureAspect: CGFloat = 16.0 / 9.0

    /// The picture filling `size` without distortion, centred, cropped on the
    /// longer side. Points of the picture map through it.
    static func fillRect(aspect: CGFloat = pictureAspect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        if size.width / size.height > aspect {
            let height = size.width / aspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }
        let width = size.height * aspect
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
    }

    /// A point of the picture, given from 0 to 1 on each side, in the view.
    static func point(_ unit: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + unit.x * rect.width, y: rect.minY + unit.y * rect.height)
    }

    /// How lively the motion is: calm at rest, fully lively while the tool works.
    static func targetEnergy(working: Bool) -> Double { working ? 1 : 0.32 }

    /// One step of the energy towards its target: it eases in over about a
    /// second rather than jumping, so nothing leaps when work starts.
    static func eased(_ energy: Double, towards target: Double, elapsed: Double) -> Double {
        guard elapsed > 0 else { return energy }
        let step = 1 - exp(-elapsed / 0.6)
        return energy + (target - energy) * min(1, step)
    }

    /// The motion's own time: it runs faster with more energy, and never
    /// jumps, because each frame only adds what elapsed since the last.
    struct Clock {
        private(set) var phase: Double = 0
        private(set) var energy: Double = targetEnergy(working: false)
        private var last: Double?

        mutating func advance(to now: Double, working: Bool) {
            defer { last = now }
            guard let last else { return }
            // A frame after a long pause (window hidden) restarts calmly.
            let elapsed = min(max(now - last, 0), 0.25)
            energy = eased(energy, towards: targetEnergy(working: working), elapsed: elapsed)
            // About twice as fast while working as at rest.
            phase += elapsed * (0.2 + energy * 0.8) * 3
        }
    }

    /// Where the cleaning sweep is, from 0 (left edge) to 1 (right edge),
    /// or nil between two sweeps. A sweep crosses in `crossing` phase units.
    static func sweep(phase: Double, period: Double, crossing: Double) -> Double? {
        guard period > 0, crossing > 0 else { return nil }
        let local = phase.truncatingRemainder(dividingBy: period)
        return local < crossing ? local / crossing : nil
    }

    /// A stable pseudo-random number from 0 to 1 for a particle or a cell.
    static func noise(_ seed: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 31
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 29
        return Double(x % 10_000) / 10_000
    }
}
