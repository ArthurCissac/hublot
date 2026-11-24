// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import QuartzCore
import SwiftUI

/// The capture menu: its global shortcut shows its bar, alone, over the last
/// area, or over a new selection, as set. The Area item draws an area and
/// photographs it as soon as it is drawn, as Shift-Command-4 does, or frames
/// it to be adjusted first. An area drawn otherwise stays on screen, framed,
/// with the bar under it, and the bar's buttons decide what is done with it
/// (a picture, a scrolling capture, its text, a recording) or change a
/// setting first. A scrolling capture starts as soon as its area is drawn, its
/// window clicked, or Return takes the whole display; a recording opens a short
/// bar of its own, with its options and a start button, and films an area, a
/// window or the whole display.
///
/// The selection is upstream's own surface, run here in its "where" mode, and
/// each action hands the area to the entry point upstream's tools already
/// accept one through. Started once from `ForkBootstrap`; no upstream file
/// calls it. Used from the main thread only.
final class ForkCaptureMenu: ObservableObject {
    typealias Mode = ForkCaptureMenuLayout.Mode

    static let shared = ForkCaptureMenu()

    /// True when macOS refused the shortcut, usually because another app holds it.
    @Published private(set) var shortcutUnavailable = false

    /// Outside the ids upstream gives its own quick-tool hotkeys.
    private let hotkey = QuickToolHotkey(id: 9_101)
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.syncWithPreferences() }
    private let model = ForkCaptureMenuModel()
    private var bar: ForkCaptureMenuPanel?
    private var frame: ForkCaptureAreaPanel?
    private var selection: ScreenshotSelectionController?
    private var area: RecorderSupport.Region?
    /// The microphones macOS lists, read off the main thread each time the menu
    /// opens: asking takes long enough to freeze the screen for a moment.
    private var microphones: [ForkRecorderMicrophone.Device] = []
    /// A mode picked before any area was drawn: it runs as soon as one is.
    private var armed: Mode?
    /// The app in front when the menu opened, brought back when it closes.
    private var appInFront: NSRunningApplication?
    /// Watching for Escape, in this app and outside it, while the menu is open.
    private var escapeMonitors: [Any] = []
    private var mainModes: [Mode] = []
    private var screenFrame = CGRect.zero
    private var audio = RecorderSelectionAudioOptions()

    /// The menu's windows, for the capture engine to leave out of every picture.
    var windowIDs: Set<CGWindowID> {
        Set([bar, frame].compactMap { panel -> CGWindowID? in
            guard let panel, panel.windowNumber > 0 else { return nil }
            return CGWindowID(panel.windowNumber)
        })
    }

    func start() {
        hotkey.onPress = { [weak self] in self?.toggle() }
        // The hotkey needs the app's event dispatcher: register once the run
        // loop is going, then again whenever a setting changes or the app
        // comes and goes. Upstream releases every hotkey while a shortcut
        // field is listening; coming back from Settings takes this one again.
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

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: DefaultsKey.forkCaptureMenuShortcutEnabled)
            && AppFeature.screenshot.isAvailable
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.forkCaptureMenuShortcut,
                                            fallback: ForkCaptureMenuLayout.defaultShortcut)
        let registered = hotkey.sync(enabled: enabled, shortcut: shortcut,
                                     storageKey: DefaultsKey.forkCaptureMenuShortcut)
        let unavailable = enabled && !registered
        if unavailable != shortcutUnavailable { shortcutUnavailable = unavailable }
        if !enabled { close() }
    }

    /// The shortcut as the keyboard prints it, for the settings row.
    static var shortcutDisplayString: String {
        GlobalShortcut.saved(for: DefaultsKey.forkCaptureMenuShortcut,
                             fallback: ForkCaptureMenuLayout.defaultShortcut).displayString
    }

    private var isOpen: Bool { bar != nil }

    /// The shortcut again, with the menu open, puts everything away.
    private func toggle() {
        if isOpen { close() } else { open() }
    }

    // MARK: - Opening, selecting, closing

    private func open() {
        guard !isOpen, !ScreenshotSelectionController.isSessionOnScreen,
              !ScreenshotService.shared.hasActiveCapture,
              !ScreenRecorderService.shared.hasActiveCapture else { return }
        let defaults = UserDefaults.standard
        let modes = ForkCaptureMenuLayout.modes(available: ScreenCaptureTool.available(),
                                                stored: defaults.string(forKey: DefaultsKey.forkCaptureMenuItems))
        guard !modes.isEmpty,
              let screen = ForkPreviewCardLayout.screenFrame(pointer: NSEvent.mouseLocation,
                                                             screenFrames: NSScreen.screens.map(\.frame))
        else {
            NSSound.beep()
            return
        }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        mainModes = modes
        screenFrame = screen
        appInFront = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0
        }
        armed = nil
        audio = RecorderSelectionAudioOptions()
        model.delay = 0  // each opening starts without a timer
        refreshMicrophones()
        readSettings()
        model.modes = modes
        model.active = nil
        model.highlighted = nil
        model.pressed = nil
        showBar(at: ForkCaptureMenuLayout.barFrame(modes: modes, in: screen))
        ForkBackgroundCursor.setAllowed(true, by: .captureMenu)
        watchEscape()
        switch ForkCaptureMenuLayout.Opening.stored(defaults.string(forKey: DefaultsKey.forkCaptureMenuOpening)) {
        case .bar:
            // The bar alone: an item is picked first, then its area drawn if it needs one.
            break
        case .lastArea:
            // The last area comes back framed; a click beside it draws a new one.
            if let remembered = rememberedRegion(on: screen) { areaChosen(remembered) } else { beginSelection() }
        case .select:
            beginSelection()
        }
    }

    /// Escape leaves the menu from anywhere, whichever window has the keyboard
    /// and whichever app is in front: the key is watched in this app and
    /// outside it, as upstream's selection does, and only while the menu is open.
    private func watchEscape() {
        guard escapeMonitors.isEmpty else { return }
        let escape: UInt16 = 53
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escape, let self, self.isOpen else { return event }
            self.close()
            return nil
        }
        // Listening only: the key still reaches the app in front.
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escape else { return }
            DispatchQueue.main.async {
                guard let self, self.isOpen else { return }
                self.close()
            }
        }
        escapeMonitors = [local, global].compactMap { $0 }
    }

    private func stopWatchingEscape() {
        escapeMonitors.forEach { NSEvent.removeMonitor($0) }
        escapeMonitors = []
    }

    /// Upstream's selection surface, asked for an area only: nothing is
    /// photographed, and a click on a window gives that window's frame.
    private func beginSelection() {
        frame?.orderOut(nil)
        frame = nil
        area = nil
        ForkCameraBubble.shared.hidePreview()
        let previous = selection
        selection = nil
        previous?.cancel()
        // The bar already says what can be done: upstream's hint bar stays away.
        ForkCaptureSelectionGuide.isHidden = true

        let controller = ScreenshotSelectionController(
            freeze: false,
            includePointer: false,
            showLastRegion: false,
            hideVorssaintWindows: true,
            protectedWindowIDs: {
                ScreenshotService.shared.protectedWindowIDsForCapture(honoursVisibilityPreference: false)
            },
            purpose: FeatureStrings.screenshot(L10n.shared.language).screenCaptureTitle,
            mode: .geometry)
        selection = controller
        controller.begin { [weak self, weak controller] outcome in
            // A selection this menu has replaced or cancelled reports nothing.
            guard let self, let controller, self.selection === controller else { return }
            self.selection = nil
            switch outcome {
            case .region(let region), .scrollingRegion(let region):
                self.areaChosen(region)
            case .captured, .color, .cancelled, .failed:
                self.close()
            }
        }
    }

    /// The area is kept, framed, with the bar under it. A mode picked
    /// beforehand runs on it at once.
    private func areaChosen(_ region: RecorderSupport.Region) {
        // "Window" was picked first: the window clicked is photographed at once,
        // without stopping at a framed area. A drag still frames its area.
        if armed == .window, region.windowID != nil {
            armed = nil
            run(.area, on: region)
            return
        }
        // "Area" was picked first: the area drawn is photographed as soon as
        // the mouse lets go, as with Shift-Command-4.
        if armed == .area {
            armed = nil
            remember(region)
            run(.area, on: region)
            return
        }
        // A scrolling capture runs on what was picked: the area drawn, the
        // window clicked, or the whole display, which Return gives.
        if armed == .scrolling {
            armed = nil
            remember(region)
            run(.scrolling, on: region)
            return
        }
        area = region
        if let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) {
            screenFrame = screen.frame
        }
        remember(region)
        showFrame(around: region.anchorRect)
        moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, under: region.anchorRect, in: screenFrame))
        if let armed, armed.needsArea {
            self.armed = nil
            choose(armed)
        } else {
            armed = nil
            model.active = .area
        }
        // The camera bubble follows the area: back to its bottom right corner.
        syncCamera()
    }

    private func close() {
        let previous = selection
        selection = nil
        previous?.cancel()
        area = nil
        armed = nil
        stopWatchingEscape()
        ForkCaptureSelectionGuide.isHidden = false
        // A camera preview goes too; a bubble kept for a recording stays.
        ForkCameraBubble.shared.hidePreview()
        // Gone at once: whatever is captured next must not show the menu.
        frame?.orderOut(nil)
        frame = nil
        bar?.orderOut(nil)
        bar = nil
        ForkBackgroundCursor.setAllowed(false, by: .captureMenu)
        NSCursor.arrow.set()
        // The app that was in front gets the keyboard back.
        if NSApp.isActive, let appInFront, !appInFront.isTerminated { appInFront.activate() }
        appInFront = nil
    }

    // MARK: - Choosing

    private func choose(_ mode: Mode) {
        guard isOpen else { return }
        let defaults = UserDefaults.standard
        switch mode {
        case .timer:
            // The menu's own timer, for the capture taken from it only: written to
            // the shared delay, it made ⇧⌘3 and ⇧⌘4 count down too, then select again.
            model.delay = ForkCaptureMenuLayout.nextDelay(after: model.delay, allowed: ScreenshotSupport.allowedDelays)
        case .microphone:
            // One step per click: the Mac's microphone, each other one, then off.
            let next = ForkRecorderMicrophone.next(
                enabled: audio.microphone,
                storedID: defaults.string(forKey: DefaultsKey.forkRecorderMicrophoneID) ?? "",
                among: microphones)
            defaults.set(next.id, forKey: DefaultsKey.forkRecorderMicrophoneID)
            audio.microphone = next.enabled
        case .camera:
            guard !model.camera else {
                defaults.set(false, forKey: DefaultsKey.forkRecorderCamera)
                break
            }
            switch ForkCameraBubble.access {
            case .allowed:
                defaults.set(true, forKey: DefaultsKey.forkRecorderCamera)
            case .undetermined:
                // macOS has a question to ask, and the menu's windows would cover it: the menu
                // leaves, and is opened again by hand once the question is answered.
                close()
                ForkCameraBubble.requestAccess { granted in
                    defaults.set(granted, forKey: DefaultsKey.forkRecorderCamera)
                    let text = ForkStrings.current
                    QuickToolHUD.show(icon: granted ? "person.crop.circle" : "video.slash",
                                      message: granted ? text.cameraAllowed : text.cameraRefused)
                }
                return
            case .refused:
                close()
                QuickToolHUD.show(icon: "video.slash", message: ForkStrings.current.cameraRefused)
                return
            }
        case .cameraShape:
            defaults.set(model.cameraShape.next.rawValue, forKey: DefaultsKey.forkRecorderCameraShape)
        case .systemAudio:
            audio.systemAudio.toggle()
        case .mono:
            defaults.set(!model.mono, forKey: DefaultsKey.forkRecorderMonoAudio)
        case .clicks:
            defaults.set(!model.clicks, forKey: DefaultsKey.forkRecorderShowsClicks)
        case .keys:
            defaults.set(!model.keys, forKey: DefaultsKey.forkRecorderShowsKeys)
        case .countdown:
            defaults.set(ForkCaptureMenuLayout.nextDelay(after: model.countdown,
                                                         allowed: ForkCaptureMenuLayout.recordingCountdowns),
                         forKey: DefaultsKey.recorderCountdown)
        case .back:
            // Nothing waits for an area any more: one drawn now is framed.
            armed = nil
            showModes(mainModes, active: area == nil ? nil : .area)
        case .fullScreen:
            close()
            DispatchQueue.main.async { ScreenshotService.shared.captureFullScreen() }
        case .window:
            // Start over: a click on a window photographs it at once, a drag frames an area.
            armed = .window
            model.active = .window
            if model.modes != mainModes { showModes(mainModes, active: .window) }
            beginSelection()
            moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, in: screenFrame))
        case .scrolling:
            // No bar of its own and nothing kept from before, not even a framed
            // area: a selection at once, and the capture starts on what it gives.
            dropArea()
            arm(mode)
            moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, in: screenFrame))
        case .recording:
            // Its bar comes first, with what is filmed, the options and the
            // start button; what is filmed decides what has to be drawn.
            readSettings()
            showModes(ForkCaptureMenuLayout.recordingModes, active: nil)
            prepareRecordingScope()
        case .scopeArea, .scopeWindow, .scopeScreen:
            guard let scope = ForkCaptureMenuLayout.RecordingScope(mode: mode) else { break }
            defaults.set(scope.rawValue, forKey: DefaultsKey.forkRecorderScope)
            model.scope = scope
            dropArea()
            moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, in: screenFrame))
            prepareRecordingScope()
        case .record:
            if model.scope == .fullScreen, let display = wholeDisplay() {
                run(.record, on: display)
            } else if let area {
                run(.record, on: area)
            } else {
                prepareRecordingScope()
            }
        case .area:
            if defaults.bool(forKey: DefaultsKey.forkCaptureMenuAreaAtOnce) {
                // A new area, photographed as soon as it is drawn.
                armed = .area
                model.active = .area
                if model.modes != mainModes { showModes(mainModes, active: .area) }
                beginSelection()
                moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, in: screenFrame))
            } else if let area {
                run(.area, on: area)
            } else {
                // Framed first, to be adjusted; the item, or Return, takes it.
                armed = nil
                model.active = .area
                beginSelection()
            }
        case .text:
            guard let area else {
                arm(mode)
                return
            }
            run(mode, on: area)
        }
        if mode.isSetting {
            readSettings()
            syncCamera()
        }
    }

    /// The bubble previews while the recording bar is up with the camera on,
    /// over what will be filmed.
    private func syncCamera() {
        let filmed = model.scope == .fullScreen ? screenFrame : area?.anchorRect
        if let filmed, model.camera, model.modes == ForkCaptureMenuLayout.recordingModes {
            ForkCameraBubble.shared.showPreview(in: filmed, screen: screenFrame)
        } else {
            ForkCameraBubble.shared.hidePreview()
        }
    }

    // MARK: - What a recording films

    /// Draws what the chosen scope needs: an area, or a click on a window. The
    /// whole display needs nothing. Once drawn, the recording bar comes back
    /// under it, and its start button films it.
    private func prepareRecordingScope() {
        switch model.scope {
        case .fullScreen:
            dropArea()
        case .area:
            guard area == nil else { return }
            armed = .recording
            beginSelection()
        case .window:
            guard area?.windowID == nil else { return }
            armed = .recording
            beginSelection()
        }
        syncCamera()
    }

    /// No area any more: the selection, the frame and the area go.
    private func dropArea() {
        let previous = selection
        selection = nil
        previous?.cancel()
        frame?.orderOut(nil)
        frame = nil
        area = nil
    }

    /// The display the menu is on, as a region to film.
    private func wholeDisplay() -> RecorderSupport.Region? {
        guard let display = NSScreen.screens.first(where: { $0.frame == screenFrame }) ?? NSScreen.main else { return nil }
        return ForkCaptureAreaGeometry.region(anchor: display.frame, screenFrame: display.frame,
                                              displayID: display.displayID, scale: display.backingScaleFactor)
    }

    // MARK: - The framed area

    private var currentFormat: ForkCaptureAreaGeometry.Format {
        ForkCaptureAreaGeometry.format(at: UserDefaults.standard.integer(forKey: DefaultsKey.forkCaptureMenuFormat))
    }

    /// Return on the frame: what the bar shown is for, on the area as framed.
    /// Never a new selection, as the Area item can be set to draw one.
    private func confirmFramed() {
        guard let area else { return }
        if model.modes == ForkCaptureMenuLayout.recordingModes {
            choose(.record)
        } else {
            run(.area, on: area)
        }
    }

    /// A click beside the frame: a new selection, with nothing armed, so a
    /// click on a window then frames it instead of photographing it.
    private func restartSelection() {
        armed = nil
        model.active = nil
        if model.modes != mainModes { showModes(mainModes, active: nil) }
        beginSelection()
        moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, in: screenFrame))
    }

    /// The area was moved or resized on its frame: the region follows, and the bar with it.
    private func areaChanged(_ viewRect: CGRect) {
        guard let current = area else { return }
        let region = ForkCaptureAreaGeometry.region(anchor: viewRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY),
                                                    screenFrame: screenFrame, displayID: current.displayID,
                                                    scale: current.scale)
        area = region
        remember(region)
        moveBar(to: ForkCaptureMenuLayout.barFrame(modes: model.modes, under: region.anchorRect, in: screenFrame))
        // The camera bubble goes back to the new area's corner.
        ForkCameraBubble.shared.hidePreview()
        syncCamera()
    }

    /// The format label on the frame: the next format, applied to the area at once.
    private func cycleFormat() {
        let next = ForkCaptureAreaGeometry.nextFormat(after: currentFormat)
        UserDefaults.standard.set(ForkCaptureAreaGeometry.formats.firstIndex(of: next) ?? 0,
                                  forKey: DefaultsKey.forkCaptureMenuFormat)
        guard let view = frame?.contentView as? ForkCaptureAreaView, let current = area else { return }
        view.format = next
        let shaped = ForkCaptureAreaGeometry.applying(next, to: view.area, within: view.bounds, scale: current.scale)
        view.setArea(shaped)
        areaChanged(shaped)
    }

    /// A window, or an area covering nearly the whole display, is not kept:
    /// framed again it would leave no room beside it to draw another.
    private func remember(_ region: RecorderSupport.Region) {
        guard region.windowID == nil,
              !ForkCaptureAreaGeometry.isNearlyWholeDisplay(region.anchorRect, screen: screenFrame) else { return }
        UserDefaults.standard.set(ForkCaptureAreaGeometry.encoded(region.anchorRect), forKey: DefaultsKey.forkCaptureMenuLastArea)
    }

    /// The last area framed, when it is on the pointer's display. One covering
    /// nearly the whole display, kept by an earlier version, is forgotten.
    private func rememberedRegion(on screen: CGRect) -> RecorderSupport.Region? {
        let defaults = UserDefaults.standard
        guard let rect = ForkCaptureAreaGeometry.decoded(defaults.string(forKey: DefaultsKey.forkCaptureMenuLastArea))
        else { return nil }
        if ForkCaptureAreaGeometry.isNearlyWholeDisplay(rect, screen: screen) {
            defaults.removeObject(forKey: DefaultsKey.forkCaptureMenuLastArea)
            return nil
        }
        guard screen.contains(CGPoint(x: rect.midX, y: rect.midY)),
              let display = NSScreen.screens.first(where: { $0.frame == screen })
        else { return nil }
        return ForkCaptureAreaGeometry.region(anchor: rect.intersection(screen), screenFrame: screen,
                                              displayID: display.displayID, scale: display.backingScaleFactor)
    }

    /// No area yet: the mode waits for one, marked on the bar, and a
    /// selection starts if none is under way (the menu may show its bar alone).
    private func arm(_ mode: Mode) {
        armed = mode
        model.active = mode
        if selection == nil { beginSelection() }
    }

    private func run(_ mode: Mode, on region: RecorderSupport.Region) {
        guard ScreenshotSupport.captureRouteIsAuthorized(selected: mode.tool) else {
            close()
            return
        }
        let audio = audio
        let delay = mode == .area ? model.delay : 0
        let horizontal = model.horizontal
        // A clicked window is recorded alone; with the bubble on, its area is recorded instead.
        let region = mode == .record
            ? ForkRecorderOptions.recordedRegion(region, withCamera: ForkCameraBubble.shared.isShown)
            : region
        if mode == .record {
            ForkCameraBubble.shared.keepForRecording(startingWithin: TimeInterval(model.countdown))
        }
        close()
        // Once this click has finished and the menu has left the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            switch mode {
            case .scrolling:
                // Armed just before: the capture takes the direction at its first frame.
                if horizontal { ForkScrollingDirection.armHorizontal() } else { ForkScrollingDirection.disarm() }
                // Scrolled by hand, or by the pointer once its auto-scroll is on (ForkScrollingControls).
                ScreenshotService.shared.receiveUnifiedScrollingRegion(region)
            case .record:
                ScreenRecorderService.shared.record(region, audioOptions: audio)
            default:
                ScreenCaptureService.shared.performAfterDelay(delay) { Self.capture(region, readingText: mode == .text) }
            }
        }
    }

    /// Photographs the area as it is now and hands the picture to upstream's
    /// screenshot tool, or to its text recognition. A framed window is taken
    /// from its own buffer, like a window clicked in upstream's selection.
    private static func capture(_ region: RecorderSupport.Region, readingText: Bool) {
        let defaults = UserDefaults.standard
        let includePointer = defaults.bool(forKey: DefaultsKey.screenshotIncludePointer)
        let hidesOwnWindows = defaults.bool(forKey: DefaultsKey.screenshotHideVorssaintWindows)
        let protected = ScreenshotService.shared.protectedWindowIDsForCapture(honoursVisibilityPreference: true)
        Task { @MainActor in
            var image: CGImage?
            var scale = region.scale
            if let windowID = region.windowID,
               let window = await ScreenshotCaptureEngine.captureWindow(windowID, scale: region.scale) {
                image = window.image
                scale = window.scale
            } else {
                image = await ScreenshotCaptureEngine.captureDisplayRegion(
                    displayID: region.displayID, pixelRect: region.pixelRect, includePointer: includePointer,
                    hideVorssaintWindows: hidesOwnWindows, protectedWindowIDs: protected)
            }
            guard var picture = image else {
                NSSound.beep()
                return
            }
            // A framed window comes out in the window capture style, as one clicked in upstream's selection.
            if region.windowID != nil {
                (picture, scale) = ForkWindowCaptureStyler.styled(image: picture, scale: scale)
            }
            let capture = ScreenshotSelectionController.Capture(image: picture, scale: scale,
                                                                anchorRect: region.anchorRect)
            if readingText {
                ScreenTextService.shared.receiveUnifiedCapture(capture)
            } else {
                ScreenshotService.shared.receiveUnifiedCapture(capture)
            }
        }
    }

    private func refreshMicrophones() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let listed = ForkRecorderDevices.microphones().map(\.info)
            DispatchQueue.main.async {
                guard let self else { return }
                self.microphones = listed
                if self.isOpen { self.readSettings() }
            }
        }
    }

    private func readSettings() {
        let defaults = UserDefaults.standard
        model.horizontal = defaults.bool(forKey: DefaultsKey.forkScrollingHorizontal)
        model.countdown = max(0, defaults.integer(forKey: DefaultsKey.recorderCountdown))
        model.microphone = audio.microphone
        model.systemAudio = audio.systemAudio
        model.mono = defaults.bool(forKey: DefaultsKey.forkRecorderMonoAudio)
        // On only while macOS allows the camera: a preference restored on another Mac asks again.
        model.camera = defaults.bool(forKey: DefaultsKey.forkRecorderCamera) && ForkCameraBubble.access == .allowed
        let microphone = ForkRecorderMicrophone.selected(
            storedID: defaults.string(forKey: DefaultsKey.forkRecorderMicrophoneID) ?? "",
            among: microphones)
        model.microphoneName = microphone.map { $0.isBuiltIn ? "" : $0.name } ?? ""
        model.cameraShape = ForkCameraBubbleLayout.shape(
            stored: defaults.string(forKey: DefaultsKey.forkRecorderCameraShape))
        model.clicks = ForkRecorderOptions.showsClicks(in: defaults)
        model.keys = defaults.bool(forKey: DefaultsKey.forkRecorderShowsKeys)
        model.scope = ForkCaptureMenuLayout.RecordingScope.stored(defaults.string(forKey: DefaultsKey.forkRecorderScope))
    }

    // MARK: - Windows

    private func showModes(_ modes: [Mode], active: Mode?) {
        model.modes = modes
        model.active = active
        model.highlighted = nil
        model.pressed = nil
        syncCamera()
        guard bar != nil else { return }
        moveBar(to: area.map { ForkCaptureMenuLayout.barFrame(modes: modes, under: $0.anchorRect, in: screenFrame) }
            ?? ForkCaptureMenuLayout.barFrame(modes: modes, in: screenFrame))
    }

    private func showBar(at target: CGRect) {
        let drawing = NSHostingView(rootView: ForkCaptureMenuView(model: model))
        let events = ForkCaptureMenuEventView(model: model, content: drawing) { [weak self] mode in
            self?.choose(mode)
        }
        let panel = ForkCaptureMenuPanel(contentRect: target,
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered,
                                         defer: false)
        panel.contentView = events
        Self.configure(panel)
        panel.hasShadow = true
        // Above the selection and above the frame, which both cover the display.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        bar = panel

        // It fades in where it stands: only its opacity is animated.
        panel.alphaValue = 0
        panel.setFrame(target, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak panel] in
            panel?.invalidateShadow()
        })
    }

    /// Places the bar, at once. Its frame is never animated: an animation
    /// still running when the bar changes size (the main bar giving way to a
    /// shorter one) ends on the old size, and the drawing then sits in a
    /// window wider than itself, away from where its clicks are read.
    private func moveBar(to target: CGRect) {
        guard let bar, bar.frame != target else { return }
        bar.setFrame(target, display: true)
        bar.invalidateShadow()
    }

    /// Dims the display around the area and outlines it. It takes the keys
    /// while the area waits: Return captures it, Escape gives up, and a click
    /// outside starts a new selection.
    private func showFrame(around areaRect: CGRect) {
        let view = ForkCaptureAreaView(
            area: areaRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY),
            format: currentFormat,
            scale: area?.scale ?? 1,
            confirm: { [weak self] in self?.confirmFramed() },
            cancel: { [weak self] in self?.close() },
            redo: { [weak self] in self?.restartSelection() })
        view.changed = { [weak self] rect in self?.areaChanged(rect) }
        view.nextFormat = { [weak self] in self?.cycleFormat() }
        let panel = ForkCaptureAreaPanel(contentRect: screenFrame,
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered,
                                         defer: false)
        panel.contentView = view
        Self.configure(panel)
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        frame = panel
        panel.setFrame(screenFrame, display: true)
        panel.orderFrontRegardless()
        // A panel of an app in the background never truly gets the keys:
        // Return went to the app in front, and its cursor kept coming back.
        // This app comes forward while the frame waits; the app that was in
        // front comes back when the menu closes.
        NSApp.activate()
        panel.makeKey()
        panel.makeFirstResponder(view)
        // Upstream's selection, just ended, took the permission back.
        ForkBackgroundCursor.setAllowed(true, by: .captureMenu)
        NSCursor.arrow.set()
    }

    private static func configure(_ panel: NSPanel) {
        // The cursor is set by hand on every move (the arrow, or a resize
        // arrow on an edge). Left on, AppKit's cursor rectangles would set
        // theirs after each move, and the two would take turns.
        panel.disableCursorRects()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        // Left to itself, macOS guesses which parts of a see-through window
        // take clicks, and guesses wrong; said explicitly, the window takes them all.
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
}

