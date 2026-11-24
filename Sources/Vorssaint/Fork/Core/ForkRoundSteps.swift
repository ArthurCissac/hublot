// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Volume and brightness keys in steps of 5 %, landing on round values: from
/// 63 % a press up gives 65 %, then 70 %, and a press down gives 60 %. It only
/// replaces the system's full step (a sixteenth): finer steps, such as the
/// quarter step taken with Option-Shift, are left as they are.
enum ForkRoundSteps {
    /// One press, as a share of the full range.
    static let step = 0.05

    /// The system's full key step, the one these round steps replace.
    static let systemStep = 1.0 / 16

    /// A level read back slightly off a round value (0.6499 for 65 %) still
    /// counts as that value: 0.1 % of the range, a fiftieth of a step.
    static let tolerance = 0.02

    /// The next multiple of 5 % from `current` (0...1) in `direction`.
    static func next(from current: Double, direction: Int) -> Double {
        let level = current.isFinite ? min(max(current, 0), 1) : 0
        guard direction != 0 else { return level }
        let position = level / step
        let index = direction > 0
            ? (position + tolerance).rounded(.down) + 1
            : (position - tolerance).rounded(.up) - 1
        // Rounded to the percent, so 13 × 0.05 is stored as 0.65, not 0.6500000001.
        return min(max((index * step * 100).rounded() / 100, 0), 1)
    }

    /// The level after a key change of `delta`, or nil when round steps do not
    /// apply: switched off, or a change finer than the system's full step.
    /// Several presses queued together (a delta of two sixteenths) take as
    /// many round steps.
    static func level(current: Double, delta: Double, enabled: Bool) -> Double? {
        guard enabled, current.isFinite, delta.isFinite, abs(delta) >= systemStep * 0.99 else { return nil }
        let presses = max(1, Int((abs(delta) / systemStep).rounded()))
        var level = current
        for _ in 0..<presses { level = next(from: level, direction: delta > 0 ? 1 : -1) }
        return level
    }

    /// The volume after one key press, or nil to keep the island's own step.
    static func volumeLevel(current: Double, direction: Int, fine: Bool,
                            defaults: UserDefaults = .standard) -> Double? {
        guard !fine, direction != 0 else { return nil }
        return level(current: current, delta: Double(direction.signum()) * systemStep,
                     enabled: defaults.bool(forKey: DefaultsKey.forkVolumeRoundSteps))
    }

    /// The brightness after a key change of `delta`, or nil to keep the usual step.
    static func brightness(_ current: Double, delta: Double, defaults: UserDefaults = .standard) -> Double? {
        level(current: current, delta: delta, enabled: defaults.bool(forKey: DefaultsKey.forkBrightnessRoundSteps))
    }
}
