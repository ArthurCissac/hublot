// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices
import os

/// Three fingers swiped down while Chrome is in front (see
/// `ForkChromeFullscreenLogic`). In full screen, typically a video: Chrome
/// leaves it and its tabs are back; the tab is remembered. Out of full
/// screen, in that window: the tab comes back and the video goes full screen
/// again, by the F key most players take.
///
/// The trackpad is read from MultitouchSupport, which only reports, as the
/// window switcher's swipe does: no event is held. Only while Chrome is in
/// front, the setting is on, and macOS leaves three fingers down free.
final class ForkChromeFullscreenSwipe {
    static let shared = ForkChromeFullscreenSwipe()
    typealias Logic = ForkChromeFullscreenLogic

    private let lock = NSLock()
    private var recognizer = Logic.DownSwipe()
    private var devices: [UnsafeMutableRawPointer] = []
    private var observers: [NSObjectProtocol] = []
    private var videoTab: Logic.VideoTab?
    /// Chrome's scripts block their thread until Chrome answers, or until the
    /// first-time permission prompt does: never the main thread.
    private let scripts = DispatchQueue(label: "agency.nexflow.hublot.chrome-fullscreen", qos: .userInitiated)
    /// What happened, for `log show --predicate 'category == "chrome-fullscreen"'`: no URLs, no titles.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "chrome-fullscreen")

    private init() {}

    func start() {
        DispatchQueue.main.async { [weak self] in self?.sync() }
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sync()
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.sync() })
        // A trackpad comes back from sleep without its callbacks: they are set again.
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopDevices()
            self?.sync()
        })
    }

    private static var systemTakesSwipe: Bool {
        let vertical = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
            .compactMap { UserDefaults(suiteName: $0)?.object(forKey: "TrackpadThreeFingerVertSwipeGesture") as? Int }
            .max()
        let appExpose = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "showAppExposeGestureEnabled") as? Bool
        return Logic.systemUsesThreeFingersDown(verticalSwipe: vertical, appExposeGesture: appExpose)
    }

    private var wanted: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.forkChromeFullscreenSwipe)
            && AppFeature.windowLayout.isAvailable && AXIsProcessTrusted()
            && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Logic.chromeBundleID
            && !Self.systemTakesSwipe
    }

    private func sync() {
        if wanted { startDevices() } else { stopDevices() }
    }

    private func startDevices() {
        guard devices.isEmpty, ForkMultitouch.available, let list = ForkMultitouch.deviceList() else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            ForkMultitouch.register(device, forkChromeFullscreenCallback)
            ForkMultitouch.start(device)
            devices.append(device)
        }
    }

    private func stopDevices() {
        for device in devices { ForkMultitouch.unregister(device, forkChromeFullscreenCallback) }
        devices.removeAll()
        lock.withLock { recognizer = Logic.DownSwipe() }
    }

    /// From MultitouchSupport's own thread: only arithmetic here, Chrome is handled on the main thread.
    fileprivate func frame(fingers: Int, touches: UnsafeMutableRawPointer?) {
        let center = ForkMultitouch.center(touches: touches, count: fingers)
        let fired = lock.withLock { recognizer.feed(fingers: fingers, center: center) }
        guard fired else { return }
        DispatchQueue.main.async { [weak self] in self?.swiped() }
    }

    // MARK: - Chrome

    private func swiped() {
        guard let chrome = NSWorkspace.shared.frontmostApplication,
              chrome.bundleIdentifier == Logic.chromeBundleID else { return }
        let application = AXUIElementCreateApplication(chrome.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let window = Self.element(application, kAXFocusedWindowAttribute) else { return }
        if Self.bool(window, "AXFullScreen") {
            leaveFullScreen(window, pid: chrome.processIdentifier)
        } else if let videoTab {
            comeBack(to: videoTab, pid: chrome.processIdentifier)
        }
    }

    /// The window leaves full screen at once, and a page's own full screen
    /// (a video) with it; the tab, still in front while Chrome animates, is
    /// then remembered.
    private func leaveFullScreen(_ window: AXUIElement, pid: pid_t) {
        if AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse) != .success {
            // Escape leaves a page's full screen when the window refuses.
            Self.press(keyCode: 53, pid: pid)
        }
        run(Logic.frontTabScript) { [weak self] reply in
            self?.videoTab = reply.flatMap(Logic.videoTab(fromReply:))
            self?.log.notice("left full screen, tab remembered: \(self?.videoTab != nil)")
        }
    }

    /// The remembered tab in front, then F once Chrome has shown it.
    private func comeBack(to tab: Logic.VideoTab, pid: pid_t) {
        videoTab = nil
        run(Logic.showTabScript(tab)) { [weak self] reply in
            guard reply == "ok" else {
                self?.log.notice("remembered tab gone")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Self.press(keyCode: 3, pid: pid)  // F
            }
            self?.log.notice("tab back, full screen asked")
        }
    }

    /// Runs one of Chrome's scripts off the main thread, with upstream's
    /// runner (the permission to drive Chrome is asked in this app's name),
    /// and answers on the main thread; nil when Chrome, or that permission, says no.
    private func run(_ source: String, completion: @escaping (String?) -> Void) {
        scripts.async { [weak self] in
            let result = AppleScriptRunner.runDetailed(source)
            DispatchQueue.main.async {
                if !result.ok {
                    self?.log.notice("Chrome script failed: \(result.errorNumber ?? 0, privacy: .public)")
                }
                completion(result.ok ? result.output : nil)
            }
        }
    }

    private static func press(keyCode: CGKeyCode, pid: pid_t) {
        guard CGPreflightPostEventAccess() else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = []
            event.postToPid(pid)
        }
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}

private func forkChromeFullscreenCallback(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?,
                                          _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    ForkChromeFullscreenSwipe.shared.frame(fingers: Int(count), touches: touches)
    return 0
}
