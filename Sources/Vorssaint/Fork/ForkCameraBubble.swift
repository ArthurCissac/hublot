// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import AppKit

/// The camera bubble: a live picture of the person recording, round, square
/// or a 16:9 rectangle, shown inside the recorded area. It is an ordinary
/// window of the app, on screen before the recording starts, which is how it
/// ends up in the video: upstream's recorder keeps the app's ordinary windows
/// and builds its filter once, at the start.
///
/// Dragging it moves it; dragging its border, or pinching it, resizes it.
/// Both work before and during a recording, and neither shows anything in the
/// video but the bubble itself. Its shape is chosen in the recording bar, and
/// from its right-click menu once the recording runs.
///
/// It appears as a preview when the recording bar's camera option is on, stays
/// for the length of the recording, and leaves with it. Main thread only.
final class ForkCameraBubble: NSObject {
    typealias Layout = ForkCameraBubbleLayout

    static let shared = ForkCameraBubble()

    private var panel: NSPanel?
    private var view: ForkCameraBubbleView?
    /// The camera's picture, cut to the shape by `mask`, with `border` drawn on the same outline:
    /// a preview layer's own rounded corners do not reliably clip the video it shows.
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "agency.nexflow.hublot.camera-bubble")
    private var watcher: Timer?
    private var recording = false
    private var sawCapture = false
    private var deadline = Date.distantPast
    private var shape = Layout.Shape.circle

    /// What macOS says about this app and the camera.
    enum Access {
        case allowed, undetermined, refused
    }

    static var access: Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .notDetermined: return .undetermined
        default: return .refused
        }
    }

    /// Has macOS put its question on screen; answers on the main thread. The
    /// caller clears the screen first: the capture menu sits above everything,
    /// that question included.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    var isShown: Bool { panel != nil }

    /// Shows the bubble as a preview, in the remembered shape and size, at the
    /// area's bottom right corner. A bubble already there only takes the shape
    /// the recording bar may just have changed. Never asks for the camera: a
    /// bubble is only wanted once access was given.
    func showPreview(in area: CGRect, screen: CGRect) {
        guard Self.access == .allowed else { return }
        let defaults = UserDefaults.standard
        let stored = Layout.shape(stored: defaults.string(forKey: DefaultsKey.forkRecorderCameraShape))
        guard panel == nil else {
            setShape(stored)
            return
        }
        shape = stored
        let size = Layout.size(stored: defaults.double(forKey: DefaultsKey.forkRecorderCameraSize))
        present(at: Layout.frame(shape: stored, size: size, in: area, screen: screen))
    }

    /// Puts a preview away. A bubble kept for a recording stays.
    func hidePreview() {
        guard !recording else { return }
        hide()
    }

    /// The recording is about to start: the bubble stays until it is over.
    /// Upstream gives no signal for that, so a light timer, alive only while
    /// the bubble is shown, looks; it also gives up if no recording ever starts.
    func keepForRecording(startingWithin seconds: TimeInterval) {
        guard let panel else { return }
        recording = true
        // The capture menu is gone: back among ordinary floating windows, under menus.
        panel.level = .floating
        sawCapture = false
        deadline = Date().addingTimeInterval(seconds + 8)
        watcher?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.watch() }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    private func watch() {
        if ScreenRecorderService.shared.hasActiveCapture {
            sawCapture = true
        } else if sawCapture || Date() > deadline {
            hide()
        }
    }

    private func hide() {
        watcher?.invalidate()
        watcher = nil
        recording = false
        panel?.orderOut(nil)
        panel = nil
        view = nil
        previewLayer = nil
        if let session {
            self.session = nil
            sessionQueue.async { session.stopRunning() }
        }
    }

    // MARK: - Shape and size

    private func setShape(_ shape: Layout.Shape) {
        guard shape != self.shape else { return }
        self.shape = shape
        guard let panel else { return }
        apply(Layout.reshaped(panel.frame, to: shape, within: screenFrame(of: panel)))
    }

    /// A drag of the border or a pinch, measured from the frame the gesture began with.
    private func resize(_ start: CGRect, by factor: CGFloat) {
        guard let panel else { return }
        apply(Layout.scaled(start, shape: shape, by: factor, within: screenFrame(of: panel)))
    }

    /// The size the gesture ended on is the one the next bubble starts with.
    private func rememberSize() {
        guard let panel else { return }
        UserDefaults.standard.set(Double(panel.frame.height), forKey: DefaultsKey.forkRecorderCameraSize)
    }

    /// Never animated: a window whose size changes mid-animation draws its content at the wrong place.
    private func apply(_ frame: CGRect) {
        guard let panel, let view else { return }
        view.shape = shape
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(frame, display: true)
        outline(CGRect(origin: .zero, size: frame.size))
        CATransaction.commit()
        panel.invalidateShadow()
    }

    /// The shape, for the picture's mask and for its border: one path, so they always agree.
    private func outline(_ bounds: CGRect) {
        let radius = Layout.cornerRadius(shape: shape, height: bounds.height)
        previewLayer?.frame = bounds
        maskLayer.frame = bounds
        maskLayer.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let inset = bounds.insetBy(dx: 1, dy: 1)
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: inset, cornerWidth: max(0, radius - 1), cornerHeight: max(0, radius - 1),
                                  transform: nil)
    }

    private func screenFrame(of panel: NSPanel) -> CGRect {
        panel.screen?.frame ?? NSScreen.main?.frame ?? panel.frame
    }

    /// The right-click menu: the shapes. Only once the recording runs: during
    /// the preview the capture menu's windows would cover it, and the
    /// recording bar offers the same choice.
    private func shapeMenu() -> NSMenu? {
        guard recording else { return nil }
        let text = ForkStrings.current
        let menu = NSMenu()
        for shape in Layout.Shape.allCases {
            let item = NSMenuItem(title: text.name(of: shape), action: #selector(shapePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shape.rawValue
            item.state = shape == self.shape ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func shapePicked(_ sender: NSMenuItem) {
        let shape = Layout.shape(stored: sender.representedObject as? String)
        UserDefaults.standard.set(shape.rawValue, forKey: DefaultsKey.forkRecorderCameraShape)
        setShape(shape)
    }

    // MARK: - Window and camera

    private func present(at frame: CGRect) {
        guard panel == nil else { return }
        // The window comes up at once, dark; the camera is opened off the main
        // thread, where it takes long enough to freeze the screen, and its
        // picture fills the bubble when it is ready.
        let session = AVCaptureSession()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        let container = CALayer()
        container.addSublayer(preview)
        container.mask = maskLayer
        borderLayer.fillColor = nil
        borderLayer.strokeColor = CGColor(gray: 1, alpha: 0.75)
        borderLayer.lineWidth = 2
        container.addSublayer(borderLayer)
        previewLayer = preview

        let view = ForkCameraBubbleView(frame: CGRect(origin: .zero, size: frame.size), shape: shape)
        view.layer = container
        view.wantsLayer = true
        outline(CGRect(origin: .zero, size: frame.size))
        view.onResize = { [weak self] start, factor in self?.resize(start, by: factor) }
        view.onResizeEnded = { [weak self] in self?.rememberSize() }
        view.menuProvider = { [weak self] in self?.shapeMenu() }

        let panel = ForkCameraBubblePanel(contentRect: frame,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered,
                                          defer: false)
        panel.contentView = view
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Said explicitly so macOS does not guess which parts of a see-through window take the mouse.
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        // Above the capture menu's windows while it previews, so it can be moved and resized
        // before the recording starts; back to a floating window once it does.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.view = view
        self.session = session

        sessionQueue.async { [weak self] in
            guard let device = AVCaptureDevice.userPreferredCamera ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                DispatchQueue.main.async { self?.cameraFailed(session) }
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async {
                // A mirror image, as in every video call: moving left moves left.
                if let connection = preview.connection, connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
        }
    }

    /// No camera to open: the bubble it was meant for goes away.
    private func cameraFailed(_ session: AVCaptureSession) {
        guard self.session === session else { return }
        recording = false
        hide()
        NSSound.beep()
    }
}

/// The bubble's picture and its gestures: a press on the border resizes, a
/// press anywhere else moves the window, a pinch resizes, a right click asks
/// for the menu.
final class ForkCameraBubbleView: NSView {
    typealias Layout = ForkCameraBubbleLayout

    var shape: Layout.Shape
    /// The frame the gesture began with, and the factor it asks for since.
    var onResize: ((CGRect, CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private var borderDrag: (pointer: CGPoint, frame: CGRect)?
    private var pinch: (frame: CGRect, factor: CGFloat)?
    private var tracking: NSTrackingArea?

    init(frame: CGRect, shape: Layout.Shape) {
        self.shape = shape
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The first click acts: the bubble never has to be woken first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Moving is decided here, press by press, not by AppKit for the whole window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if Layout.isOnEdge(convert(event.locationInWindow, from: nil), in: bounds.size, shape: shape) {
            borderDrag = (NSEvent.mouseLocation, window.frame)
        } else {
            borderDrag = nil
            window.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let borderDrag else { return }
        let center = CGPoint(x: borderDrag.frame.midX, y: borderDrag.frame.midY)
        onResize?(borderDrag.frame,
                  Layout.resizeFactor(from: borderDrag.pointer, to: NSEvent.mouseLocation, center: center))
    }

    override func mouseUp(with event: NSEvent) {
        guard borderDrag != nil else { return }
        borderDrag = nil
        onResizeEnded?()
    }

    override func magnify(with event: NSEvent) {
        guard let window else { return }
        var current = pinch ?? (window.frame, 1)
        if event.phase == .began { current = (window.frame, 1) }
        // Each event carries the change since the previous one.
        current.factor *= 1 + event.magnification
        pinch = current
        onResize?(current.frame, current.factor)
        if event.phase == .ended || event.phase == .cancelled {
            pinch = nil
            onResizeEnded?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // The pointer says what a press would do. Best effort: an app in the
    // background does not always get to set it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let onEdge = Layout.isOnEdge(convert(event.locationInWindow, from: nil), in: bounds.size, shape: shape)
        (onEdge ? Self.resizeCursor : NSCursor.openHand).set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private static var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: .bottomRight, directions: .all)
        }
        return .crosshair
    }
}

/// The bubble's window: it never takes the keyboard.
final class ForkCameraBubblePanel: OverlayPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension ForkStrings {
    func name(of shape: ForkCameraBubbleLayout.Shape) -> String {
        switch shape {
        case .circle: return cameraShapeCircle
        case .square: return cameraShapeSquare
        case .rectangle: return cameraShapeRectangle
        }
    }
}
