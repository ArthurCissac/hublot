// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// Swish's double tap: two fingers tapped twice on a window's title bar (or
/// anywhere in it, with the super modifier) center the window.
///
/// A tap carries no scroll or gesture event, so it is read from the trackpad's
/// contact frames, through the MultitouchSupport bridge the three-finger
/// switcher uses, with no event tap. The bridge is only open while the
/// feature is wanted, the window layout feature available and Accessibility
/// granted, and opened again after sleep, when trackpads come back.
final class ForkSwishDoubleTap {
    static let shared = ForkSwishDoubleTap()

    private let lock = NSLock()
    private var recognizer = ForkSwishTapRecognizer()
    private var devices: [UnsafeMutableRawPointer] = []
    private var observers: [NSObjectProtocol] = []

    func start() {
        DispatchQueue.main.async { [weak self] in self?.sync() }
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.sync() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            self?.stopDevices()
            self?.sync()
        })
    }

    private var wanted: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.forkSwishDoubleTap)
            && UserDefaults.standard.bool(forKey: DefaultsKey.forkTitleBarSwipe)
            && AppFeature.windowLayout.isAvailable && AXIsProcessTrusted()
    }

    func sync() {
        if wanted { startDevices() } else { stopDevices() }
    }

    private func startDevices() {
        guard devices.isEmpty, ForkMultitouch.available, let list = ForkMultitouch.deviceList() else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            ForkMultitouch.register(device, forkSwishDoubleTapCallback)
            ForkMultitouch.start(device)
            devices.append(device)
        }
    }

    private func stopDevices() {
        for device in devices { ForkMultitouch.unregister(device, forkSwishDoubleTapCallback) }
        devices.removeAll()
        lock.withLock { recognizer = ForkSwishTapRecognizer() }
    }

    /// One contact frame, on the bridge's own thread.
    fileprivate func frame(fingers: Int, touches: UnsafeMutableRawPointer?) {
        let center = ForkMultitouch.center(touches: touches, count: fingers)
        let now = ProcessInfo.processInfo.systemUptime
        guard lock.withLock({ recognizer.feed(fingers: fingers, center: center, at: now) }) else { return }
        DispatchQueue.main.async { ForkTitleBarGestures.shared.doubleTapped() }
    }
}

private func forkSwishDoubleTapCallback(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?,
                                        _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    ForkSwishDoubleTap.shared.frame(fingers: Int(count), touches: touches)
    return 0
}
