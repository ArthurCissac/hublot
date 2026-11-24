// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import AVFoundation
import Combine
import CoreAudio
import SwiftUI

/// Background sound: plays `ForkAmbientSynth` through macOS's audio engine,
/// which runs only during a session. While it plays, an icon shows in the
/// menu bar and opens a dark panel hanging under it; a window holds every
/// sound; the island shows a control and, closed, a wave (see the hooks in
/// `NotchSupport`, `NotchControlsView`, `NotchService` and `NotchView`).
/// A session runs for a time or in Pomodoro cycles, holds during calls or
/// while music plays, and pauses when the screen locks or the Mac sleeps.
final class ForkAmbientPlayer: ObservableObject {
    typealias Logic = ForkAmbientLogic

    static let shared = ForkAmbientPlayer()

    /// A session is running (its sound may be quiet: a break, a call).
    @Published private(set) var playing = false
    @Published private(set) var mix: Logic.Mix
    @Published private(set) var volume: Double
    @Published private(set) var favorites: [Logic.Favorite]
    /// When the timer or the current Pomodoro phase ends; nil without either.
    @Published private(set) var endDate: Date?
    @Published private(set) var remaining: TimeInterval?
    @Published private(set) var phase: Logic.Phase?
    @Published private(set) var completedWork = 0
    /// Held for a call or music.
    @Published private(set) var holding = false
    @Published private(set) var shortcutTaken = false

