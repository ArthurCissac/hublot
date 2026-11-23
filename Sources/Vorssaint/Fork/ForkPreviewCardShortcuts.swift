// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import CoreGraphics

/// ⌘C, ⌘S, ⌘W and ⌘E on the card under the pointer.
///
/// A card never takes the keyboard: the app being typed into keeps it. So
/// these four keys are caught by an event tap that exists only while the
/// pointer is over a card, takes those four and nothing else, and goes away
/// as soon as the pointer leaves or the card closes. It needs the
/// Accessibility permission the app already asks for; without it the
/// shortcuts simply do nothing. Main thread only.
final class ForkPreviewCardShortcuts {
    static let shared = ForkPreviewCardShortcuts()

    private weak var hovered: ForkPreviewCardController?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func pointer(_ inside: Bool, over card: ForkPreviewCardController) {
        if inside {
            hovered = card
            start()
        } else if hovered === card || hovered == nil {
            hovered = nil
            stop()
        }
    }

    private func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let shortcuts = Unmanaged<ForkPreviewCardShortcuts>.fromOpaque(refcon).takeUnretainedValue()
            return shortcuts.handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS switches a slow tap off; the hover is still going, so it comes back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, let card = hovered, let key = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        let flags = key.modifierFlags.intersection([.command, .option, .shift, .control])
        guard let shortcut = ForkPreviewCardGestures.shortcut(character: key.charactersIgnoringModifiers,
                                                              keyCode: Int(key.keyCode),
                                                              commandOnly: flags == .command)
        else { return Unmanaged.passUnretained(event) }
        // A held key repeats: the first press acts, the repeats are only kept from the app in front.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { card.run(shortcut) }
        }
        return nil
    }
}
