// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Swish's double tap: two fingers set down and lifted quickly, twice in a
/// row, without sliding. Fed with the trackpad's contact frames (finger count
/// and their center, from 0 to 1 on each axis).
struct ForkSwishTapRecognizer {
    /// The longest a tap's fingers stay down.
    static let tapDuration: TimeInterval = 0.25
    /// The longest wait between the first tap's lift and the second's touch.
    static let gap: TimeInterval = 0.35
    /// How far the fingers may slide during a tap, as a share of the trackpad.
    static let drift: Float = 0.03

    private var touchStart: TimeInterval?
    private var maxFingers = 0
    private var startCenter: (x: Float, y: Float)?
    private var slid = false
    private var lastTapEnd: TimeInterval?

    /// One contact frame. True when it completes a double tap.
    mutating func feed(fingers: Int, center: (x: Float, y: Float)?, at time: TimeInterval) -> Bool {
        if fingers > 0 {
            if touchStart == nil {
                touchStart = time
                maxFingers = fingers
                startCenter = center
                slid = false
            }
            maxFingers = max(maxFingers, fingers)
            if let start = startCenter, let center, hypot(center.x - start.x, center.y - start.y) > Self.drift {
                slid = true
            }
            return false
        }
        guard let start = touchStart else { return false }
        touchStart = nil
        let isTap = maxFingers == 2 && !slid && time - start <= Self.tapDuration
        guard isTap else {
            lastTapEnd = nil
            return false
        }
        if let previous = lastTapEnd, start - previous <= Self.gap {
            lastTapEnd = nil
            return true
        }
        lastTapEnd = time
        return false
    }
}