/// What the bar's drawing follows.
final class ForkCaptureMenuModel: ObservableObject {
    @Published var modes: [ForkCaptureMenuLayout.Mode] = []
    @Published var highlighted: ForkCaptureMenuLayout.Mode?
    @Published var pressed: ForkCaptureMenuLayout.Mode?
    /// The mode the area on screen is meant for, or the one waiting for an area.
    @Published var active: ForkCaptureMenuLayout.Mode?
    /// Seconds before a picture is taken; 0 is no delay.
    @Published var delay = 0
    @Published var microphone = false
    @Published var systemAudio = false
    @Published var mono = false
    @Published var clicks = false
    @Published var camera = false
    @Published var horizontal = false
    @Published var keys = false
    @Published var cameraShape = ForkCameraBubbleLayout.Shape.circle
    /// The chosen microphone's name; empty for the Mac's own.
    @Published var microphoneName = ""
    /// Seconds before a recording starts; 0 is no countdown.
    @Published var countdown = 0
    /// What a recording films.
    @Published var scope = ForkCaptureMenuLayout.RecordingScope.area
}

/// The bar's drawing, and only its drawing: the event view takes the mouse.
/// System symbols and the fork's own wording.
struct ForkCaptureMenuView: View {
    typealias Mode = ForkCaptureMenuLayout.Mode

