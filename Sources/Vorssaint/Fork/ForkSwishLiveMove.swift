// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices

/// The window itself glides to where a swipe would put it, while the fingers
/// are still down: from one place to the next as the direction changes, and
/// back where it was if the gesture is called off.
///
/// Every Accessibility call happens on one serial queue, never on an event
/// tap's path: an app slow to answer only slows its own window. A newer glide
/// cuts the running one short at its next step.
final class ForkSwishLiveMove {
    static let shared = ForkSwishLiveMove()

    private let queue = DispatchQueue(label: "agency.nexflow.hublot.swish-glide", qos: .userInteractive)
    private let lock = NSLock()
    private var generation = 0
    // Touched on the queue only.
    private var element: AXUIElement?
    private var original: CGRect?
    private var current: CGRect?

    private func bump() -> Int {
        lock.withLock {
            generation += 1
            return generation
        }
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.withLock { generation == value }
    }

    /// A swipe starts on this window: reach it and note where it is.
    func begin(_ window: WindowServerWindowCandidate) {
        _ = bump()
        queue.async { [self] in
            let app = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            element = AXWindowResolver.element(for: window.windowID, in: app, pid: window.pid)
            original = element.flatMap(ForkSwishWindowOps.frame(of:))
            current = original
        }
    }

    /// Glides toward `target` (Accessibility coordinates), or back to where
    /// the window was when the swipe started when nil.
    func glide(to target: CGRect?) {
        let mine = bump()
        queue.async { [self] in
            guard let element, let start = current, let end = target ?? original, start != end else { return }
            let pause = useconds_t(ForkSwishMotion.glideDuration / Double(ForkSwishMotion.glideSteps) * 1_000_000)
            for frame in ForkSwishMotion.glide(from: start, to: end) {
                guard isCurrent(mine) else { return }
                ForkSwishWindowOps.setFrameQuickly(element, frame)
                current = frame
                usleep(pause)
            }
        }
    }

    /// The swipe is over. Unless `keep`, the window glides back first. `then`
    /// runs on the main thread once nothing moves the window any more, so the
    /// final layout is never overtaken by a late step.
    func finish(keep: Bool, then: @escaping () -> Void = {}) {
        if !keep { glide(to: nil) }
        queue.async { [self] in
            element = nil
            original = nil
            current = nil
            DispatchQueue.main.async(execute: then)
        }
    }
}
