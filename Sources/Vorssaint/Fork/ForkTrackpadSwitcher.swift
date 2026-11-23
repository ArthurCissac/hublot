// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// Opens upstream's window switcher with three fingers swiped sideways on
/// the trackpad, steps through it as the fingers travel, and picks the window
/// when they lift. No event tap: the trackpad's frames are read from
/// MultitouchSupport, which only reports and never holds an event, and only
/// while the setting is on and macOS leaves three-finger swipes free.
final class ForkTrackpadSwitcher {
    static let shared = ForkTrackpadSwitcher()

    private let lock = NSLock()
    private var recognizer = ForkTrackpadSwitchRecognizer()
    private var devices: [UnsafeMutableRawPointer] = []
    private var observers: [NSObjectProtocol] = []

    func start() {
        DispatchQueue.main.async { [weak self] in self?.sync() }
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sync()
            })
        }
        // A trackpad comes back from sleep without its callbacks: they are set again.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopDevices()
            self?.sync()
        })
    }

    /// macOS's own three-finger sideways swipe, on the built-in and on a Bluetooth trackpad.
    static var systemUsesThreeFingerSwipe: Bool {
        let key = "TrackpadThreeFingerHorizSwipeGesture"
        let values = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].map {
            UserDefaults(suiteName: $0)?.object(forKey: key) as? Int
        }
        return ForkTrackpadSwitchRecognizer.systemUsesThreeFingerSwipe(values)
    }

    private var wanted: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: DefaultsKey.forkSwitcherTrackpadGesture)
            && defaults.bool(forKey: DefaultsKey.switcherEnabled)
            && AppFeature.switcher.isAvailable && AXIsProcessTrusted()
            && !Self.systemUsesThreeFingerSwipe
    }

    func sync() {
        if wanted { startDevices() } else { stopDevices() }
    }

    private func startDevices() {
        guard devices.isEmpty, ForkMultitouch.available, let list = ForkMultitouch.deviceList() else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            ForkMultitouch.register(device, forkTrackpadSwitchCallback)
            ForkMultitouch.start(device)
            devices.append(device)
        }
    }

    private func stopDevices() {
        for device in devices {
            ForkMultitouch.unregister(device, forkTrackpadSwitchCallback)
        }
        devices.removeAll()
        lock.withLock { recognizer = ForkTrackpadSwitchRecognizer() }
    }

    /// From MultitouchSupport's own thread: only arithmetic here, the switcher is driven on the main thread.
    fileprivate func frame(fingers: Int, touches: UnsafeMutableRawPointer?) {
        let center = ForkMultitouch.center(touches: touches, count: fingers)
        let outputs = lock.withLock { recognizer.feed(fingers: fingers, center: center) }
        guard !outputs.isEmpty else { return }
        DispatchQueue.main.async {
            let switcher = AppSwitcher.shared
            for output in outputs {
                switch output {
                case .begin(let reversed): _ = switcher.forkBeginGestureSession(scope: .allApps, reversed: reversed)
                case .step(let delta): switcher.forkStep(delta)
                case .commit: switcher.forkCommit()
                case .cancel: switcher.forkCancel()
                }
            }
        }
    }
}

private func forkTrackpadSwitchCallback(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?,
                                        _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    ForkTrackpadSwitcher.shared.frame(fingers: Int(count), touches: touches)
    return 0
}

/// The fork's own bridge to MultitouchSupport, a copy of the one upstream's
/// middle click keeps private. Everything is optional: without the framework
/// or its symbols, `available` is false and the gesture stays off.
enum ForkMultitouch {
    typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private static let createListFn: CreateListFn? = symbol("MTDeviceCreateList")
    private static let registerFn: RegisterFn? = symbol("MTRegisterContactFrameCallback")
    private static let unregisterFn: RegisterFn? = symbol("MTUnregisterContactFrameCallback")
    private static let startFn: StartFn? = symbol("MTDeviceStart")

    static var available: Bool {
        createListFn != nil && registerFn != nil && unregisterFn != nil && startFn != nil
    }

    static func deviceList() -> CFArray? {
        guard let list = createListFn?()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { return nil }
        return list
    }

    static func register(_ device: UnsafeMutableRawPointer, _ callback: ContactCallback?) { registerFn?(device, callback) }
    /// Only this callback is taken off: the device keeps running for anyone else listening (upstream's middle click).
    static func unregister(_ device: UnsafeMutableRawPointer, _ callback: ContactCallback?) { unregisterFn?(device, callback) }
    static func start(_ device: UnsafeMutableRawPointer) { startFn?(device, 0) }

    /// The touch record layout every multitouch utility relies on: 96-byte
    /// stride, normalized position at offsets 32 and 36. A value out of range
    /// means the layout moved, and the frame reports no position.
    static func center(touches: UnsafeMutableRawPointer?, count: Int) -> (x: Float, y: Float)? {
        guard let touches, count > 0 else { return nil }
        var sumX: Float = 0, sumY: Float = 0
        for index in 0..<count {
            let base = touches.advanced(by: index * 96)
            let x = base.loadUnaligned(fromByteOffset: 32, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: 36, as: Float.self)
            guard x.isFinite, y.isFinite, x >= -0.2, x <= 1.2, y >= -0.2, y <= 1.2 else { return nil }
            sumX += x
            sumY += y
        }
        return (sumX / Float(count), sumY / Float(count))
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
