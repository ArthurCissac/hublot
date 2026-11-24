// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The scrolling capture's controls, in place of upstream's: Cancel,
/// Auto-scroll and Done, in a strip above the area. Return finishes, Escape
/// cancels. Once Auto-scroll is on the pointer steers it: the further it goes
/// down from where it clicked, the faster the page scrolls; back up there, it
/// stops (see `ForkCursorScroll`). Scrolling by hand keeps working meanwhile.
///
/// Upstream's capture runs as it does when scrolled by hand: it watches the
/// pixels, and these scroll events are one more hand. They go where the
/// pointer is, as a hand's would, and only while it is over the page: an
/// event placed anywhere else drags the pointer there. Upstream's own
/// step-by-step automatic mode stays off while these controls are on.
/// Called by upstream's screenshot service, from the main thread only.
final class ForkScrollingControls {
    static let shared = ForkScrollingControls()

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkScrollingControls) }

    private var panel: Panel?
    private let model = Model()
    private var region: RecorderSupport.Region?
    private var onFinish: (() -> Void)?
    private var onCancel: (() -> Void)?

    /// What the auto-scroll scrolls: the window under the middle of the area
    /// when it was switched on.
    private struct Target {
        let windowID: CGWindowID
        let processID: pid_t
    }

    private var keyMonitors: [Any] = []
    private var timer: Timer?
    private var target: Target?
    private var start = CGPoint.zero
    private var horizontal = false
    private var maxSpeed: CGFloat = 0
    private var smoother = ForkCursorScroll.Smoother()
    private var accumulator = ForkCursorScroll.Accumulator()
    private var lastTick: TimeInterval = 0

    private init() {}

    /// The strip's window and the live preview's, for the capture engine to leave out.
    var windowIDs: Set<CGWindowID> {
        var ids = ForkScrollingPreview.shared.windowIDs
        if let panel, panel.isVisible, panel.windowNumber > 0 { ids.insert(CGWindowID(panel.windowNumber)) }
        return ids
    }

    /// Takes over from upstream's controls, just shown, for a capture of
    /// `region`. False, and upstream's controls stay, when the setting is off.
    @discardableResult
    func show(region: RecorderSupport.Region, onFinish: @escaping () -> Void,
              onCancel: @escaping () -> Void) -> Bool {
        guard Self.isEnabled else { return false }
        QuickToolHUD.dismissScrollingCapture()
        stopAuto()
        self.region = region
        self.onFinish = onFinish
        self.onCancel = onCancel
        model.height = 0
        model.autoOn = false
        model.finishing = false
        model.horizontal = ForkScrollingDirection.isArmedHorizontal()

        let host = Host(rootView: ControlsView(model: model,
                                               toggleAuto: { [weak self] in self?.toggleAuto() },
                                               finish: { [weak self] in self?.finish() },
                                               cancel: { [weak self] in self?.cancel() }))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.contentView = host
        let area = region.anchorRect
        let screen = NSScreen.screens.max {
            $0.frame.intersection(area).width * $0.frame.intersection(area).height
                < $1.frame.intersection(area).width * $1.frame.intersection(area).height
        } ?? NSScreen.main
        panel.setFrame(ForkCursorScroll.controlsFrame(size: size, area: area,
                                                      screen: screen?.visibleFrame ?? area),
                       display: true)
        panel.orderFrontRegardless()
        // Key without making the app active, so Return and Escape stay out of the page.
        panel.makeKey()
        // The capture menu hands the keyboard back to the app in front as it
        // closes, and that can land after this: the strip takes it once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.onCancel != nil, let panel = self.panel, panel.isVisible else { return }
            panel.makeKey()
        }
        watchEscape()
        // The column beside the area, before the first picture so it is left out of all of them.
        ForkScrollingPreview.shared.show(region: region)
        return true
    }

    /// Escape cancels from anywhere, whichever window has the keyboard, as
    /// the capture menu's does: watched here and outside, only while the strip
    /// is up. Outside, the key is only listened to and still reaches the app.
    private func watchEscape() {
        guard keyMonitors.isEmpty else { return }
        let escape: UInt16 = 53
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escape, let self, self.onCancel != nil else { return event }
            self.cancel()
            return nil
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escape else { return }
            DispatchQueue.main.async {
                guard let self, self.onCancel != nil else { return }
                self.cancel()
            }
        }
        keyMonitors = [local, global].compactMap { $0 }
    }

    func update(height: Int) {
        model.height = height
    }

    func dismiss() {
        stopAuto()
        ForkScrollingPreview.shared.hide()
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors = []
        panel?.orderOut(nil)
        panel?.contentView = nil
        region = nil
        onFinish = nil
        onCancel = nil
    }

    // MARK: - Buttons

    private func finish() {
        guard !model.finishing else { return }
        model.finishing = true
        // Still pages give the last picture at once.
        stopAuto()
        onFinish?()
    }

    private func cancel() {
        stopAuto()
        let cancel = onCancel
        // Once: Escape may come both from the strip and from the watch.
        onCancel = nil
        cancel?()
    }

    private func toggleAuto() {
        guard !model.finishing else { return }
        if model.autoOn {
            stopAuto()
            return
        }
        guard CGPreflightPostEventAccess() else {
            Permissions.shared.requestAccessibility()
            return
        }
        guard let region, let target = Self.target(for: region, excluding: windowIDs) else {
            QuickToolHUD.show(icon: "rectangle.stack", message: ForkScrollingStrings.current.noPage)
            return
        }
        self.target = target
        // The direction was settled at the capture's first picture.
        horizontal = ForkScrollingDirection.isHorizontal
        model.horizontal = horizontal
        start = NSEvent.mouseLocation
        maxSpeed = ForkCursorScroll.maxSpeed(
            areaLength: horizontal ? region.anchorRect.width : region.anchorRect.height)
        smoother = ForkCursorScroll.Smoother()
        accumulator = ForkCursorScroll.Accumulator()
        lastTick = ProcessInfo.processInfo.systemUptime
        model.autoOn = true
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        panel?.makeKey()
    }

    private func stopAuto() {
        timer?.invalidate()
        timer = nil
        target = nil
        model.autoOn = false
    }

    // MARK: - Scrolling

    private func tick() {
        guard let target else {
            stopAuto()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let interval = min(0.05, max(0, now - lastTick))
        lastTick = now
        let pointer = NSEvent.mouseLocation
        let distance = ForkCursorScroll.distance(from: start, to: pointer, horizontal: horizontal)
        let speed = smoother.next(target: ForkCursorScroll.speed(distance: distance, maxSpeed: maxSpeed),
                                  interval: interval)
        let step = accumulator.step(speed: speed, interval: interval)
        // Over the strip, another window or the desktop, nothing scrolls:
        // the page only, the one the capture is of.
        guard step > 0,
              NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0) == Int(target.windowID),
              let event = Self.scrollEvent(processID: target.processID, step: step, horizontal: horizontal)
        else { return }
        event.post(tap: .cgSessionEventTap)
    }

    /// The window under the middle of the area, as upstream's automatic
    /// scroller finds it; nil when there is none, or it is not the window the
    /// capture is of.
    private static func target(for region: RecorderSupport.Region, excluding own: Set<CGWindowID>) -> Target? {
        guard let mainHeight = NSScreen.screens.first?.frame.maxY else { return nil }
        let point = CGPoint(x: region.anchorRect.midX, y: mainHeight - region.anchorRect.midY)
        guard let id = WindowServerSupport.receivingWindow(at: point), !own.contains(id),
              region.windowID == nil || region.windowID == id,
              let pid = WindowServerSupport.ownerProcessID(ofWindowID: id), pid > 0
        else { return nil }
        return Target(windowID: id, processID: pid)
    }

    /// One scroll event of `step` points, down or right, tagged like
    /// upstream's own so its smoothing and inversion leave it alone. Its
    /// location is left as created, where the pointer is: posted elsewhere,
    /// the event would pull the pointer there, sixty times a second.
    static func scrollEvent(processID: pid_t, step: Int32, horizontal: Bool) -> CGEvent? {
        guard step > 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: horizontal ? 2 : 1, wheel1: horizontal ? 0 : -step,
                                  wheel2: horizontal ? -step : 0, wheel3: 0)
        else { return nil }
        event.flags = []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(processID))
        event.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        event.setIntegerValueField(.eventSourceUnixProcessID,
                                   value: Int64(ProcessInfo.processInfo.processIdentifier))
        return event
    }

    // MARK: - Window

    private static func makePanel() -> Panel {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }

    /// Non-activating, yet able to take Return and Escape.
    private final class Panel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class Host: NSHostingView<ControlsView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    fileprivate final class Model: ObservableObject {
        @Published var height = 0
        @Published var autoOn = false
        @Published var finishing = false
        @Published var horizontal = false
    }
}