    @ObservedObject var model: ForkCaptureMenuModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let size = ForkCaptureMenuLayout.barSize(modes: model.modes)
        let shape = RoundedRectangle(cornerRadius: ForkCaptureMenuLayout.cornerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Color(red: 0.145, green: 0.153, blue: 0.153).opacity(0.97))
            ForEach(model.modes, id: \.self) { mode in
                item(mode)
            }
            ForEach(ForkCaptureMenuLayout.dividerOffsets(in: model.modes), id: \.self) { x in
                Rectangle()
                    .fill(Color.white.opacity(0.13))
                    .frame(width: 1, height: 31)
                    .offset(x: x, y: (size.height - 31) / 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        // Pinned to the corner the clicks are measured from, so the drawing
        // and the clicks agree even if the window were ever a different size.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func item(_ mode: Mode) -> some View {
        if let frame = ForkCaptureMenuLayout.itemFrame(mode, in: model.modes) {
            let isActive = model.active == mode
            VStack(spacing: 4) {
                Image(systemName: symbol(for: mode))
                    .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                    .frame(height: 21)
                Text(label(for: mode))
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(color(for: mode, isActive: isActive))
            .frame(width: frame.width - 5, height: frame.height - 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(fill(for: mode, isActive: isActive))))
            .offset(x: frame.minX + 2.5, y: frame.minY + 4.5)
        }
    }

    /// A setting that is on shows in orange, one that is off is dimmed; the
    /// record button is red; everything else is white.
    private func color(for mode: Mode, isActive: Bool) -> Color {
        switch mode {
        case .record: return Color(red: 1, green: 0.27, blue: 0.23)
        case .timer: return model.delay > 0 ? .orange : plain(mode, isActive)
        case .countdown: return model.countdown > 0 ? .orange : plain(mode, isActive)
        case .microphone: return model.microphone ? .white : Color.white.opacity(0.45)
        case .systemAudio: return model.systemAudio ? .white : Color.white.opacity(0.45)
        case .mono: return model.mono ? .white : Color.white.opacity(0.45)
        case .clicks: return model.clicks ? .white : Color.white.opacity(0.45)
        case .keys: return model.keys ? .white : Color.white.opacity(0.45)
        case .camera, .cameraShape: return model.camera ? .white : Color.white.opacity(0.45)
        case .scopeArea, .scopeWindow, .scopeScreen:
            return model.scope.mode == mode ? .white : Color.white.opacity(0.45)
        default: return plain(mode, isActive)
        }
    }

    private func plain(_ mode: Mode, _ isActive: Bool) -> Color {
        Color.white.opacity(isActive || model.highlighted == mode ? 1 : 0.8)
    }

    private func fill(for mode: Mode, isActive: Bool) -> Double {
        if model.pressed == mode { return 0.24 }
        if isActive { return 0.16 }
        return model.highlighted == mode ? 0.09 : 0
    }

    private func symbol(for mode: Mode) -> String {
        switch mode {
        case .area: return "viewfinder"
        case .fullScreen: return "display"
        case .window: return "macwindow"
        case .scrolling: return "arrow.down.to.line"
        case .timer, .countdown: return "timer"
        case .text: return "text.viewfinder"
        case .recording: return "video"
        case .record: return "record.circle.fill"
        case .microphone: return model.microphone ? "mic.fill" : "mic.slash.fill"
        case .systemAudio: return model.systemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill"
        case .mono: return "speaker.wave.1.fill"
        case .clicks: return "cursorarrow.click.2"
        case .keys: return "command"
        case .camera: return "person.crop.circle"
        case .cameraShape:
            switch model.cameraShape {
            case .circle: return "circle"
            case .square: return "square"
            case .rectangle: return "rectangle"
            }
        case .back: return "chevron.left"
        case .scopeArea: return "viewfinder"
        case .scopeWindow: return "macwindow"
        case .scopeScreen: return "display"
        }
    }

    private func label(for mode: Mode) -> String {
        let text = ForkStrings.current
        switch mode {
        case .area: return text.captureMenuArea
        case .fullScreen: return text.captureMenuFullScreen
        case .window: return text.captureMenuWindow
        case .scrolling: return text.captureMenuScrolling
        case .timer: return model.delay > 0 ? text.captureMenuSeconds(model.delay) : text.captureMenuTimer
        case .text: return text.captureMenuText
        case .recording: return text.captureMenuRecording
        case .record: return text.captureMenuRecord
        case .microphone:
            guard model.microphone else { return text.captureMenuMicOff }
            return model.microphoneName.isEmpty ? text.captureMenuMicrophone : model.microphoneName
        case .camera: return text.captureMenuCamera
        case .cameraShape: return text.name(of: model.cameraShape)
        case .systemAudio: return text.captureMenuSystemAudio
        case .mono: return text.captureMenuMono
        case .clicks: return text.captureMenuClicks
        case .keys: return text.captureMenuKeys
        case .countdown: return text.captureMenuSeconds(model.countdown)
        case .back: return text.captureMenuBack
        case .scopeArea: return text.captureMenuArea
        case .scopeWindow: return text.captureMenuWindow
        case .scopeScreen: return text.captureMenuFullScreen
        }
    }
}

/// Takes the bar's mouse: hover and clicks. AppKit events for the same reason
/// as the preview card: they work whatever the window's state. The keyboard
/// stays with the selection or with the frame underneath.
final class ForkCaptureMenuEventView: NSView {
    private let model: ForkCaptureMenuModel
    private let choose: (ForkCaptureMenuLayout.Mode) -> Void
    private var tracking: NSTrackingArea?

