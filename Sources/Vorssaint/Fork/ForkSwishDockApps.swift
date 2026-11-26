// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices

/// The app behind a Dock icon, and what Swish's Dock gestures do to it, all
/// through Accessibility: called off the event taps' path.
enum ForkSwishDockApps {
    /// Where the Dock sits, from its own preferences: "bottom", "left" or
    /// "right". Read again at most every few seconds: it is asked at the start
    /// of every scroll that does not begin on a title bar.
    static var orientation: String? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - orientationReadAt > 5 {
            cachedOrientation = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String
            orientationReadAt = now
        }
        return cachedOrientation
    }

    private static var cachedOrientation: String?
    private static var orientationReadAt: TimeInterval = -.infinity

    /// Whether a point (window-list coordinates, top-left origin) lies along
    /// the Dock's edge of the display under it, with the Dock on screen there:
    /// a hidden Dock leaves the bottom of the windows to them. `windows` is
    /// the on-screen window list already read for this gesture.
    static func isNearDock(_ point: CGPoint, windows: [[String: Any]]) -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              ForkSwishDock.isShowing(at: point, in: windows, dockPID: dock.processIdentifier)
        else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        let orientation = self.orientation
        return NSScreen.screens.contains { ForkSwishDock.isInBand(appKitPoint, screen: $0.frame, orientation: orientation) }
    }

    /// The running app whose Dock icon is at the point, if any.
    static func application(at point: CGPoint) -> NSRunningApplication? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.35)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit
        else { return nil }
        // The hit can land on the icon's label or badge: climb to the tile.
        for _ in 0..<3 {
            if string(element, kAXSubroleAttribute) == "AXApplicationDockItem" {
                if case .instance(let app) = DockTileResolver.resolution(forTile: element) { return app }
                return nil
            }
            guard let parent = child(element, kAXParentAttribute) else { return nil }
            element = parent
        }
        return nil
    }

    /// What the app behind the icon at the point has, or nil when no running
    /// app's icon is there.
    static func state(at point: CGPoint) -> ForkSwishDock.AppState? {
        guard let app = application(at: point) else { return nil }
        let all = windows(of: app)
        let minimized = all.filter(isMinimized).count
        return ForkSwishDock.AppState(open: all.count - minimized, minimized: minimized,
                                      onScreen: onScreenWindowIDs(of: app.processIdentifier).count, active: app.isActive)
    }

    static func perform(_ gesture: ForkSwishDock.Gesture, on app: NSRunningApplication) {
        switch gesture {
        case .quit:
            ForkSwishWindowOps.quitApp(pid: app.processIdentifier)
        case .minimize(let all):
            let open = windows(of: app).filter { !isMinimized($0) }
            for window in all ? open : Array(open.prefix(1)) { ForkSwishWindowOps.minimize(window) }
        case .unminimize(let all):
            let minimized = windows(of: app).filter(isMinimized)
            for window in all ? minimized : Array(minimized.suffix(1)) {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            if !minimized.isEmpty { app.activate() }
        case .cycle(let forward):
            let ids = onScreenWindowIDs(of: app.processIdentifier)
            // An app in the background first comes forward with its front window.
            let target = app.isActive ? ForkSwishDock.cycleTarget(ids, forward: forward) : ids.first
            if let target {
                _ = WindowActivator.focusWindow(windowID: CGWindowID(target), pid: app.processIdentifier)
            }
        }
    }

    /// The app's standard windows, front to back, as Accessibility lists them.
    private static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }
        return windows.filter { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole as String }
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
            && (value as? Bool) == true
    }

    /// The app's ordinary windows on screen, front to back, from the window list.
    private static func onScreenWindowIDs(of pid: pid_t) -> [UInt32] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let number = info[kCGWindowNumber as String] as? Int
            else { return nil }
            return UInt32(number)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}
