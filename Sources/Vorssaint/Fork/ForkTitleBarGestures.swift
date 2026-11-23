// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices

/// Two-finger swipes and pinches on a window's title bar lay the window out,
/// minimize, close or send it to another display, as Swish does; with the
/// super modifier held, anywhere in the window. Over a Dock icon, they act on
/// that app's windows.
///
/// Two event taps. The first only listens: it never holds, changes or
/// swallows an event, and spots where a gesture starts. The second, Swish's
/// "active event listener", stays switched off until a gesture has started on
/// a window, then holds back that gesture's scroll and pinch events so the
/// window underneath neither scrolls nor zooms, and switches off again as soon
/// as the gesture and its momentum are over. Both exist only while the feature
/// is wanted, the window layout feature available and Accessibility granted.
/// Their callbacks only do arithmetic and one window-list lookup at the start
/// of a gesture; reaching the window through Accessibility and moving it
/// happen afterwards, off the taps' path. macOS switches a slow tap off: it is
/// switched back on, as upstream's taps do.
final class ForkTitleBarGestures {
    typealias Logic = ForkTitleBarGestureLogic

    static let shared = ForkTitleBarGestures()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdTap: CFMachPort?
    private var holdSource: CFRunLoopSource?
    /// Whether the holding tap is on: a gesture is under way.
    private var holding = false
    private var release: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    /// What a gesture acts on: a window, or the Dock icon at a point.
    private enum Target {
        case window(WindowServerWindowCandidate)
        case dock(CGPoint)

        var window: WindowServerWindowCandidate? {
            if case .window(let window) = self { return window }
            return nil
        }
    }

    /// What a swipe or a pinch started on, and how far it has gone.
    private var swipe: (target: Target, tracker: Logic.Tracker)?
    private var pinch: (target: Target, tracker: Logic.Tracker)?
    private var twice = Logic.Twice()
    private var pendingClose: DispatchWorkItem?
    /// The close waiting for a second gesture, kept to run should it not come.
    private var pendingCloseAction: (() -> Void)?
    /// Whether the window glides during the swipe under way.
    private var gliding = false
    /// What the gesture under way would do now, to notice when it changes.
    private var shownGesture: Logic.Gesture?
    private var shownDockGesture: ForkSwishDock.Gesture?
    private var escapeMonitor: Any?
    private var escaped = false