    init(model: ForkCaptureMenuModel, content: NSView, choose: @escaping (ForkCaptureMenuLayout.Mode) -> Void) {
        self.model = model
        self.choose = choose
        super.init(frame: CGRect(origin: .zero, size: ForkCaptureMenuLayout.barSize(modes: model.modes)))
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Top-left origin, the same space as `ForkCaptureMenuLayout.itemFrame`.
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func mode(under event: NSEvent) -> ForkCaptureMenuLayout.Mode? {
        ForkCaptureMenuLayout.mode(at: convert(event.locationInWindow, from: nil), in: model.modes)
    }

    // The ordinary arrow over the bar, set on every move: with a selection
    // underneath setting its crosshair, the two would otherwise take turns.
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        model.highlighted = mode(under: event)
    }
    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        model.highlighted = mode(under: event)
    }
    override func mouseExited(with event: NSEvent) { model.highlighted = nil }

    override func mouseDown(with event: NSEvent) {
        model.pressed = mode(under: event)
    }

    override func mouseDragged(with event: NSEvent) {
        // Sliding to another item before releasing picks that one, like a menu.
        model.pressed = mode(under: event)
    }

    override func mouseUp(with event: NSEvent) {
        let released = mode(under: event)
        let pressed = model.pressed
        model.pressed = nil
        if let released, released == pressed { choose(released) }
    }
}

