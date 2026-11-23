// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import QuartzCore
import SwiftUI

typealias ForkPreviewAction = ScreenshotQuickPreviewController.Action

/// The card-style capture previews: fixed cards stacked at the bottom left of
/// the pointer's display, in place of upstream's preview panel and of the
/// island. The newest card sits on top; when the display can hold no more,
/// the oldest is saved to the capture folder and leaves.
///
/// `ScreenshotQuickPreviewController.show` hands a capture over from one line,
/// together with the closure that runs its actions, so copy, save, edit, pin
/// and discard stay upstream's own. Used from the main thread only, like the
/// capture workflow that calls it.
final class ForkPreviewCards {
    static let shared = ForkPreviewCards()

    private var cards: [ForkPreviewCardController] = []
    private var stackScreen = CGRect.zero
    private var followTimer: Timer?
    /// The last card put away, for the reopen shortcut. One picture, replaced by the next.
    private var lastClosed: ScreenshotSelectionController.Capture?
    private let reopenHotkey = QuickToolHotkey(id: 9_102)
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.syncWithPreferences() }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkScreenshotPreviewCard)
    }

    /// The cards' windows, for the capture engine to leave out: a card is a
    /// surface of the capture workflow and must never be photographed.
    var windowIDs: Set<CGWindowID> {
        Set(cards.compactMap(\.windowID)).union(ForkCaptureMenu.shared.windowIDs)
    }

    /// Shows the capture as a card. False when the card style is off, and the
    /// caller then goes on with its own preview.
    static func present(_ capture: ScreenshotSelectionController.Capture,
                        strings: ScreenshotFeatureStrings,
                        disabled: Set<ForkPreviewAction>,
                        perform: @escaping (ForkPreviewAction) -> Set<ForkPreviewAction>) -> Bool {
        guard isEnabled() else { return false }
        shared.add(ForkPreviewCardController(capture: capture, strings: strings,
                                             disabled: disabled, perform: perform))
        return true
    }

    /// An editor that closes hands its picture back as a card, edits included,
    /// so closing the editor never loses the capture: it is back at the bottom
    /// left, ready to be copied, saved, dragged or opened again. Called from
    /// one line in `ScreenshotService.editorDidClose`; with the card style on,
    /// the editor also skips its "discard changes?" question, which no longer
    /// has anything to warn about.
    static func editorDidClose(_ editor: ScreenshotEditorController) {
        guard isEnabled(), AppFeature.screenshot.isAvailable,
              let export = editor.model.exportImage() else { return }
        // The preview goes through upstream's own path, which hands the
        // capture to `present` above, and runs none of the after-capture
        // actions a second time.
        ScreenshotService.shared.restorePreview(ScreenshotSelectionController.Capture(
            image: export.image, scale: export.scale, anchorRect: .zero, sourceFormat: editor.sourceFormat))
    }

    /// Registers the reopen shortcut, as the capture menu does its own.
    func start() {
        reopenHotkey.onPress = { [weak self] in self?.reopen() }
        DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
        for name in [UserDefaults.didChangeNotification,
                     NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Never from inside the notification: see ForkCoalescedMainAction.
                self?.resync.schedule()
            }
        }
    }

    private func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: DefaultsKey.forkReopenPreviewShortcutEnabled)
            && Self.isEnabled(in: defaults) && AppFeature.screenshot.isAvailable
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.forkReopenPreviewShortcut,
                                            fallback: ForkPreviewCardGestures.reopenShortcut)
        _ = reopenHotkey.sync(enabled: enabled, shortcut: shortcut, storageKey: DefaultsKey.forkReopenPreviewShortcut)
        if !enabled { lastClosed = nil }
    }

    /// The last card put away comes back, through upstream's own preview path.
    private func reopen() {
        guard let capture = lastClosed else {
            QuickToolHUD.show(icon: "rectangle.stack", message: ForkStrings.current.noClosedPreview)
            return
        }
        lastClosed = nil
        ScreenshotService.shared.restorePreview(capture)
    }

    private func add(_ card: ForkPreviewCardController) {
        guard let screen = pointerScreen() else { return }
        // Room for the newcomer: the oldest cards are saved and leave.
        archiveOldest(ForkPreviewCardLayout.overflow(count: cards.count + 1,
                                                     capacity: ForkPreviewCardLayout.capacity(in: screen)))
        // The stack lives on one display: the pointer's.
        stackScreen = screen
        card.onClose = { [weak self] closed in self?.remove(closed) }
        cards.append(card)
        settle()
        card.show(in: ForkPreviewCardLayout.cardFrame(index: cards.count - 1, in: screen))
        startFollowingPointer()
    }

    private func remove(_ card: ForkPreviewCardController) {
        // Put away, not thrown away: the reopen shortcut can bring it back.
        if card.remembersWhenClosed { lastClosed = card.capture }
        cards.removeAll { $0 === card }
        settle()
        if cards.isEmpty { stopFollowingPointer() }
    }

    /// Saves the oldest cards to the capture folder and takes them off the
    /// stack. A capture is never dropped for lack of room.
    private func archiveOldest(_ count: Int) {
        for _ in 0..<min(max(0, count), cards.count) {
            let oldest = cards.removeFirst()
            oldest.onClose = nil
            oldest.archive()
        }
    }

    /// Puts every card already on screen at its place in the stack.
    private func settle() {
        for (index, card) in cards.enumerated() {
            card.move(to: ForkPreviewCardLayout.cardFrame(index: index, in: stackScreen))
        }
    }

    private func pointerScreen() -> CGRect? {
        ForkPreviewCardLayout.screenFrame(pointer: NSEvent.mouseLocation,
                                          screenFrames: NSScreen.screens.map(\.frame))
    }

    // MARK: - Following the pointer from one display to the next

    /// The cards stay on the display the pointer is on. A light timer, alive
    /// only while a card is shown, notices the pointer changing display; a
    /// card being dragged is left alone until the drag is over.
    private func startFollowingPointer() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.followPointer() }
        // Common modes, so the cards also follow during a drag or a menu.
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowingPointer() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func followPointer() {
        guard !cards.isEmpty, !cards.contains(where: \.isBeingDragged),
              let screen = pointerScreen(), screen != stackScreen else { return }
        stackScreen = screen
        // A smaller display holds fewer cards.
        archiveOldest(ForkPreviewCardLayout.overflow(count: cards.count,
                                                     capacity: ForkPreviewCardLayout.capacity(in: screen)))
        for (index, card) in cards.enumerated() {
            card.relocate(to: ForkPreviewCardLayout.cardFrame(index: index, in: screen))
        }
    }
}