    private var engine: AVAudioEngine?
    private var renderer: ForkAmbientRenderer?
    private var tick: Timer?
    private var watch: Timer?
    private var stopWork: DispatchWorkItem?
    private var pausedBySystem = false
    /// Its own id: 9_102 and 9_103 are the preview cards' reopen and hide shortcuts.
    private let hotkey = QuickToolHotkey(id: 9_107)
    private var statusItem: NSStatusItem?
    private var observers: [NSObjectProtocol] = []
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.syncWithPreferences() }

    private init() {
        let defaults = UserDefaults.standard
        let saved = Logic.decode(defaults.string(forKey: DefaultsKey.forkAmbientMix))
        mix = saved.isEmpty ? Logic.defaultMix : saved
        volume = defaults.object(forKey: DefaultsKey.forkAmbientVolume) as? Double ?? 0.6
        favorites = Logic.favorites(stored: defaults.string(forKey: DefaultsKey.forkAmbientFavorites))
    }

    var isAvailable: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkAmbientEnabled) }

    var mode: Logic.Mode {
        Logic.Mode(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.forkAmbientMode) ?? "") ?? .timer
    }

    var preset: Logic.Preset? { Logic.preset(for: mix) }

    var favorite: Logic.Favorite? { favorites.first { Logic.sameMix($0.sounds, mix) } }

    /// Whether the sound is heard now.
    var audible: Bool { playing && Logic.soundsDuring(phase) && !holding }

    /// The closed island shows the wave.
    var showsIslandActivity: Bool {
        Logic.showsIslandActivity(playing: playing,
                                  wanted: UserDefaults.standard.bool(forKey: DefaultsKey.forkAmbientIslandActivity),
                                  featureOn: isAvailable)
    }

    // MARK: - Life cycle

    func start() {
        Logic.showIslandControlOnce(in: .standard)
        Logic.islandActivityShown = { ForkAmbientPlayer.shared.showsIslandActivity }
        Logic.islandReading = { ForkAmbientIsland.reading(language: $0) }
        Logic.islandStripWing = {
            Logic.stripWing(reading: ForkAmbientIsland.reading(language: L10n.shared.language),
                            scenes: UserDefaults.standard.bool(forKey: DefaultsKey.forkAmbientScenes), in: $0)
        }
        hotkey.onPress = { [weak self] in self?.toggle() }
        DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.resync.schedule()
            })
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                 object: nil, queue: .main) { [weak self] _ in self?.systemPause() })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                 object: nil, queue: .main) { [weak self] _ in self?.systemResume() })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.systemPause() })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.systemResume() })
    }

    private func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let available = isAvailable
        if !available, playing { pause() }
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.forkAmbientShortcut, fallback: Logic.defaultShortcut)
        let wanted = available && defaults.bool(forKey: DefaultsKey.forkAmbientShortcutEnabled)
        let registered = hotkey.sync(enabled: wanted, shortcut: shortcut, storageKey: DefaultsKey.forkAmbientShortcut)
        if shortcutTaken != (wanted && !registered) { shortcutTaken = wanted && !registered }
        syncStatusItem()
        refreshIsland()
    }

    private func systemPause() {
        guard playing else { return }
        pausedBySystem = true
        pause()
    }

    private func systemResume() {
        guard pausedBySystem else { return }
        pausedBySystem = false
        play()
    }

    // MARK: - Playing

    func toggle() {
        if playing { pause() } else { play() }
    }

    func play() {
        guard isAvailable, !playing else { return }
        if mix.isEmpty { setMix(Logic.defaultMix) }
        stopWork?.cancel()
        guard startEngine() else { return }
        playing = true
        holding = false
        startSessionClock()
        startWatching()
        applyLevels()
        syncStatusItem()
        refreshIsland()
    }

    /// The sound glides to silence, then the engine stops: no click, and no
    /// work at all while paused. The menu bar icon goes with it.
    func pause() {
        guard playing else { return }
        playing = false
        holding = false
        endDate = nil
        remaining = nil
        phase = nil
        tick?.invalidate()
        tick = nil
        watch?.invalidate()
        watch = nil
        renderer?.setMaster(0)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.playing else { return }
            self.engine?.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        syncStatusItem()
        refreshIsland()
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        UserDefaults.standard.set(volume, forKey: DefaultsKey.forkAmbientVolume)
        applyLevels()
    }

    func setLevel(_ level: Double, for sound: Logic.Sound) {
        var next = mix
        next[sound] = level > 0.001 ? min(1, level) : nil
        setMix(next)
    }

    /// A sound turns on at half level, or off; turning one on also plays.
    func toggleSound(_ sound: Logic.Sound) {
        setLevel(mix[sound] == nil ? 0.5 : 0, for: sound)
        if !playing, !mix.isEmpty { play() }
    }

    func apply(_ preset: Logic.Preset) {
        setMix(preset.mix)
        if !playing { play() }
    }

    func apply(_ favorite: Logic.Favorite) {
        setMix(favorite.sounds)
        if !playing { play() }
    }

    private func setMix(_ next: Logic.Mix) {
        mix = next
        UserDefaults.standard.set(Logic.encode(next), forKey: DefaultsKey.forkAmbientMix)
        if next.isEmpty, playing { pause() }
        applyLevels()
    }

    // MARK: - Favourites

    func saveFavorite(named name: String) {
        guard !mix.isEmpty else { return }
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = Logic.uniqueName(base.isEmpty ? ForkAmbientStrings.current.defaultFavoriteName : base,
                                     among: favorites)
        favorites.append(Logic.Favorite(id: UUID(), name: title, mix: Logic.encode(mix)))
        storeFavorites()
    }

    func rename(_ favorite: Logic.Favorite, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        let others = favorites.filter { $0.id != favorite.id }
        favorites[index].name = Logic.uniqueName(trimmed, among: others)
        storeFavorites()
    }

    func delete(_ favorite: Logic.Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        storeFavorites()
    }

    private func storeFavorites() {
        UserDefaults.standard.set(Logic.stored(favorites), forKey: DefaultsKey.forkAmbientFavorites)
    }

    // MARK: - Timer and Pomodoro

    func setMode(_ next: Logic.Mode) {
        UserDefaults.standard.set(next.rawValue, forKey: DefaultsKey.forkAmbientMode)
        if playing { startSessionClock() }
    }

    func setTimer(minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: DefaultsKey.forkAmbientTimer)
        if playing, mode == .timer { startSessionClock() }
    }

    func setPomodoro(minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: DefaultsKey.forkAmbientPomodoroMinutes)
        if playing, mode == .pomodoro { startSessionClock() }
    }

    private var pomodoroMinutes: Int { UserDefaults.standard.integer(forKey: DefaultsKey.forkAmbientPomodoroMinutes) }

    private func startSessionClock() {
        switch mode {
        case .timer:
            phase = nil
            let minutes = UserDefaults.standard.integer(forKey: DefaultsKey.forkAmbientTimer)
            endDate = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        case .pomodoro:
            phase = .work
            completedWork = 0
            endDate = Date().addingTimeInterval(Logic.duration(of: .work, workMinutes: pomodoroMinutes))
        }
        tick?.invalidate()
        tick = nil
        updateClock()
        // A time limit set or removed while playing widens or narrows the island.
        refreshIsland()
        guard endDate != nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateClock() }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func updateClock() {
        guard playing, let endDate else {
            remaining = nil
            applyLevels()
            return
        }
        let left = endDate.timeIntervalSinceNow
        remaining = max(0, left)
        if left <= 0 {
            if let phase {
                advance(from: phase)
            } else {
                pause()
                return
            }
        }
        applyLevels()
    }

    /// Work ends, a break starts (or the reverse): the chime rings and the
    /// sound fades out or back in.
    private func advance(from current: Logic.Phase) {
        let next = Logic.next(after: current, completedWork: completedWork)
        phase = next.phase
        completedWork = next.completedWork
        endDate = Date().addingTimeInterval(Logic.duration(of: next.phase, workMinutes: pomodoroMinutes))
        remaining = endDate?.timeIntervalSinceNow
        renderer?.ringChime()
        refreshIsland()
    }

    // MARK: - Calls and music

    /// Checked every two seconds during a session only.
    private func startWatching() {
        watch?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkHold() }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
        checkHold()
    }

    private func checkHold() {
        let defaults = UserDefaults.standard
        let hold = Logic.holds(microphoneInUse: Self.microphoneInUse(),
                               musicPlaying: NotchMusicService.shared.playback?.isPlaying == true,
                               pauseForCalls: defaults.bool(forKey: DefaultsKey.forkAmbientPauseForCalls),
                               pauseForMusic: defaults.bool(forKey: DefaultsKey.forkAmbientPauseForMusic))
        guard hold != holding else { return }
        holding = hold
        applyLevels()
    }

    /// Whether any app records from the default input: a call, a dictation.
    private static func microphoneInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: - Levels and engine

    private func applyLevels() {
        guard let renderer else { return }
        for sound in Logic.Sound.allCases { renderer.setLevel(mix[sound] ?? 0, for: sound) }
        renderer.setMaster(audible ? volume * Logic.fadeFactor(remaining: mode == .timer || phase == .work ? remaining : nil) : 0)
    }

    private func startEngine() -> Bool {
        if engine == nil { buildEngine() }
        guard let engine else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            self.engine = nil
            renderer = nil
            return false
        }
    }

    private func buildEngine() {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let renderer = ForkAmbientRenderer(sampleRate: rate)
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            renderer.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        // A new output (headphones, a display's speakers) stops the engine:
        // it is rebuilt on the new one and the sound carries on.
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.engine = nil
            self.renderer = nil
            if self.playing, self.startEngine() { self.applyLevels() }
        })
        self.engine = engine
        self.renderer = renderer
    }

    // MARK: - Island

    private func refreshIsland() {
        guard NotchSupport.isEnabled() else { return }
        NotchService.shared.refreshPresentation()
    }

    // MARK: - Menu bar

    /// Shown only during a session, when wanted.
    private func syncStatusItem() {
        let visible = playing && isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.forkAmbientMenuBarIcon)
        if !visible {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: ForkAmbientStrings.current.title)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        ForkAmbientPanel.shared.toggle(atX: NSEvent.mouseLocation.x)
    }

    func openWindow() {
        ForkAmbientPanel.shared.close()
        ForkAmbientWindow.shared.show()
    }
}

