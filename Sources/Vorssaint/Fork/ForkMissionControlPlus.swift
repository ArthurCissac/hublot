// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices
import os

/// Mission Control with a × on the window under the pointer, ⌘W, ⌘H, ⌘Q
/// acting on that window, and a two-finger pinch on it quitting its app
/// (see `ForkMissionControlLogic`).
///
/// While the setting is on, the window list is looked at a few times a
/// second for Mission Control. Only while it is open: WindowManager's
/// thumbnails are read by accessibility, the pointer is followed, a small
/// panel shows the × over the thumbnail under it, a keyboard tap takes ⌘W,
/// ⌘H and ⌘Q when a thumbnail is under the pointer (any other key goes on),
/// and a listening tap follows pinches. Both taps are gone as soon as Mission
/// Control closes. Main thread only.
final class ForkMissionControlPlus {
    static let shared = ForkMissionControlPlus()
    typealias Logic = ForkMissionControlLogic

    private var observers: [NSObjectProtocol] = []
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }
    private var watchTimer: Timer?
    private var refreshTimer: Timer?
    private var isOpen = false
    private var thumbnails: [Logic.Thumbnail] = []
    private var hovered: Logic.Thumbnail?
    private var mouseMonitor: Any?
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var pinchTap: CFMachPort?
    private var pinchSource: CFRunLoopSource?
    /// The pinch under way: the thumbnail it started on, and how far it has closed.
    private var pinch: (target: Logic.Thumbnail, magnification: Double)?
    /// One × per thumbnail place, so the × appears where it belongs instead
    /// of one sliding from window to window.
    private var buttons: [NSPanel] = []
    private var shownButton: Int?
    /// What happened, for `log show --predicate 'category == "mission-control"'`: no titles.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "mission-control")

    private init() {}

    func start() {
        resync.schedule()
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Never from inside the notification: see ForkCoalescedMainAction.
                self?.resync.schedule()
            })
        }
    }

    private var wanted: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.forkMissionControlPlus)
            && AppFeature.windowLayout.isAvailable && AXIsProcessTrusted()
    }

    private func sync() {
        if wanted {
            guard watchTimer == nil else { return }
            let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.watch() }
            RunLoop.main.add(timer, forMode: .common)
            watchTimer = timer
        } else {
            watchTimer?.invalidate()
            watchTimer = nil
            if isOpen { closed() }
        }
    }

    // MARK: - Mission Control coming and going

    private func watch() {
        let open = Self.overviewIsOpen()
        if open, !isOpen { opened() } else if !open, isOpen { closed() }
    }

    private static func overviewIsOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let windows = list.compactMap { entry -> Logic.WindowInfo? in
            guard let owner = entry[kCGWindowOwnerName as String] as? String,
                  owner == "WindowManager" || owner == "Dock",
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return Logic.WindowInfo(owner: owner, layer: layer,
                                    bounds: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                                                   width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0))
        }
        return Logic.overviewIsOpen(windows: windows, displays: NSScreen.screens.map(\.frame))
    }

    private func opened() {
        isOpen = true
        refreshThumbnails()
        log.notice("Mission Control open: \(self.thumbnails.count) windows")
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateHover()
        }
        startKeyTap()
        startPinchTap()
        // Thumbnails slide in, and move again once a window goes.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshThumbnails()
            self?.updateHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        updateHover()
    }

    private func closed() {
        isOpen = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        stopKeyTap()
        stopPinchTap()
        pinch = nil
        thumbnails = []
        hovered = nil
        hideButton()
        log.notice("Mission Control closed")
    }

    // MARK: - Thumbnails

    /// WindowManager's thumbnails, from accessibility: one button per window
    /// in each display's `mc.display` group.
    private func refreshThumbnails() {
        guard let manager = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first
        else {
            thumbnails = []
            return
        }
        let application = AXUIElementCreateApplication(manager.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var found: [Logic.Thumbnail] = []
        for display in Self.children(application) where Self.string(display, kAXIdentifierAttribute) == "mc.display" {
            for item in Self.children(display) {
                guard let identifier = Self.string(item, kAXIdentifierAttribute),
                      let bundleID = Logic.bundleID(fromIdentifier: identifier),
                      let frame = Self.frame(item) else { continue }
                found.append(Logic.Thumbnail(windowID: Self.number(item, "wid").map { CGWindowID($0) },
                                             bundleID: bundleID,
                                             title: Self.string(item, kAXTitleAttribute) ?? "",
                                             frame: frame))
            }
        }
        thumbnails = found
    }

    private func updateHover() {
        guard isOpen, let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let point = Logic.accessibilityPoint(NSEvent.mouseLocation, primaryHeight: primaryHeight)
        hovered = Logic.thumbnail(at: point, in: thumbnails)
        guard let hovered, let index = thumbnails.firstIndex(of: hovered) else {
            hideButton()
            return
        }
        showButton(at: index, frame: Logic.appKitRect(Logic.closeButtonFrame(for: hovered.frame),
                                                      primaryHeight: primaryHeight))
    }

    /// The × of one thumbnail place: the one shown before goes, this one
    /// appears where it is, without moving across.
    private func showButton(at index: Int, frame: CGRect) {
        if let shownButton, shownButton != index, shownButton < buttons.count { buttons[shownButton].orderOut(nil) }
        while buttons.count <= index { buttons.append(makePanel()) }
        let panel = buttons[index]
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        shownButton = index
        (panel.contentView as? CloseButton)?.pinching = pinch.map { Logic.pinchLeans(magnification: $0.magnification) } ?? false
    }

    private func hideButton() {
        if let shownButton, shownButton < buttons.count {
            (buttons[shownButton].contentView as? CloseButton)?.pinching = false
            buttons[shownButton].orderOut(nil)
        }
        shownButton = nil
    }

    // MARK: - Acting on the window

    private func perform(_ action: Logic.Action) {
        guard let target = hovered else { return }
        perform(action, on: target)
    }

    private func perform(_ action: Logic.Action, on target: Logic.Thumbnail) {
        guard let resolved = Self.resolve(target) else {
            log.notice("no window found for a thumbnail")
            NSSound.beep()
            return
        }
        let (windowID, pid) = resolved
        let own = pid == ProcessInfo.processInfo.processIdentifier
        switch action {
        case .close:
            _ = WindowActivator.closeWindow(windowID: windowID, appPID: pid, windowOwnerPID: pid)
        case .hide:
            if !own { NSRunningApplication(processIdentifier: pid)?.hide() }
        case .quit:
            if !own { NSRunningApplication(processIdentifier: pid)?.terminate() }
        }
        log.notice("\(String(describing: action), privacy: .public) on a window of \(target.bundleID, privacy: .public)")
        hovered = nil
        hideButton()
        // Mission Control rearranges what is left.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshThumbnails()
            self?.updateHover()
        }
    }

    /// The window a thumbnail shows, and its owner: its number when
    /// WindowManager gives one that belongs to the thumbnail's app, otherwise
    /// the window of that app with the thumbnail's title.
    private static func resolve(_ thumbnail: Logic.Thumbnail) -> (CGWindowID, pid_t)? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: thumbnail.bundleID)
            .map(\.processIdentifier))
        if let windowID = thumbnail.windowID, let pid = WindowServerSupport.ownerProcessID(ofWindowID: windowID),
           pids.contains(pid) {
            return (windowID, pid)
        }
        guard !thumbnail.title.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for entry in list {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  entry[kCGWindowLayer as String] as? Int == 0,
                  entry[kCGWindowName as String] as? String == thumbnail.title,
                  let number = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            return (CGWindowID(number.uint32Value), pid)
        }
        return nil
    }

    // MARK: - Keys, while Mission Control is open

    private func startKeyTap() {
        guard keyTap == nil else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ForkMissionControlPlus>.fromOpaque(refcon).takeUnretainedValue()
            return owner.key(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                          callback: callback, userInfo: me)
        else {
            log.notice("keyboard tap refused")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        keySource = source
    }

    private func stopKeyTap() {
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: false)
            if let keySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keySource, .commonModes) }
            CFMachPortInvalidate(keyTap)
        }
        keyTap = nil
        keySource = nil
    }

    /// True when the key was taken: ⌘W, ⌘H or ⌘Q with a thumbnail under the pointer.
    private func key(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return false
        case .keyDown:
            let flags = event.flags
            guard isOpen, hovered != nil,
                  let action = Logic.action(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                                            command: flags.contains(.maskCommand),
                                            otherModifiers: !flags.isDisjoint(with: [.maskControl, .maskAlternate, .maskShift]))
            else { return false }
            // A key held down repeats: acted on once, the repeats swallowed.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { [weak self] in self?.perform(action) }
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Pinches, while Mission Control is open

    /// Listening only: Mission Control does nothing with a two-finger pinch,
    /// and the gesture is followed, never held back.
    private func startPinchTap() {
        guard pinchTap == nil else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon { Unmanaged<ForkMissionControlPlus>.fromOpaque(refcon).takeUnretainedValue().gesture(type, event) }
            return Unmanaged.passUnretained(event)
        }
        // The trackpad's gesture events (type 29) carry pinches.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(1 << 29), callback: callback, userInfo: me)
        else {
            log.notice("pinch tap refused")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        pinchTap = tap
        pinchSource = source
    }

    private func stopPinchTap() {
        if let pinchTap {
            CGEvent.tapEnable(tap: pinchTap, enable: false)
            if let pinchSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), pinchSource, .commonModes) }
            CFMachPortInvalidate(pinchTap)
        }
        pinchTap = nil
        pinchSource = nil
    }

    /// A pinch is a gesture event of subtype 8 (field 110), its phase in
    /// field 132 and its change of size in field 113, as the title bar
    /// gestures read it. It acts on the thumbnail it started on.
    private func gesture(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let pinchTap { CGEvent.tapEnable(tap: pinchTap, enable: true) }
            return
        }
        guard isOpen, type.rawValue == 29,
              let subtype = CGEventField(rawValue: 110), event.getIntegerValueField(subtype) == 8,
              let phaseField = CGEventField(rawValue: 132), let sizeField = CGEventField(rawValue: 113)
        else { return }
        switch ForkTitleBarGestureLogic.Phase(raw: event.getIntegerValueField(phaseField)) {
        case .began:
            pinch = hovered.map { ($0, 0) }
        case .changed:
            guard var current = pinch else { return }
            let change = event.getDoubleValueField(sizeField)
            if change.isFinite { current.magnification += change }
            pinch = current
            if let shownButton, shownButton < buttons.count {
                (buttons[shownButton].contentView as? CloseButton)?.pinching = Logic.pinchLeans(magnification: current.magnification)
            }
        case .ended:
            guard let current = pinch else { return }
            pinch = nil
            if Logic.pinchQuits(magnification: current.magnification) {
                perform(.quit, on: current.target)
            } else {
                updateHover()
            }
        case .cancelled:
            pinch = nil
            updateHover()
        case .other:
            break
        }
    }

    // MARK: - The × button

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        // Mission Control is composited above ordinary levels, screen savers
        // included: at the display-shield level, as upstream's brightness
        // overlay does, the button stays in the picture. Stationary, as
        // transient windows are hidden while Mission Control is open.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Appears and goes at once, without macOS's window animation.
        panel.animationBehavior = .none
        panel.contentView = CloseButton { [weak self] in self?.perform(.close) }
        return panel
    }

    /// A dark circle with a ×, red under the pointer or while a pinch leans
    /// toward quitting. Drawn here, not taken from anywhere.
    private final class CloseButton: NSView {
        private let action: () -> Void
        private var highlighted = false { didSet { needsDisplay = true } }
        var pinching = false { didSet { if pinching != oldValue { needsDisplay = true } } }

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            setAccessibilityRole(.button)
            setAccessibilityLabel(ForkMissionControlStrings.current.closeWindow)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { highlighted = true }
        override func mouseExited(with event: NSEvent) { highlighted = false }
        override func mouseDown(with event: NSEvent) { action() }

        override func draw(_ dirtyRect: NSRect) {
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            (highlighted || pinching ? NSColor.systemRed : NSColor.black.withAlphaComponent(0.78)).setFill()
            circle.fill()
            NSColor.white.withAlphaComponent(0.85).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            let cross = NSBezierPath()
            let inset = bounds.width * 0.33
            cross.move(to: CGPoint(x: inset, y: inset))
            cross.line(to: CGPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
            cross.move(to: CGPoint(x: inset, y: bounds.maxY - inset))
            cross.line(to: CGPoint(x: bounds.maxX - inset, y: inset))
            cross.lineWidth = 2
            cross.lineCapStyle = .round
            NSColor.white.setStroke()
            cross.stroke()
        }
    }

    // MARK: - Accessibility reads

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func number(_ element: AXUIElement, _ attribute: String) -> UInt32? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? NSNumber, number.int64Value > 0 else { return nil }
        return number.uint32Value
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        // swiftlint:disable:next force_cast
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}
