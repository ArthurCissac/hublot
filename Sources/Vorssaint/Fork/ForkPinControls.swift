// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// The bar of buttons a pinned capture shows under the pointer: close it, put
/// it back among the previews, edit it, save it, drag it into another app,
/// shrink it, enlarge it.
///
/// Upstream's pin already moves by dragging, resizes from its edges and has a
/// right-click menu; none of that changes. The bar is added on top from one
/// call in the pin's initializer, which also lends it the pin's own save and
/// close, the two actions the fork cannot reach by itself.
enum ForkPinControls {
    static func install(in content: NSView, image: CGImage, scale: CGFloat,
                        save: @escaping () -> Void, close: @escaping () -> Void) {
        let controls = ForkPinControlsView(image: image, scale: scale, save: save, close: close)
        controls.frame = content.bounds
        controls.autoresizingMask = [.width, .height]
        content.addSubview(controls)
    }
}

/// Covers the pin without taking its clicks: only the bar's buttons answer,
/// so dragging the picture still moves the pin and a double click still closes it.
final class ForkPinControlsView: NSView {
    private let image: CGImage
    private let scale: CGFloat
    private let save: () -> Void
    private let close: () -> Void
    private let bar = NSView()
    private let stack = NSStackView()
    private var shown: [ForkPinLayout.Control] = []
    private var tracking: NSTrackingArea?
    private var pointerInside = false

    init(image: CGImage, scale: CGFloat, save: @escaping () -> Void, close: @escaping () -> Void) {
        self.image = image
        self.scale = scale
        self.save = save
        self.close = close
        super.init(frame: .zero)

        bar.wantsLayer = true
        bar.layer?.backgroundColor = CGColor(gray: 0.08, alpha: 0.72)
        bar.layer?.cornerRadius = ForkPinLayout.barHeight / 2
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = CGColor(gray: 1, alpha: 0.16)
        bar.alphaValue = 0
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: ForkPinLayout.barPadding, bottom: 0, right: ForkPinLayout.barPadding)
        stack.frame = bar.bounds
        stack.autoresizingMask = [.width, .height]
        bar.addSubview(stack)
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var capture: ScreenshotSelectionController.Capture {
        ScreenshotSelectionController.Capture(image: image, scale: scale, anchorRect: .zero)
    }

    /// Everything but the bar falls through to the pin underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func layout() {
        super.layout()
        // The buttons that fit this width, in a bar centered at the top.
        let controls = ForkPinLayout.controls(forPinWidth: bounds.width)
        if controls != shown {
            shown = controls
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for control in controls { stack.addArrangedSubview(button(for: control)) }
        }
        bar.isHidden = controls.isEmpty
        let width = ForkPinLayout.barWidth(for: controls)
        bar.frame = CGRect(x: ((bounds.width - width) / 2).rounded(),
                           y: bounds.height - ForkPinLayout.margin - ForkPinLayout.barHeight,
                           width: width, height: ForkPinLayout.barHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setBarVisible(true) }
    override func mouseExited(with event: NSEvent) { setBarVisible(false) }

    private func setBarVisible(_ visible: Bool) {
        guard visible != pointerInside else { return }
        pointerInside = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            bar.animator().alphaValue = visible ? 1 : 0
        }
    }

    private func button(for control: ForkPinLayout.Control) -> NSView {
        let text = ForkStrings.current
        let upstream = FeatureStrings.screenshot(L10n.shared.language)
        let symbol: String
        let help: String
        switch control {
        case .close: (symbol, help) = ("xmark", L10n.shared.s.menuClose)
        case .restore: (symbol, help) = ("rectangle.stack", text.pinRestore)
        case .edit: (symbol, help) = ("pencil", upstream.editButton)
        case .save: (symbol, help) = ("square.and.arrow.down", upstream.saveAsButton)
        case .drag: (symbol, help) = ("hand.draw", text.pinDrag)
        case .shrink: (symbol, help) = ("minus", text.pinShrink)
        case .enlarge: (symbol, help) = ("plus", text.pinEnlarge)
        }
        let picture = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        let view: NSView
        if control == .drag {
            // Not a button: a press that moves starts a drag of the capture.
            view = ForkPinDragHandle(picture: picture) { [weak self] in
                guard let self else { return nil }
                return ScreenshotService.temporaryExportFile(image: self.image, scale: self.scale, strings: upstream)
            }
        } else {
            let button = ForkPinButton(image: picture ?? NSImage(), target: self, action: #selector(pressed(_:)))
            button.isBordered = false
            button.contentTintColor = .white
            button.tag = ForkPinLayout.Control.allCases.firstIndex(of: control) ?? 0
            view = button
        }
        view.toolTip = help
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: ForkPinLayout.buttonSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: ForkPinLayout.buttonSize).isActive = true
        return view
    }

    @objc private func pressed(_ sender: NSButton) {
        let all = ForkPinLayout.Control.allCases
        guard all.indices.contains(sender.tag) else { return }
        switch all[sender.tag] {
        case .close:
            close()
        case .restore:
            // Back among the previews at the bottom left, as a capture just taken would be.
            let capture = capture
            close()
            ScreenshotService.shared.restorePreview(capture)
        case .edit:
            // The editor's own closing brings the picture back as a preview.
            let capture = capture
            close()
            ScreenshotService.shared.openEditor(with: capture)
        case .save:
            save()
        case .shrink:
            zoom(by: 1 / ForkPinLayout.zoomStep)
        case .enlarge:
            zoom(by: ForkPinLayout.zoomStep)
        case .drag:
            break
        }
    }

    private func zoom(by factor: CGFloat) {
        guard let window else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let frame = ForkPinLayout.resized(window.frame, by: factor, minimum: window.minSize, within: screen)
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

/// A button that answers the first click, without the pin having to be
/// clicked once beforehand to wake it.
final class ForkPinButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The bar's drag handle: press, move, and the capture leaves as a file for
/// whatever app it is dropped on. The pin itself stays where it is.
final class ForkPinDragHandle: NSView, NSDraggingSource {
    private let picture: NSImage?
    private let file: () -> URL?
    private var pressOrigin: CGPoint?
    private var dragSession: NSDraggingSession?

    init(picture: NSImage?, file: @escaping () -> URL?) {
        self.picture = picture
        self.file = file
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A press here drags the capture out; it must not move the pin instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let picture else { return }
        let size = picture.size
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        // A template symbol draws black: tint it white like the buttons beside it.
        NSColor.white.set()
        picture.draw(in: rect)
        rect.fill(using: .sourceAtop)
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin,
              ForkPreviewCardLayout.isDrag(from: origin, to: convert(event.locationInWindow, from: nil))
        else { return }
        pressOrigin = nil
        guard let url = file() else {
            NSSound.beep()
            return
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(forFile: url.path))
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        dragSession = session
    }

    override func mouseUp(with event: NSEvent) {
        pressOrigin = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        dragSession = nil
    }
}