/// The bar's window. Like the preview card it never takes the keyboard: the
/// selection or the frame underneath keeps it.
final class ForkCaptureMenuPanel: OverlayPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The frame around an area that waits for its action: the display dimmed
/// around it, a thin outline, and the keys while it is up.
final class ForkCaptureAreaView: NSView {
    typealias Geometry = ForkCaptureAreaGeometry

    private(set) var area: CGRect
    var format: Geometry.Format {
        didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }
    private let scale: CGFloat
    private let confirm: () -> Void
    private let cancel: () -> Void
    private let redo: () -> Void
    /// The area after a move or a resize, once the mouse is let go.
    var changed: ((CGRect) -> Void)?
    /// A click on the format label.
    var nextFormat: (() -> Void)?
    private var drag: (start: CGPoint, area: CGRect, handle: Geometry.Handle?)?

    init(area: CGRect, format: Geometry.Format, scale: CGFloat, confirm: @escaping () -> Void,
         cancel: @escaping () -> Void, redo: @escaping () -> Void) {
        self.area = area
        self.format = format
        self.scale = scale
        self.confirm = confirm
        self.cancel = cancel
        self.redo = redo
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Gives the area a new shape from outside, the format item for instance.
    func setArea(_ rect: CGRect) {
        area = rect
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        // The area itself stays clear: what is in it is what will be captured.
        NSColor.clear.setFill()
        area.fill(using: .copy)
        let outline = NSBezierPath(rect: area.insetBy(dx: -0.75, dy: -0.75))
        outline.lineWidth = 1.5
        NSColor.white.setStroke()
        outline.stroke()
        // Small squares on the corners and edges say they can be pulled.
        NSColor.white.setFill()
        for point in handlePoints { CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6).fill() }
        let labels = labelFrames
        drawPill(Geometry.sizeLabel(for: area, scale: scale), in: labels.size, emphasized: false)
        drawPill(formatTitle, in: labels.format, emphasized: format != .free)
    }

