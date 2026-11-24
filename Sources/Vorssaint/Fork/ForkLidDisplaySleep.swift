// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import IOKit
import os

/// Puts every display to sleep, the external ones included, a few seconds
/// after the lid closes while Keep Awake's closed-lid mode runs. The Mac keeps
/// working; the displays come back when the lid opens, or on a key press or a
/// mouse move.
///
/// The lid is watched the way upstream's `KeepAwakeManager` watches it for
/// its own dimming: a general-interest notification on `IOPMrootDomain`,
/// which fires on far more than the lid, so the lid itself is read each time
/// and compared with the last reading. The notification exists only while
/// the closed-lid mode is in effect and the setting is on.
final class ForkLidDisplaySleep {
    typealias Logic = ForkLidDisplaySleepLogic

    static let shared = ForkLidDisplaySleep()

    private var notificationPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var watch = Logic.LidWatch()
    /// Bumped on every lid change and when the watch stops, so a pending
    /// sleep from an earlier closing finds it moved on and does nothing.
    private var generation = 0
    /// The displays were put to sleep since the lid last closed.
    private var slept = false
    private var observers: [NSObjectProtocol] = []
    private var clamshellObservation: AnyCancellable?
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }
    /// What happened, for `log show --predicate 'category == "lid-displays"'`.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "lid-displays")
    private let queue = DispatchQueue(label: "lid-displays", qos: .utility)

    private init() {}

    func start() {
        resync.schedule()
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resync.schedule()
        })
        // `@Published` sends before the value changes; the coalesced sync
        // reads it on the next turn of the run loop, once it has.
        clamshellObservation = KeepAwakeManager.shared.$clamshellActive.sink { [weak self] _ in
            self?.resync.schedule()
        }
    }

    /// Asked by Keep Awake before each pointer nudge: none while the displays
    /// sleep with the lid shut, since a mouse move would light them up again.
    var holdsDisplaysAsleep: Bool {
        guard slept else { return false }
        return Logic.holdsDisplaysAsleep(slept: slept, lidClosed: BrightnessService.lidClosed())
    }

    private var armed: Bool {
        Logic.isArmed(enabled: UserDefaults.standard.bool(forKey: DefaultsKey.forkLidSleepsDisplays),
                      clamshellActive: KeepAwakeManager.shared.clamshellActive,
                      featureAvailable: AppFeature.keepAwake.isAvailable)
    }

    private func sync() {
        if armed { startWatching() } else { stopWatching() }
    }

    private func startWatching() {
        guard notificationPort == nil else { return }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let result = IOServiceAddInterestNotification(
            port, root, kIOGeneralInterest, { context, _, _, _ in
                guard let context else { return }
                let owner = Unmanaged<ForkLidDisplaySleep>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in owner?.lidMayHaveChanged() }
            }, Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            log.error("could not watch the lid: \(result)")
            return
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        // The lid as it is now. A lid already shut is not a closing: the
        // external display in use stays on.
        watch = Logic.LidWatch()
        _ = watch.read(BrightnessService.lidClosed())
        log.log("watching the lid")
    }

    private func stopWatching() {
        generation &+= 1
        slept = false
        guard notificationPort != nil else { return }
        if notification != 0 { IOObjectRelease(notification) }
        notification = 0
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        notificationPort = nil
        watch = Logic.LidWatch()
        log.log("stopped watching the lid")
    }

    /// The armed check also catches a callback queued just before the watch
    /// stopped: it lands here and does nothing.
    private func lidMayHaveChanged() {
        guard notificationPort != nil, armed else { return }
        switch watch.read(BrightnessService.lidClosed()) {
        case .closed:
            generation &+= 1
            let scheduled = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Logic.settleDelay) { [weak self] in
                self?.sleepDisplays(scheduled)
            }
        case .opened:
            generation &+= 1
            if slept { log.log("lid opened, the displays wake") }
            slept = false
        case .none:
            break
        }
    }

    private func sleepDisplays(_ scheduled: Int) {
        guard Logic.shouldSleep(scheduled: scheduled, current: generation, armed: armed,
                                lidClosed: BrightnessService.lidClosed()) else { return }
        slept = true
        log.log("lid closed, putting the displays to sleep")
        let log = log
        queue.async {
            let result = BoundedProcessRunner.run(Logic.pmsetPath, Logic.pmsetArguments,
                                                  timeout: 5, maxOutputBytes: 4096)
            if result.timedOut || result.status != 0 {
                log.error("pmset displaysleepnow failed: status \(result.status), timed out \(result.timedOut)")
            }
        }
    }
}
