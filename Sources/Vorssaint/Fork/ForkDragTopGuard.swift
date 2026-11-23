// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import os

/// Keeps a dragged file (or any dragged item) from resting on the top edge of
/// a display, where macOS opens Mission Control: carried onto the display
/// above when there is one, kept one point under the edge otherwise. A window
/// being moved is left alone: upstream handles it.
///
/// Two event taps. The first only listens to the mouse button and notices a
/// drag-and-drop coming near the top: the system's drag pasteboard has changed
/// since the button went down, which a window being moved never does. Only
/// then is the second tap switched on; it moves each dragged event's position
/// down to one point under the edge when it reaches it, and switches off again
/// when the button comes up. Both exist only while the setting is on, the
/// shelf available and Accessibility granted; a slow tap switched off by macOS
/// is switched back on, as upstream's taps are.
final class ForkDragTopGuard {
    typealias Logic = ForkDragTopGuardLogic

    static let shared = ForkDragTopGuard()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdTap: CFMachPort?
    private var holdSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }
    /// The drag pasteboard's count when the button went down.
    private var countAtDown = 0
    private var guarding = false
    /// Where the cursor is held, one point under the edge at `heldEdgeY`,
    /// while it is detached from the mouse; nil when it moves freely.
    private var held: CGPoint?
    private var heldEdgeY: CGFloat = 0
    /// Whether this press already noted a drag near the top that was not a
    /// drag and drop, so the log says it once.
    private var notedPlainDrag = false
    /// What the guard did, for `log show --predicate 'category == "drag-guard"'`:
    /// no file names, no content, only the steps.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "drag-guard")
    /// The top edges guarded, read again when the displays change.
    private var edges: [Logic.Edge] = []

    func start() {
        resync.schedule()
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.resync.schedule()
            })
        }
    }

    private var wanted: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.forkDragTopGuard)
            && AppFeature.shelf.isAvailable && AXIsProcessTrusted()
    }

    func sync() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let displays = NSScreen.screens.map { ForkSwishDisplays.accessibilityRect($0.frame, primaryHeight: primaryHeight) }
        edges = Logic.edges(displays: displays)
        if wanted { startTaps() } else { stopTaps() }
    }

    private static let buttonMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

    private func startTaps() {
        guard tap == nil else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let listen: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon { Unmanaged<ForkDragTopGuard>.fromOpaque(refcon).takeUnretainedValue().listen(type, event) }
            return Unmanaged.passUnretained(event)
        }
        let hold: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon { Unmanaged<ForkDragTopGuard>.fromOpaque(refcon).takeUnretainedValue().hold(type, event) }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: Self.buttonMask, callback: listen, userInfo: me),
              let holdTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: Self.buttonMask, callback: hold, userInfo: me)
        else { return }
        CGEvent.tapEnable(tap: holdTap, enable: false)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let holdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, holdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), holdSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        self.holdTap = holdTap
        self.holdSource = holdSource
    }

    private func stopTaps() {
        stopGuarding()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        if let holdTap {
            CGEvent.tapEnable(tap: holdTap, enable: false)
            if let holdSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), holdSource, .commonModes) }
            CFMachPortInvalidate(holdTap)
        }
        tap = nil
        source = nil
        holdTap = nil
        holdSource = nil
    }

    private func stopGuarding() {
        releaseCursor()
        guard guarding else { return }
        guarding = false
        if let holdTap { CGEvent.tapEnable(tap: holdTap, enable: false) }
    }

    /// The cursor follows the mouse again.
    private func releaseCursor() {
        guard held != nil else { return }
        held = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        log.notice("cursor let go")
    }

    private func listen(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown:
            countAtDown = NSPasteboard(name: .drag).changeCount
            notedPlainDrag = false
            stopGuarding()
        case .leftMouseDragged:
            // The pasteboard is asked only near the top, where it matters.
            guard !guarding, Logic.isNearTop(event.location, edges: edges), let holdTap else { return }
            guard NSPasteboard(name: .drag).changeCount != countAtDown else {
                if !notedPlainDrag {
                    notedPlainDrag = true
                    log.notice("drag near the top, but no drag and drop: left alone")
                }
                return
            }
            guarding = true
            CGEvent.tapEnable(tap: holdTap, enable: true)
            log.notice("drag and drop near the top: guard on at y \(Int(event.location.y))")
        case .leftMouseUp:
            stopGuarding()
        default:
            break
        }
    }

    /// While guarding: at the guarded edge the cursor itself is detached from
    /// the mouse and moved by hand, one point under the edge, so neither the
    /// events nor the cursor ever reach the coordinate that opens Mission
    /// Control. It is let go as soon as it comes back down, leaves the guarded
    /// stretch, or the button comes up.
    private func hold(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if guarding, let holdTap { CGEvent.tapEnable(tap: holdTap, enable: true) } else { releaseCursor() }
        case .leftMouseDragged:
            guard guarding else { return }
            if let current = held {
                let delta = CGVector(dx: event.getDoubleValueField(.mouseEventDeltaX),
                                     dy: event.getDoubleValueField(.mouseEventDeltaY))
                let step = Logic.heldStep(from: current, delta: delta, edgeY: heldEdgeY, edges: edges)
                CGWarpMouseCursorPosition(step.point)
                event.location = step.point
                if step.held { held = step.point } else { releaseCursor() }
            } else if let carried = Logic.carried(event.location, deltaY: event.getDoubleValueField(.mouseEventDeltaY),
                                                  edges: edges) {
                // A display above: straight onto it, without resting on the edge.
                CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
                CGWarpMouseCursorPosition(carried)
                event.location = carried
                log.notice("drag carried onto the display above")
            } else if let kept = Logic.kept(event.location, edges: edges) {
                held = kept
                heldEdgeY = kept.y - 1
                // A moved cursor would otherwise mute the mouse for a quarter second.
                CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
                CGAssociateMouseAndMouseCursorPosition(0)
                CGWarpMouseCursorPosition(kept)
                event.location = kept
                log.notice("cursor held under the edge at y \(Int(kept.y))")
            }
        case .leftMouseUp:
            stopGuarding()
        default:
            break
        }
    }
}