/// One card: its panel, its drawing, and what its controls do.
final class ForkPreviewCardController {
    let capture: ScreenshotSelectionController.Capture
    private let strings: ScreenshotFeatureStrings
    private let perform: (ForkPreviewAction) -> Set<ForkPreviewAction>
    private let model: ForkPreviewCardModel
    private var panel: ForkPreviewCardPanel?
    private var closed = false
    private var relocation = 0
    private(set) var isBeingDragged = false
    /// False once the capture was thrown away, opened in the editor or pinned:
    /// the reopen shortcut has nothing to bring back then.
    private(set) var remembersWhenClosed = true
    private var swipe: (rest: CGRect, travel: CGFloat, sideways: Bool?)?
    var onClose: ((ForkPreviewCardController) -> Void)?

    var windowID: CGWindowID? {
        guard let panel, panel.windowNumber > 0 else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    init(capture: ScreenshotSelectionController.Capture,
         strings: ScreenshotFeatureStrings,
         disabled: Set<ForkPreviewAction>,
         perform: @escaping (ForkPreviewAction) -> Set<ForkPreviewAction>) {
        self.capture = capture
        self.strings = strings
        self.perform = perform
        var done = Set<ForkPreviewCardLayout.Control>()
        if disabled.contains(.copy) { done.insert(.copy) }
        if disabled.contains(.save) { done.insert(.save) }
        model = ForkPreviewCardModel(disabled: done)
    }

    func show(in frame: CGRect) {
        guard panel == nil, !closed else { return }
        let thumbnail = Self.thumbnail(for: capture.image)
        let drawing = NSHostingView(rootView: ForkPreviewCardView(image: thumbnail, strings: strings, model: model))
        let events = ForkPreviewCardEventView(
            model: model,
            content: drawing,
            dragPreview: Self.cardImage(for: thumbnail),
            activate: { [weak self] target in self?.activate(target) },
            dragFile: { [weak self] in
                guard let self else { return nil }
                return ScreenshotService.temporaryExportFile(image: self.capture.image,
                                                             scale: self.capture.scale,
                                                             strings: self.strings)
            },
            dragBegan: { [weak self] in self?.dragBegan() },
            dragEnded: { [weak self] delivered in self?.dragEnded(delivered: delivered) })
        events.hover = { [weak self] inside in
            guard let self else { return }
            ForkPreviewCardShortcuts.shared.pointer(inside, over: self)
        }
        events.scroll = { [weak self] event in self?.scrolled(event) }

        let panel = ForkPreviewCardPanel(contentRect: frame,
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered,
                                         defer: false)
        panel.contentView = events
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // For a see-through window macOS decides by itself which parts take
        // clicks, from what it believes is drawn there, and lets the rest fall
        // through to the window below. It got the card wrong: clicks near its
        // right edge reached the desktop. Setting this explicitly, even to its
        // default, turns that guesswork off: the whole card takes its clicks.
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel = panel

        panel.alphaValue = 0
        panel.setFrame(Self.reducesMotion ? frame : ForkPreviewCardLayout.restingOffsetFrame(for: frame),
                       display: false)
        panel.orderFrontRegardless()
        slideIn(panel, to: frame)
    }

    /// Slides to another place in the stack on the same display.
    func move(to frame: CGRect) {
        guard let panel, !closed, panel.frame != frame else { return }
        if Self.reducesMotion {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Leaves one display and arrives on another: out toward the edge here,
    /// in from the edge there, rather than flying across both screens.
    func relocate(to frame: CGRect) {
        guard let panel, !closed, panel.frame != frame else { return }
        if Self.reducesMotion {
            panel.setFrame(frame, display: true)
            return
        }
        relocation += 1
        let token = relocation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(ForkPreviewCardLayout.restingOffsetFrame(for: panel.frame), display: true)
        }, completionHandler: { [weak self] in
            // A newer move, or a close, has taken over meanwhile.
            guard let self, !self.closed, self.relocation == token, let panel = self.panel else { return }
            panel.setFrame(ForkPreviewCardLayout.restingOffsetFrame(for: frame), display: false)
            self.slideIn(panel, to: frame)
        })
    }

    func close(animated: Bool = true) {
        guard !closed else { return }
        closed = true
        ForkPreviewCardShortcuts.shared.pointer(false, over: self)
        // The stack closes ranks at once; the panel fades out on its own.
        onClose?(self)
        onClose = nil
        guard let panel else { return }
        self.panel = nil
        guard animated, !Self.reducesMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(ForkPreviewCardLayout.restingOffsetFrame(for: panel.frame), display: true)
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Leaves the stack for good, without losing the capture: unless the
    /// after-capture action already saved it, it is saved now.
    func archive() {
        guard !closed else { return }
        if !model.disabled.contains(.save) { _ = perform(.save) }
        close()
    }

    private func slideIn(_ panel: NSPanel, to frame: CGRect) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak panel] in
            // The window's shadow follows the rounded card once it is drawn.
            panel?.invalidateShadow()
        })
    }

    private func activate(_ target: ForkPreviewCardLayout.ClickTarget) {
        guard !closed else { return }
        switch target {
        case .picture, .control(.edit):
            // A click on the picture opens it in the editor, like the pencil.
            // The editor promotes the app and builds its own window: leave
            // first, and open it once this click has finished.
            let perform = perform
            remembersWhenClosed = false
            close()
            DispatchQueue.main.async { _ = perform(.edit) }
        case .control(let control):
            guard !model.disabled.contains(control) else { return }
            switch control {
            case .close:
                // Closing only puts the card away; the capture keeps whatever was done with it.
                close()
            case .copy:
                // A copy leaves the card in place: the capture can still be saved or dragged.
                if !perform(.copy).isEmpty { model.flashCopied() }
            case .save:
                if !perform(.save).isEmpty { close() }
            case .pin:
                if !perform(.pin).isEmpty {
                    remembersWhenClosed = false
                    close()
                }
            case .discard:
                if !perform(.discard).isEmpty {
                    remembersWhenClosed = false
                    close()
                }
            case .edit:
                break
            }
        }
    }

    /// A shortcut typed while the pointer is over the card: the same as its buttons.
    func run(_ shortcut: ForkPreviewCardGestures.Shortcut) {
        switch shortcut {
        case .copy: activate(.control(.copy))
        case .save: activate(.control(.save))
        case .close: activate(.control(.close))
        case .edit: activate(.control(.edit))
        }
    }

    /// Two fingers sideways move the card; far enough toward the left edge, it
    /// is put away, otherwise it slides back. The size never changes, so the
    /// frame can follow the fingers and be animated back.
    private func scrolled(_ event: NSEvent) {
        guard !closed, let panel, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipe = (panel.frame, 0, nil)
            return
        }
        guard var current = swipe else { return }
        if event.phase.contains(.changed) {
            if current.sideways == nil, abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) >= 2 {
                current.sideways = ForkPreviewCardGestures.isSideways(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
                if current.sideways == true { isBeingDragged = true }
            }
            guard current.sideways == true else {
                swipe = current
                return
            }
            // With natural scrolling the delta already follows the fingers.
            current.travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            swipe = current
            let offset = ForkPreviewCardGestures.swipeOffset(fingerTravel: current.travel)
            panel.setFrameOrigin(CGPoint(x: current.rest.minX + offset, y: current.rest.minY))
            return
        }
        guard event.phase.contains(.ended) || event.phase.contains(.cancelled) else { return }
        swipe = nil
        guard current.sideways == true else { return }
        isBeingDragged = false
        if ForkPreviewCardGestures.swipeDismisses(offset: ForkPreviewCardGestures.swipeOffset(fingerTravel: current.travel)) {
            close()
        } else if Self.reducesMotion {
            panel.setFrame(current.rest, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(current.rest, display: true)
            }
        }
    }

    /// While its picture follows the pointer, the card itself is out of sight:
    /// the capture looks picked up, not copied.
    private func dragBegan() {
        isBeingDragged = true
        panel?.alphaValue = 0
    }

    /// Dropped into an app, the capture has gone where it was wanted and the
    /// card with it. Dropped nowhere, the picture has flown back and the card
    /// is shown again where it was.
    private func dragEnded(delivered: Bool) {
        isBeingDragged = false
        if delivered {
            close(animated: false)
        } else {
            panel?.alphaValue = 1
        }
    }

    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The card shows a small picture: a capture of several thousand pixels is
    /// scaled down once instead of at every redraw.
    private static func thumbnail(for image: CGImage) -> CGImage {
        let maximumDimension: CGFloat = 1_200
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maximumDimension else { return image }
        let factor = maximumDimension / longest
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// The card as it looks at rest, for the drag: the picture filling the
    /// card's size, with its rounded corners.
    private static func cardImage(for image: CGImage) -> NSImage {
        let size = ForkPreviewCardLayout.cardSize
        return NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let radius = ForkPreviewCardLayout.cornerRadius
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            context.interpolationQuality = .high
            context.draw(image, in: ForkPreviewCardLayout.fillRect(
                imageSize: CGSize(width: image.width, height: image.height), in: rect))
            return true
        }
    }
}

/// The card's window. It never becomes key: a capture preview must not take
/// the keyboard from the app being typed into, and a card left on screen after
/// a copy would otherwise swallow the paste that follows. Its clicks do not
/// need it: the card's event view takes the mouse whatever the window's state.
/// (Asking AppKit to make it key only "if needed" was not enough: a click on
/// the card still made it key.)
final class ForkPreviewCardPanel: OverlayPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