private struct ControlsView: View {
    @ObservedObject var model: ForkScrollingControls.Model
    let toggleAuto: () -> Void
    let finish: () -> Void
    let cancel: () -> Void

    var body: some View {
        let text = ForkScrollingStrings.current
        HStack(spacing: 6) {
            Button(action: cancel) {
                pill(text.cancel, systemImage: "xmark")
            }
            .buttonStyle(PillStyle(fill: Color.white.opacity(0.14), ink: .white))
            .keyboardShortcut(.cancelAction)

            Button(action: toggleAuto) {
                // Both labels laid over each other, so the strip keeps its width.
                ZStack {
                    pill(text.auto, systemImage: arrow).opacity(model.autoOn ? 0 : 1)
                    pill(model.horizontal ? text.autoOnRight : text.autoOnDown, systemImage: arrow)
                        .opacity(model.autoOn ? 1 : 0)
                }
            }
            .buttonStyle(PillStyle(fill: model.autoOn ? Color.accentColor : Color.white.opacity(0.14), ink: .white))
            .disabled(model.finishing)
            .screenshotSafeHelp(model.horizontal ? text.autoHelpRight : text.autoHelpDown)

            Text("\(model.height) px")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 62)

            Button(action: finish) {
                ZStack {
                    pill(text.done, systemImage: "checkmark").opacity(model.finishing ? 0 : 1)
                    ProgressView().controlSize(.small).environment(\.colorScheme, .light)
                        .opacity(model.finishing ? 1 : 0)
                }
            }
            .buttonStyle(PillStyle(fill: .white, ink: .black))
            .keyboardShortcut(.defaultAction)
            .disabled(model.finishing)
        }
        .padding(5)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.78)))
        .environment(\.colorScheme, .dark)
    }

    private var arrow: String { model.horizontal ? "arrow.right" : "arrow.down" }

    private func pill(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .fixedSize()
    }
}

private struct PillStyle: ButtonStyle {
    let fill: Color
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule(style: .continuous).fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule(style: .continuous))
    }
}