/// The synthesis behind the audio engine. Levels set from the main thread go
/// through plain memory the audio thread reads at each buffer: no lock on the
/// audio thread, and the synthesis glides to each new level anyway.
final class ForkAmbientRenderer: @unchecked Sendable {
    private var synth: ForkAmbientSynth
    private let targets: UnsafeMutablePointer<Float>
    private let sounds = ForkAmbientLogic.Sound.allCases
    private let count = ForkAmbientLogic.Sound.allCases.count

    init(sampleRate: Double) {
        synth = ForkAmbientSynth(sampleRate: sampleRate)
        // The sounds' levels, the master volume, then the chime's request.
        targets = UnsafeMutablePointer<Float>.allocate(capacity: count + 2)
        targets.initialize(repeating: 0, count: count + 2)
    }

    deinit { targets.deallocate() }

    func setLevel(_ level: Double, for sound: ForkAmbientLogic.Sound) {
        guard let index = sounds.firstIndex(of: sound) else { return }
        targets[index] = Float(level)
    }

    func setMaster(_ level: Double) { targets[count] = Float(level) }

    func ringChime() { targets[count + 1] = 1 }

    /// On the audio thread.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for index in 0..<count {
            synth.setLevel(Double(targets[index]), for: sounds[index])
        }
        synth.setMaster(Double(targets[count]))
        if targets[count + 1] > 0.5 {
            targets[count + 1] = 0
            synth.ringChime()
        }
        synth.render(left: left, right: right, frames: frames)
    }
}

/// The dark panel under the menu bar icon. Placed by hand, just under the
/// bar where it was clicked: on recent macOS the status item's frame can lie
/// and an attached popover once opened far below the bar. Closes on a click
/// elsewhere or Escape.
final class ForkAmbientPanel {
    static let shared = ForkAmbientPanel()
    static let size = CGSize(width: 372, height: 560)

    private var panel: NSPanel?
    private var monitors: [Any] = []

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(atX x: CGFloat) {
        if isOpen { close() } else { open(atX: x) }
    }

    func open(atX x: CGFloat) {
        let screen = NSScreen.screens.first { $0.frame.minX <= x && x <= $0.frame.maxX } ?? NSScreen.main
        guard let screen else { return }
        let frame = ForkAmbientLogic.panelFrame(size: Self.size, clickX: x, visibleFrame: screen.visibleFrame)
        let panel = self.panel ?? makePanel()
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        watchForDismissal()
    }

    func close() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = ForkAmbientKeyPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                                        styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingView(rootView: ForkAmbientPanelView(player: .shared))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func watchForDismissal() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53, self?.isOpen == true else { return event }  // Escape
            self?.close()
            return nil
        }) { monitors.append(local) }
    }
}

/// A borderless panel that can still take the keyboard, for Escape and the sliders.
private final class ForkAmbientKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
