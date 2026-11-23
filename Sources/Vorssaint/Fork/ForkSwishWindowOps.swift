// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices

/// The few window operations Swish-style gestures and keys need beyond
/// upstream's layout actions, all through Accessibility. Called off any event
/// tap's path: each may wait on the app that owns the window.
enum ForkSwishWindowOps {
    typealias Direction = ForkTitleBarGestureLogic.Direction

    /// The frontmost app's focused window, unless that app is one the window
    /// layout settings leave alone.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, !isIgnored(app) else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    static func isIgnored(_ app: NSRunningApplication) -> Bool {
        WindowLayoutIgnoredApps.matches(bundleID: app.bundleIdentifier, executablePath: app.executableURL?.path,
                                        apps: WindowLayoutIgnoredApps.shared.apps)
    }

    static func minimize(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    /// The window's frame in Accessibility coordinates (top-left origin).
    static func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero, size = CGSize.zero
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let positionValue = value, AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let sizeValue = value, AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Size, then position, then size again: an app that clamps a window to
    /// its current display only accepts the new size once it is on the new one.
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// One step of a glide: position and size only, two calls instead of three.
    static func setFrameQuickly(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// The frame a gesture gives a window with this frame (window-list
    /// coordinates, top-left origin), in AppKit coordinates. Nil for a gesture
    /// that does not lay the window out (minimize, close).
    static func appKitTarget(of gesture: ForkTitleBarGestureLogic.Gesture, window frame: CGRect) -> CGRect? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flip = { (rect: CGRect) in ForkSwishDisplays.accessibilityRect(rect, primaryHeight: primaryHeight) }
        switch gesture {
        case .minimize, .close:
            return nil
        case .display(let direction):
            return destination(of: frame, toward: direction).map(flip)
        case .ninth(let column, let row):
            guard let area = visibleArea(holding: frame) else { return nil }
            return flip(ForkSwishDisplays.ninth(column: column, row: row, in: area))
        case .layout(let action):
            guard let area = visibleArea(holding: frame) else { return nil }
            if action == .fullScreen {
                return NSScreen.screens.first { flip($0.frame).intersects(frame) }?.frame ?? flip(area)
            }
            return WindowLayoutGeometry.rect(for: action, current: flip(frame), visibleFrame: flip(area),
                                             windowGap: WindowLayoutGaps.windowGap,
                                             screenGap: WindowLayoutGaps.screenGap,
                                             marginPercent: WindowLayoutMargin.percent).integral
        }
    }

    /// The visible areas of the displays, in Accessibility coordinates.
    static func visibleFrames() -> [CGRect] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { ForkSwishDisplays.accessibilityRect($0.visibleFrame, primaryHeight: primaryHeight) }
    }

    /// Sends the window to the display that lies `direction` from the one it
    /// is on. False when there is no display that way.
    @discardableResult
    static func moveToDisplay(_ window: AXUIElement, toward direction: Direction, pointerFollows: Bool) -> Bool {
        guard let current = frame(of: window), let destination = destination(of: current, toward: direction)
        else { return false }
        // Onto the other display first, at its size for now: an app keeps a
        // window within the display it is on, so a size bigger than that one
        // would be cut down before the move.
        setPosition(window, destination.origin)
        setFrame(window, destination)
        if pointerFollows { movePointer(onto: destination) }
        // An app that answers late (Electron) can still apply an older,
        // smaller size after the move: look again once it has settled.
        for delay in [0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let now = frame(of: window), !isClose(now, destination) else { return }
                setPosition(window, destination.origin)
                setFrame(window, destination)
            }
        }
        return true
    }

    private static func setPosition(_ window: AXUIElement, _ origin: CGPoint) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    /// Where a window with this frame lands on the display that lies
    /// `direction` from the one holding most of it: all of that display's
    /// visible area, as maximized (not full screen), whatever its size was.
    /// Accessibility coordinates.
    static func destination(of current: CGRect, toward direction: Direction) -> CGRect? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let displays = NSScreen.screens.map { ForkSwishDisplays.accessibilityRect($0.frame, primaryHeight: primaryHeight) }
        let visible = visibleFrames()
        // Accessibility's y grows downward: the frames are turned over before
        // asking for the neighbor.
        guard let source = displays.indices.max(by: { overlap(displays[$0], current) < overlap(displays[$1], current) }),
              overlap(displays[source], current) > 0
        else { return nil }
        let upward = displays.map(flipped)
        guard let target = ForkSwishDisplays.neighbor(of: upward[source], toward: direction, among: upward)
        else { return nil }
        return visible[target]
    }

    /// The visible area of the display holding most of a window, in
    /// Accessibility coordinates.
    static func visibleArea(holding current: CGRect) -> CGRect? {
        visibleFrames().max(by: { overlap($0, current) < overlap($1, current) })
    }

    /// Lays the window out in one cell of a 3×3 grid of the display it is on.
    static func placeNinth(_ window: AXUIElement, column: Int, row: Int, pointerFollows: Bool) {
        guard let current = frame(of: window), let area = visibleArea(holding: current) else { return }
        let destination = ForkSwishDisplays.ninth(column: column, row: row, in: area)
        setFrame(window, destination)
        if pointerFollows { movePointer(onto: destination) }
    }

    /// After a layout: the pointer back onto the window's title bar when the
    /// window moved out from under it, so the next gesture starts there.
    static func followWindow(_ window: AXUIElement) {
        guard let frame = frame(of: window), let pointer = CGEvent(source: nil)?.location else { return }
        let titleBar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(28, frame.height))
        if !titleBar.contains(pointer) { movePointer(onto: frame) }
    }

    /// The app behind a window quits, unless it is Finder or this app.
    static func quitApp(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != "com.apple.finder"
        else { return }
        app.terminate()
    }

    /// The pointer onto the window's title bar, where the next gesture starts.
    static func movePointer(onto frame: CGRect) {
        guard frame.width > 0 else { return }
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.minY + min(14, frame.height / 2)))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Accessibility frames turned upside down, for the neighbor search, which
    /// reasons with y growing upward.
    private static func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: -rect.maxY, width: rect.width, height: rect.height)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}
