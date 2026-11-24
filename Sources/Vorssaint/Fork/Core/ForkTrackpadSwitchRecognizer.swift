// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Three or four fingers (as set) swiped sideways on the trackpad open the
/// window switcher and move through it; lifting the fingers picks the window,
/// as Swish does.
/// Fed the trackpad's raw frames (how many fingers, where their centre is,
/// from 0 to 1 across the pad), it says when to open, step and pick. Pure.
struct ForkTrackpadSwitchRecognizer: Equatable {
    enum Output: Equatable {
        case begin(reversed: Bool)
        case step(Int)
        case commit
        case cancel
    }

    /// Sideways travel, as a share of the pad's width, before the switcher opens.
    static let startDistance: Float = 0.06
    /// Further travel for each step through the windows.
    static let stepDistance: Float = 0.07

    private enum State: Equatable {
        case idle
        case watching(startX: Float, startY: Float)
        case switching(lastX: Float)
        /// Fingers went a way that is not this gesture: nothing until the pad is empty.
        case ignoring
    }

    private var state = State.idle
    /// How many fingers the gesture takes: 3 or 4.
    let fingers: Int

    init(fingers: Int = 3) {
        self.fingers = fingers == 4 ? 4 : 3
    }

    /// One frame from the trackpad. `center` is nil when the touches could not be read.
    mutating func feed(fingers count: Int, center: (x: Float, y: Float)?) -> [Output] {
        switch state {
        case .idle:
            guard count == fingers, let center else { return [] }
            state = .watching(startX: center.x, startY: center.y)
            return []
        case let .watching(startX, startY):
            if count == 0 || count < fingers && count > 0 {
                state = count == 0 ? .idle : .ignoring
                return []
            }
            if count > fingers {
                state = .ignoring
                return []
            }
            guard let center else { return [] }
            let dx = center.x - startX, dy = center.y - startY
            if abs(dy) > Self.startDistance && abs(dy) > abs(dx) {
                state = .ignoring
                return []
            }
            guard abs(dx) >= Self.startDistance else { return [] }
            state = .switching(lastX: center.x)
            return [.begin(reversed: dx < 0)]
        case let .switching(lastX):
            if count == 0 {
                state = .idle
                return [.commit]
            }
            if count > fingers {
                state = .ignoring
                return [.cancel]
            }
            // One or two fingers left on the pad while lifting: wait for the last.
            guard count == fingers, let center else { return [] }
            let travel = center.x - lastX
            let steps = Int(travel / Self.stepDistance)
            guard steps != 0 else { return [] }
            state = .switching(lastX: lastX + Float(steps) * Self.stepDistance)
            return Array(repeating: .step(steps > 0 ? 1 : -1), count: abs(steps))
        case .ignoring:
            if count == 0 { state = .idle }
            return []
        }
    }

    /// Whether macOS already uses a sideways swipe with this many fingers
    /// (moving between full-screen apps), read from the trackpad's settings:
    /// then the gesture is left to macOS. Any value other than 0 means it does.
    static func systemUsesThreeFingerSwipe(_ values: [Int?]) -> Bool {
        values.contains { ($0 ?? 0) != 0 }
    }

    /// The trackpad setting that says whether macOS takes the sideways swipe
    /// with this many fingers.
    static func systemSettingKey(fingers: Int) -> String {
        fingers == 4 ? "TrackpadFourFingerHorizSwipeGesture" : "TrackpadThreeFingerHorizSwipeGesture"
    }
}