    /// The taps follow the settings, Accessibility and the app coming and going.
    func start() {
        DispatchQueue.main.async { [weak self] in self?.sync() }
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sync()
            })
        }
    }

    private var wanted: Bool {
        let defaults = UserDefaults.standard
        return (defaults.bool(forKey: DefaultsKey.forkTitleBarSwipe) || defaults.bool(forKey: DefaultsKey.forkTitleBarPinch))
            && AppFeature.windowLayout.isAvailable && AXIsProcessTrusted()
    }

    func sync() {
        if wanted {
            startTap()
            if UserDefaults.standard.bool(forKey: DefaultsKey.forkSwishActiveListener) { startHoldTap() } else { stopHoldTap() }
        } else {
            stopTap()
            stopHoldTap()
        }
    }

    /// Scroll wheel events, and the trackpad's gesture events (type 29), which carry pinches.
    private static let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue) | CGEventMask(1 << 29)

    private func startTap() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                Unmanaged<ForkTitleBarGestures>.fromOpaque(refcon).takeUnretainedValue().listen(type, event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: Self.mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func stopTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swipe = nil
        pinch = nil
        ForkSwishFeedback.shared.end()
    }

    /// The holding tap is created switched off; only a gesture switches it on.
    private func startHoldTap() {
        guard holdTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let gestures = Unmanaged<ForkTitleBarGestures>.fromOpaque(refcon).takeUnretainedValue()
            return gestures.hold(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let holdTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: Self.mask, callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        CGEvent.tapEnable(tap: holdTap, enable: false)
        let holdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, holdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), holdSource, .commonModes)
        self.holdTap = holdTap
        self.holdSource = holdSource
    }

    private func stopHoldTap() {
        releaseHold()
        guard let holdTap else { return }
        CGEvent.tapEnable(tap: holdTap, enable: false)
        if let holdSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), holdSource, .commonModes) }
        CFMachPortInvalidate(holdTap)
        self.holdTap = nil
        holdSource = nil
    }

    // MARK: - Holding events back during a gesture

    private func engageHold() {
        guard let holdTap else { return }
        if !holding {
            holding = true
            CGEvent.tapEnable(tap: holdTap, enable: true)
        }
        scheduleRelease(after: 1.0)
    }

    /// Lets go after a while without events, whatever happened: a gesture
    /// whose end never arrives must not leave scrolling held back.
    private func scheduleRelease(after delay: TimeInterval) {
        release?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.releaseHold() }
        release = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func releaseHold() {
        release?.cancel()
        release = nil
        guard holding else { return }
        holding = false
        if let holdTap { CGEvent.tapEnable(tap: holdTap, enable: false) }
    }

    /// The holding tap's events: whether to swallow each one.
    private func hold(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if holding, let holdTap { CGEvent.tapEnable(tap: holdTap, enable: true) }
            return false
        }
        guard holding else { return false }
        if type == .scrollWheel {
            // A mouse wheel is never part of a trackpad gesture.
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else {
                releaseHold()
                return false
            }
            let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            if momentum != 0 {
                // The glide after the fingers lift, swallowed too; its end lets go.
                if momentum == 3 { releaseHold() } else { scheduleRelease(after: 0.4) }
                return true
            }
            observe(type, event)
            let phase = Logic.Phase(raw: event.getIntegerValueField(.scrollWheelEventScrollPhase))
            return keepsHolding(afterStartOf: phase)
        }
        guard type.rawValue == 29 else { return false }
        let isPinch = CGEventField(rawValue: 110).map { event.getIntegerValueField($0) == 8 } ?? false
        observe(type, event)
        guard isPinch, let phaseField = CGEventField(rawValue: 132) else { return false }
        return keepsHolding(afterStartOf: Logic.Phase(raw: event.getIntegerValueField(phaseField)))
    }

    /// A new scroll or pinch that started outside any title bar while the
    /// previous gesture was winding down: let go at once and let it through,
    /// rather than eat the start of the user's next scroll.
    private func keepsHolding(afterStartOf phase: Logic.Phase) -> Bool {
        guard phase == .began, swipe == nil, pinch == nil else { return true }
        releaseHold()
        return false
    }

    // MARK: - Events

    /// The listening tap's events. While the holding tap is on it sees the
    /// gesture's events first; the listening tap leaves them to it.
    private func listen(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if !holding { observe(type, event) }
    }

    private func observe(_ type: CGEventType, _ event: CGEvent) {
        if type == .scrollWheel {
            observeScroll(event)
        } else if type.rawValue == 29 {
            observePinch(event)
        }
    }

    private func observeScroll(_ event: CGEvent) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.forkTitleBarSwipe),
              event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
        else { return }
        switch Logic.Phase(raw: event.getIntegerValueField(.scrollWheelEventScrollPhase)) {
        case .began:
            swipe = startingTarget(for: event).map { ($0, Logic.Tracker(lastMoved: Self.now)) }
            if let swipe {
                gestureBegan(on: swipe.target, at: event.location, gliding: defaults.bool(forKey: DefaultsKey.forkSwishLiveMove))
            }
        case .changed:
            guard var current = swipe, let ns = NSEvent(cgEvent: event) else { return }
            let movement = Logic.fingerMovement(scrollDeltaX: ns.scrollingDeltaX, scrollDeltaY: ns.scrollingDeltaY,
                                                naturalScrolling: ns.isDirectionInvertedFromDevice)
            current.tracker.add(movement)
            if hypot(movement.dx, movement.dy) > 0.5 { current.tracker.lastMoved = Self.now }
            swipe = current
            if holding { scheduleRelease(after: 1.0) }
            let role = ForkSwishModifiers.role(flags: Int(event.flags.rawValue), in: Self.modifiers())?.role
            let direction = Logic.direction(of: current.tracker.travel, threshold: Self.threshold())
            switch current.target {
            case .window(let window):
                let gesture = role.flatMap { role in direction.flatMap { Logic.gesture(for: $0, role: role) } }
                feedback(acting: gesture, shown: gesture, progress: 1, on: window)
            case .dock:
                let gesture = role.flatMap { role in direction.flatMap { ForkSwishDock.gesture(for: $0, role: role) } }
                dockFeedback(acting: gesture, shown: gesture, progress: 1)
            }
        case .ended:
            guard let current = swipe else { return }
            swipe = nil
            if holding { scheduleRelease(after: 0.4) }
            let calledOff = gestureEnded(lastMoved: current.tracker.lastMoved)
            let role = calledOff ? nil : ForkSwishModifiers.role(flags: Int(event.flags.rawValue), in: Self.modifiers())?.role
            let direction = Logic.direction(of: current.tracker.travel, threshold: Self.threshold())
            switch current.target {
            case .window(let window):
                finish(role.flatMap { role in direction.flatMap { Logic.gesture(for: $0, role: role) } }, on: window)
            case .dock(let point):
                ForkSwishFeedback.shared.end()
                if let gesture = role.flatMap({ role in direction.flatMap { ForkSwishDock.gesture(for: $0, role: role) } }) {
                    performOnDock(gesture, at: point)
                }
            }
        case .cancelled:
            guard let current = swipe else { return }
            swipe = nil
            _ = gestureEnded(lastMoved: Self.now)
            releaseHold()
            if let window = current.target.window { finish(nil, on: window) } else { ForkSwishFeedback.shared.end() }
        case .other:
            break
        }
    }

    /// A pinch arrives as a gesture event whose subtype (field 110) is 8,
    /// with its phase in field 132 and its change of size in field 113.
    private func observePinch(_ event: CGEvent) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.forkTitleBarPinch),
              let subtype = CGEventField(rawValue: 110), event.getIntegerValueField(subtype) == 8,
              let phaseField = CGEventField(rawValue: 132), let sizeField = CGEventField(rawValue: 113)
        else { return }
        switch Logic.Phase(raw: event.getIntegerValueField(phaseField)) {
        case .began:
            pinch = startingTarget(for: event).map { ($0, Logic.Tracker(lastMoved: Self.now)) }
            if let pinch { gestureBegan(on: pinch.target, at: event.location, gliding: false) }
        case .changed:
            guard var current = pinch else { return }
            let change = event.getDoubleValueField(sizeField)
            current.tracker.add(magnification: change)
            if abs(change) > 0.002 { current.tracker.lastMoved = Self.now }
            pinch = current
            if holding { scheduleRelease(after: 1.0) }
            // The icon shows as soon as the pinch leans one way, and firms up
            // as it comes closer to acting.
            let magnification = current.tracker.magnification
            let progress = ForkSwishMotion.pinchProgress(magnification)
            switch current.target {
            case .window(let window):
                let shown: Logic.Gesture? = magnification < -0.03 ? .close : magnification > 0.03 ? .layout(.fullScreen) : nil
                feedback(acting: Logic.gesture(forPinch: magnification), shown: shown, progress: progress, on: window)
            case .dock:
                dockFeedback(acting: ForkSwishDock.gesture(forPinch: magnification),
                             shown: magnification < -0.03 ? .quit : nil, progress: progress)
            }
        case .ended:
            guard let current = pinch else { return }
            pinch = nil
            releaseHold()
            let calledOff = gestureEnded(lastMoved: current.tracker.lastMoved)
            let magnification = calledOff ? 0 : current.tracker.magnification
            switch current.target {
            case .window(let window):
                finish(Logic.gesture(forPinch: magnification), on: window)
            case .dock(let point):
                ForkSwishFeedback.shared.end()
                if let gesture = ForkSwishDock.gesture(forPinch: magnification) { performOnDock(gesture, at: point) }
            }
        case .cancelled:
            guard let current = pinch else { return }
            pinch = nil
            _ = gestureEnded(lastMoved: Self.now)
            releaseHold()
            if let window = current.target.window { finish(nil, on: window) } else { ForkSwishFeedback.shared.end() }
        case .other:
            break
        }
    }

    // MARK: - Feedback during a gesture

    /// The window gesture under way would now do `acting` (nil: nothing yet);
    /// the bubble shows `shown`, which a pinch shows before it acts. Each new
    /// action taps the trackpad and, during a swipe, moves the window there.
    private func feedback(acting: Logic.Gesture?, shown: Logic.Gesture?, progress: Double,
                          on window: WindowServerWindowCandidate) {
        let defaults = UserDefaults.standard
        if acting != shownGesture {
            shownGesture = acting
            if acting != nil, defaults.bool(forKey: DefaultsKey.forkSwishHaptics) { Self.tapTrackpad() }
            if gliding { ForkSwishLiveMove.shared.glide(to: acting.flatMap { glideTarget(of: $0, window: window) }) }
        }
        let item = defaults.bool(forKey: DefaultsKey.forkSwishBubble)
            ? shown.flatMap { bubbleItem(for: $0, window: window, progress: progress) } : nil
        let outline = !gliding && defaults.bool(forKey: DefaultsKey.forkSwishPreview)
            ? acting.flatMap { ForkSwishWindowOps.appKitTarget(of: $0, window: window.frame) } : nil
        ForkSwishFeedback.shared.update(item: item, outline: outline)
    }

    private func dockFeedback(acting: ForkSwishDock.Gesture?, shown: ForkSwishDock.Gesture?, progress: Double) {
        let defaults = UserDefaults.standard
        if acting != shownDockGesture {
            shownDockGesture = acting
            if acting != nil, defaults.bool(forKey: DefaultsKey.forkSwishHaptics) { Self.tapTrackpad() }
        }
        let item = defaults.bool(forKey: DefaultsKey.forkSwishBubble) ? shown.map { dockItem(for: $0, progress: progress) } : nil
        ForkSwishFeedback.shared.update(item: item, outline: nil)
    }

    private static func tapTrackpad() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Where the window glides for a gesture, in Accessibility coordinates:
    /// only for gestures that give it a place, not full screen.
    private func glideTarget(of gesture: Logic.Gesture, window: WindowServerWindowCandidate) -> CGRect? {
        switch gesture {
        case .minimize, .close, .layout(.fullScreen): return nil
        default:
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return ForkSwishWindowOps.appKitTarget(of: gesture, window: window.frame)
                .map { ForkSwishDisplays.accessibilityRect($0, primaryHeight: primaryHeight) }
        }
    }

    private func bubbleItem(for gesture: Logic.Gesture, window: WindowServerWindowCandidate,
                            progress: Double) -> ForkSwishBubbleItem? {
        let text = ForkSwishStrings.current
        switch gesture {
        case .close:
            return twice.holding ? ForkSwishBubbleItem(icon: .quit, title: text.actionQuit, progress: progress)
                : ForkSwishBubbleItem(icon: .close, title: text.actionClose, progress: progress)
        case .minimize:
            return ForkSwishBubbleItem(icon: .minimize, title: text.actionMinimize, progress: progress)
        case .display(let direction):
            return ForkSwishBubbleItem(icon: .display(direction), title: text.actionDisplay(direction), progress: progress)
        case .ninth(let column, let row):
            let cell = CGRect(x: CGFloat(column) / 3, y: CGFloat(row) / 3, width: 1.0 / 3, height: 1.0 / 3)
            return ForkSwishBubbleItem(icon: .region(cell), title: text.actionCell(column, row), progress: progress)
        case .layout(let action):
            let title = action.title(FeatureStrings.windowLayout(L10n.shared.language))
            if action == .fullScreen { return ForkSwishBubbleItem(icon: .fullScreen, title: title, progress: progress) }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            guard let target = ForkSwishWindowOps.appKitTarget(of: gesture, window: window.frame),
                  let area = ForkSwishWindowOps.visibleArea(holding: window.frame)
            else { return nil }
            let region = ForkSwishMotion.region(of: target, in: ForkSwishDisplays.accessibilityRect(area, primaryHeight: primaryHeight))
            return ForkSwishBubbleItem(icon: .region(region), title: title, progress: progress)
        }
    }

    private func dockItem(for gesture: ForkSwishDock.Gesture, progress: Double) -> ForkSwishBubbleItem {
        let text = ForkSwishStrings.current
        switch gesture {
        case .cycle(let forward):
            return ForkSwishBubbleItem(icon: .cycle(forward: forward),
                                       title: forward ? text.actionNextWindow : text.actionPreviousWindow, progress: progress)
        case .minimize(let all):
            return ForkSwishBubbleItem(icon: .minimize, title: all ? text.actionMinimizeAll : text.actionMinimize, progress: progress)
        case .unminimize(let all):
            return ForkSwishBubbleItem(icon: .unminimize, title: all ? text.actionUnminimizeAll : text.actionUnminimize,
                                       progress: progress)
        case .quit:
            return ForkSwishBubbleItem(icon: .quit, title: text.actionQuit, progress: progress)
        }
    }

    /// A window gesture is over and does `gesture` (nil: nothing). The window
    /// stays where it glided only if that is where the gesture puts it; the
    /// final layout waits until it has stopped gliding.
    private func finish(_ gesture: Logic.Gesture?, on window: WindowServerWindowCandidate) {
        ForkSwishFeedback.shared.end()
        shownGesture = nil
        // A close held back by this gesture happens now, unless this is the
        // second close that turns it into quitting.
        if gesture != .close, twice.release() {
            pendingCloseAction?()
            pendingCloseAction = nil
        }
        let keep: Bool
        switch gesture {
        case .none, .minimize?, .close?, .layout(.fullScreen)?: keep = false
        default: keep = true
        }
        if gliding {
            gliding = false
            ForkSwishLiveMove.shared.finish(keep: keep) { [weak self] in
                if let gesture { self?.perform(gesture, on: window, haptic: false) }
            }
        } else if let gesture {
            DispatchQueue.main.async { [weak self] in self?.perform(gesture, on: window, haptic: false) }
        }
    }

    // MARK: - Calling a gesture off

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func threshold() -> CGFloat {
        Logic.swipeThreshold(sensitivity: UserDefaults.standard.integer(forKey: DefaultsKey.forkSwishSensitivity))
    }

    /// A gesture has started: on a window its events are held back, a close
    /// waiting on that window waits for it, and the window may glide; Escape
    /// is watched until it ends; the feedback overlay appears.
    private func gestureBegan(on target: Target, at location: CGPoint, gliding glide: Bool) {
        let defaults = UserDefaults.standard
        shownGesture = nil
        shownDockGesture = nil
        if let window = target.window {
            engageHold()
            if twice.begin(window: window.windowID, at: Self.now) { pendingClose?.cancel() }
            gliding = glide
            if glide { ForkSwishLiveMove.shared.begin(window) }
        }
        if defaults.bool(forKey: DefaultsKey.forkSwishBubble) || defaults.bool(forKey: DefaultsKey.forkSwishPreview) {
            ForkSwishFeedback.shared.begin(pointer: location, window: target.window?.frame)
        }
        escaped = false
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.escaped = true }
            }
        }
    }

    /// The gesture is over. True when it was called off: Escape was pressed,
    /// or the fingers rested longer than the cancel timeout before lifting.
    private func gestureEnded(lastMoved: TimeInterval) -> Bool {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        let timeout = UserDefaults.standard.double(forKey: DefaultsKey.forkSwishCancelTimeout)
        return escaped || Logic.rested(lastMoved: lastMoved, now: Self.now, timeout: timeout)
    }

    /// Two fingers tapped twice: the window under the pointer is centered.
    func doubleTapped() {
        guard let pointer = CGEvent(source: nil)?.location else { return }
        let flags = Int(CGEventSource.flagsState(.combinedSessionState).rawValue)
        let superHeld = ForkSwishModifiers.role(flags: flags, in: Self.modifiers())?.superHeld ?? false
        if UserDefaults.standard.bool(forKey: DefaultsKey.forkSwishRequireSuper), !superHeld { return }
        guard let window = window(at: pointer, anywhere: superHeld) else { return }
        perform(.layout(.center), on: window)
    }

    /// What a gesture starting with this event acts on: the window whose
    /// title bar is under the pointer; else an icon of the Dock, when the
    /// pointer is along the Dock's edge; else, with the super modifier held,
    /// the window under the pointer wherever it is. Nothing when the super
    /// modifier is required and not held.
    private func startingTarget(for event: CGEvent) -> Target? {
        let superHeld = ForkSwishModifiers.role(flags: Int(event.flags.rawValue), in: Self.modifiers())?.superHeld ?? false
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.forkSwishRequireSuper), !superHeld { return nil }
        let point = event.location
        if let window = window(at: point, anywhere: false) { return .window(window) }
        if defaults.bool(forKey: DefaultsKey.forkSwishDockGestures), ForkSwishDockApps.isNearDock(point) { return .dock(point) }
        return superHeld ? window(at: point, anywhere: true).map(Target.window) : nil
    }

    /// The Dock's icon is read through Accessibility, off the taps' path.
    private func performOnDock(_ gesture: ForkSwishDock.Gesture, at point: CGPoint) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let app = ForkSwishDockApps.application(at: point) else { return }
            DispatchQueue.main.async { ForkSwishDockApps.perform(gesture, on: app) }
        }
    }

    /// The window under the point, from the window list alone, without asking
    /// any app: an app left alone by the window layout settings, or this app,
    /// gives nothing.
    private func window(at point: CGPoint, anywhere: Bool) -> WindowServerWindowCandidate? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ignored = WindowLayoutIgnoredApps.shared.apps
        guard let candidate = WindowServerSupport.windowCandidate(
            in: windows, at: point, ownProcessID: ProcessInfo.processInfo.processIdentifier,
            pidIsEligible: { pid in
                let app = NSRunningApplication(processIdentifier: pid)
                return !WindowLayoutIgnoredApps.matches(bundleID: app?.bundleIdentifier,
                                                        executablePath: app?.executableURL?.path, apps: ignored)
            }),
              anywhere || Logic.isOnTitleBar(point, windowFrame: candidate.frame)
        else { return nil }
        return candidate
    }

    /// The Swish modifiers as set.
    static func modifiers() -> ForkSwishModifiers.Set {
        let defaults = UserDefaults.standard
        return ForkSwishModifiers.Set(general: defaults.integer(forKey: DefaultsKey.forkSwishGeneralModifier),
                                      screen: defaults.integer(forKey: DefaultsKey.forkSwishScreenModifier),
                                      secondary: defaults.integer(forKey: DefaultsKey.forkSwishSecondaryModifier),
                                      tertiary: defaults.integer(forKey: DefaultsKey.forkSwishTertiaryModifier),
                                      superKey: defaults.integer(forKey: DefaultsKey.forkSwishSuperModifier))
    }

    // MARK: - Acting on the window

    /// `haptic`: tap the trackpad as the gesture acts, for a gesture that
    /// gave no feedback while under way (the double tap).
    private func perform(_ gesture: Logic.Gesture, on window: WindowServerWindowCandidate, haptic: Bool = true) {
        let defaults = UserDefaults.standard
        let pointerFollows = defaults.bool(forKey: DefaultsKey.forkSwishMoveCursor)
        if haptic, defaults.bool(forKey: DefaultsKey.forkSwishHaptics) { Self.tapTrackpad() }
        switch gesture {
        case .minimize:
            _ = WindowActivator.setWindowMinimized(true, windowID: window.windowID, pid: window.pid)
        case .close:
            switch twice.close(window: window.windowID, at: ProcessInfo.processInfo.systemUptime) {
            case .closeLater:
                // Another window's close still waiting happens now: a new
                // close must never drop it.
                pendingClose?.cancel()
                pendingCloseAction?()
                let action = {
                    _ = WindowActivator.closeWindow(windowID: window.windowID, appPID: window.pid, windowOwnerPID: window.pid)
                }
                pendingCloseAction = action
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingCloseAction = nil
                    action()
                }
                pendingClose = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Logic.Twice.window, execute: work)
            case .quit:
                pendingClose?.cancel()
                pendingClose = nil
                pendingCloseAction = nil
                ForkSwishWindowOps.quitApp(pid: window.pid)
            }
        case .display(let direction):
            guard let element = element(for: window) else { return }
            _ = WindowActivator.focusWindow(windowID: window.windowID, pid: window.pid)
            ForkSwishWindowOps.moveToDisplay(element, toward: direction, pointerFollows: pointerFollows)
        case .ninth(let column, let row):
            guard let element = element(for: window) else { return }
            _ = WindowActivator.focusWindow(windowID: window.windowID, pid: window.pid)
            ForkSwishWindowOps.placeNinth(element, column: column, row: row, pointerFollows: pointerFollows)
        case .layout(let action):
            guard let element = element(for: window) else { return }
            // The window laid out comes to the front, as with Swish.
            _ = WindowActivator.focusWindow(windowID: window.windowID, pid: window.pid)
            WindowLayoutService.shared.apply(action, window: element)
            if pointerFollows, action != .fullScreen { ForkSwishWindowOps.followWindow(element) }
        }
    }

    private func element(for window: WindowServerWindowCandidate) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        return AXWindowResolver.element(for: window.windowID, in: app, pid: window.pid)
    }
}