    private var handlePoints: [CGPoint] {
        [CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.midX, y: area.minY), CGPoint(x: area.maxX, y: area.minY),
         CGPoint(x: area.minX, y: area.midY), CGPoint(x: area.maxX, y: area.midY),
         CGPoint(x: area.minX, y: area.maxY), CGPoint(x: area.midX, y: area.maxY), CGPoint(x: area.maxX, y: area.maxY)]
    }

    private var formatTitle: String {
        "\(format.label ?? ForkStrings.current.areaFormatFree) ▾"
    }

    private static let pillFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    private func pillWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: Self.pillFont]).width.rounded(.up) + 16
    }

    /// Above the area's top left corner, or just inside it when the display has no room above.
    private var labelFrames: (size: CGRect, format: CGRect) {
        let height: CGFloat = 20
        let sizeWidth = pillWidth(Geometry.sizeLabel(for: area, scale: scale))
        let formatWidth = pillWidth(formatTitle)
        let y = area.maxY + 6 + height <= bounds.maxY ? area.maxY + 6 : area.maxY - 6 - height
        let x = min(max(area.minX, bounds.minX + 4), max(bounds.minX + 4, bounds.maxX - sizeWidth - formatWidth - 10))
        return (CGRect(x: x, y: y, width: sizeWidth, height: height),
                CGRect(x: x + sizeWidth + 4, y: y, width: formatWidth, height: height))
    }

    private func drawPill(_ text: String, in rect: CGRect, emphasized: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        (emphasized ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.72)).setFill()
        path.fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.pillFont, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }

    private var cursorTracking: NSTrackingArea?

    /// The cursor is set by hand on every move rather than through cursor
    /// rectangles: those only apply in the active app's key window, and
    /// otherwise the app underneath keeps putting its arrow back.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited,
                                                              .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        cursorTracking = tracking
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        // While an edge is dragged its arrow stays, wherever the pointer goes.
        let point = drag.map { drag in
            drag.handle == nil ? convert(event.locationInWindow, from: nil) : drag.start
        } ?? convert(event.locationInWindow, from: nil)
        let reference = drag?.area ?? area
        switch Geometry.cursor(at: point, in: reference) {
        case .arrow: NSCursor.arrow.set()
        case .resizeLeftRight: NSCursor.resizeLeftRight.set()
        case .resizeUpDown: NSCursor.resizeUpDown.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if labelFrames.format.contains(point) {
            nextFormat?()
            return
        }
        updateCursor(event)
        if let handle = Geometry.handle(at: point, in: area) {
            drag = (point, area, handle)
        } else if area.contains(point) {
            drag = (point, area, nil)
        } else {
            // A click outside the area starts a new selection.
            redo()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        updateCursor(event)
        let point = convert(event.locationInWindow, from: nil)
        if let handle = drag.handle {
            area = Geometry.resized(drag.area, handle: handle, to: point, within: bounds,
                                    aspect: format.aspect, square: event.modifierFlags.contains(.shift))
        } else {
            area = Geometry.moved(drag.area, by: CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y),
                                  within: bounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        if area != drag.area { changed?(area) }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: cancel() // Escape
        case 36, 76, 49: confirm() // Return, Enter, Space
        default: break
        }
    }
}

/// The frame's window: it takes the keys, for Return and Escape.
final class ForkCaptureAreaPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
