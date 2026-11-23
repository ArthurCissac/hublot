// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// What the card's drawing follows: the pointer, a press, and what is done.
final class ForkPreviewCardModel: ObservableObject {
    @Published var hovered = false
    @Published var highlighted: ForkPreviewCardLayout.Control?
    @Published var pressed: ForkPreviewCardLayout.Control?
    @Published var copied = false
    /// Actions the after-capture action already carried out.
    @Published var disabled: Set<ForkPreviewCardLayout.Control>

    init(disabled: Set<ForkPreviewCardLayout.Control>) {
        self.disabled = disabled
    }

    /// Confirms a copy on the button itself, since the card stays.
    func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.copied = false }
    }
}

/// The card's drawing, and only its drawing: it takes no event. The fork's own
/// design, drawn with system symbols; the frames come from
/// `ForkPreviewCardLayout`, which the event view reads too.
struct ForkPreviewCardView: View {
    let image: CGImage
    let strings: ScreenshotFeatureStrings
    @ObservedObject var model: ForkPreviewCardModel

    var body: some View {
        let size = ForkPreviewCardLayout.cardSize
        let shape = RoundedRectangle(cornerRadius: ForkPreviewCardLayout.cornerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            Color.black.opacity(model.hovered ? 0.42 : 0)
            if model.hovered {
                ForEach(ForkPreviewCardLayout.Control.allCases, id: \.self) { control in
                    self.control(control)
                }
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: model.hovered)
        .allowsHitTesting(false)
    }

    private func control(_ control: ForkPreviewCardLayout.Control) -> some View {
        let frame = ForkPreviewCardLayout.controlFrame(control)
        return label(for: control)
            .foregroundColor(Color.black.opacity(0.85))
            .frame(width: frame.width, height: frame.height)
            .background(Capsule().fill(Color.white.opacity(fill(for: control))))
            .opacity(model.disabled.contains(control) ? 0.45 : 1)
            .offset(x: frame.minX, y: frame.minY)
    }

    @ViewBuilder
    private func label(for control: ForkPreviewCardLayout.Control) -> some View {
        switch control {
        case .close: symbol("xmark")
        case .pin: symbol("pin.fill")
        case .edit: symbol("pencil")
        case .discard: symbol("trash")
        case .copy:
            HStack(spacing: 4) {
                if model.copied { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(strings.copyButton).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
        case .save:
            Text(strings.saveButton).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 10, weight: .bold))
    }

    private func fill(for control: ForkPreviewCardLayout.Control) -> Double {
        if model.pressed == control { return 0.7 }
        return model.highlighted == control ? 1 : 0.88
    }
}

/// Takes every event of the card: hover, clicks on the controls, and the drag
/// of the capture into another app.
///
/// AppKit rather than SwiftUI gestures on purpose. The card's panel never
/// becomes key, so a capture preview cannot take the keyboard from the app
/// being typed into, and SwiftUI hover and buttons are unreliable in a window
/// that is not key. A tracking area marked `activeAlways` and plain mouse
/// events work whatever the window's state.
final class ForkPreviewCardEventView: NSView, NSDraggingSource {
    private let model: ForkPreviewCardModel
    private let activate: (ForkPreviewCardLayout.ClickTarget) -> Void
    private let dragFile: () -> URL?
    private let dragBegan: () -> Void
    private let dragEnded: (_ delivered: Bool) -> Void
    private let dragPreview: NSImage
    private var pressOrigin: CGPoint?
    private var pressedControl: ForkPreviewCardLayout.Control?
    private var tracking: NSTrackingArea?
    private var dragSession: NSDraggingSession?
    /// The pointer came over the card, or left it.
    var hover: ((Bool) -> Void)?
    /// A scroll over the card: two fingers sideways put it away.
    var scroll: ((NSEvent) -> Void)?

    init(model: ForkPreviewCardModel,
         content: NSView,
         dragPreview: NSImage,
         activate: @escaping (ForkPreviewCardLayout.ClickTarget) -> Void,
         dragFile: @escaping () -> URL?,
         dragBegan: @escaping () -> Void,
         dragEnded: @escaping (_ delivered: Bool) -> Void) {
        self.model = model
        self.activate = activate
        self.dragFile = dragFile
        self.dragBegan = dragBegan
        self.dragEnded = dragEnded
        self.dragPreview = dragPreview
        super.init(frame: CGRect(origin: .zero, size: ForkPreviewCardLayout.cardSize))
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Top-left origin, the same space as `ForkPreviewCardLayout.controlFrame`.
    override var isFlipped: Bool { true }

    /// The drawing below never sees an event.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /// A press on the card acts at once, without first having to wake the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hover?(true)
        model.hovered = true
        model.highlighted = control(under: event)
    }

    override func mouseMoved(with event: NSEvent) {
        model.hovered = true
        model.highlighted = control(under: event)
    }

    override func scrollWheel(with event: NSEvent) {
        scroll?(event)
    }

    override func mouseExited(with event: NSEvent) {
        hover?(false)
        model.hovered = false
        model.highlighted = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressOrigin = point
        if case .control(let control) = ForkPreviewCardLayout.clickTarget(at: point, controlsVisible: model.hovered) {
            pressedControl = control
        } else {
            pressedControl = nil
        }
        model.pressed = pressedControl
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let pressedControl {
            // Sliding off a control before releasing cancels it, like any button.
            model.pressed = ForkPreviewCardLayout.control(at: point) == pressedControl ? pressedControl : nil
            return
        }
        guard let origin = pressOrigin, ForkPreviewCardLayout.isDrag(from: origin, to: point) else { return }
        pressOrigin = nil
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressOrigin = nil
            pressedControl = nil
            model.pressed = nil
        }
        if let pressedControl {
            if control(under: event) == pressedControl { activate(.control(pressedControl)) }
            return
        }
        // A press on the picture that never turned into a drag is a click on it.
        if pressOrigin != nil { activate(.picture) }
    }

    private func control(under event: NSEvent) -> ForkPreviewCardLayout.Control? {
        ForkPreviewCardLayout.control(at: convert(event.locationInWindow, from: nil))
    }

    private func beginDrag(with event: NSEvent) {
        guard let url = dragFile() else {
            NSSound.beep()
            return
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        // What follows the pointer is the card as it looks, so the card itself
        // seems to leave its place; the owner hides the real one meanwhile.
        item.setDraggingFrame(bounds, contents: dragPreview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // Dropped nowhere, the picture flies back to where it came from.
        session.animatesToStartingPositionsOnCancelOrFail = true
        dragSession = session
        model.hovered = false
        model.highlighted = nil
        dragBegan()
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        dragSession = nil
        dragEnded(!operation.isEmpty)
    }
}
