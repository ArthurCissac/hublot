// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import SwiftUI

/// The fork's quick action tiles (see `ForkQuickActionLogic`), shown before
/// upstream's in the simple menus. Each opens a tool Hublot already has and
/// shows only while that tool is on; presentation mode switches upstream's
/// own settings and puts back what it changed.
enum ForkQuickActions {
    typealias Action = ForkQuickActionLogic.Action

    static func hidden() -> Set<Action> {
        ForkQuickActionLogic.hidden(UserDefaults.standard.string(forKey: DefaultsKey.forkQuickActionsHidden))
    }

    static func setHidden(_ action: Action, _ hide: Bool) {
        var set = hidden()
        if hide { set.insert(action) } else { set.remove(action) }
        UserDefaults.standard.set(ForkQuickActionLogic.stored(set), forKey: DefaultsKey.forkQuickActionsHidden)
    }

    static func isAvailable(_ action: Action) -> Bool {
        let defaults = UserDefaults.standard
        switch action {
        case .tasks: return defaults.bool(forKey: DefaultsKey.forkTodoistEnabled)
        case .colorPicker: return AppFeature.colorPicker.isAvailable
        case .screenText: return AppFeature.screenOCR.isAvailable
        case .phoneSite: return AppFeature.portManager.isAvailable && ForkLocalQRController.isEnabled()
        case .ambient: return defaults.bool(forKey: DefaultsKey.forkAmbientEnabled)
        case .note: return AppFeature.scratchpad.isAvailable
        case .clipboard: return ForkClipboardShelf.isEnabled()
        case .presentation: return true
        case .camera: return AppFeature.cameraPreview.isAvailable
        case .soundOutput: return AppFeature.soundOutputSwitcher.isAvailable || AppFeature.mixer.isAvailable
        case .smartScan: return defaults.bool(forKey: DefaultsKey.forkCleanerTools)
        case .recordScreen: return AppFeature.screenRecorder.isAvailable
        case .weather: return defaults.bool(forKey: DefaultsKey.forkWeatherEnabled)
        case .translate: return ForkTranslateLogic.pageAvailable(in: defaults)
        case .home: return ForkHomeLogic.pageAvailable(in: defaults)
        case .printer: return ForkBambuLogic.pageAvailable(in: defaults)
        }
    }

    static var visible: [Action] {
        ForkQuickActionLogic.visible(hidden: hidden(), available: isAvailable)
    }

    /// Once: the screen saver, the display switch and the desktop icons
    /// leave the tiles (presentation mode hides the icons); the edit list
    /// brings them back.
    static func applyDefaultsOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.forkQuickActionsSetUp) else { return }
        defaults.set(true, forKey: DefaultsKey.forkQuickActionsSetUp)
        for key in [DefaultsKey.panelToggleScreenSaver, DefaultsKey.panelToggleDisplayOff, DefaultsKey.panelToggleDesktopIcons] {
            defaults.set(false, forKey: key)
        }
    }

    /// Tools that take the screen or open a window close the panel first.
    static func closingPanel(_ action: @escaping () -> Void) {
        appDelegate()?.closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
    }

    static func perform(_ action: Action) {
        switch action {
        case .tasks: closingPanel { ForkTodoistPanel.shared.show() }
        case .colorPicker: closingPanel { ColorSamplerService.shared.pick() }
        case .screenText: closingPanel { ScreenTextService.shared.capture() }
        case .phoneSite: ForkPhoneSite.shared.open()
        case .ambient: ForkAmbientPlayer.shared.toggle()
        case .note: closingPanel { ScratchpadService.shared.toggle() }
        case .clipboard: closingPanel { _ = ForkClipboardShelf.shared.toggle() }
        case .presentation: ForkPresentationMode.shared.toggle()
        case .camera: closingPanel { CameraPreviewService.shared.toggle() }
        case .soundOutput: ForkSoundOutput.switchToNext()
        case .smartScan: closingPanel { ForkSmartScanWindow.shared.show() }
        // Starting closes the menu first, so the selection sees the screen; a second press stops.
        case .recordScreen: closingPanel { ScreenRecorderService.shared.toggle() }
        case .weather: closingPanel { NotchService.shared.open(.weather) }
        case .translate: closingPanel { ForkTranslate.shared.translateSelection() }
        case .home: closingPanel { NotchService.shared.open(.home) }
        case .printer: closingPanel { NotchService.shared.open(.printer) }
        }
    }
}

// MARK: - The phone QR code

/// Finds the dev servers running now and opens the QR code of the one, or
/// asks which one.
final class ForkPhoneSite: NSObject {
    static let shared = ForkPhoneSite()
    private var waiting: AnyCancellable?
    private var choices: [PortManagerEntry] = []

    func open() {
        let service = PortManagerService.shared
        waiting = service.$isRefreshing.dropFirst().first(where: { !$0 }).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.decide(service.entries) }
        service.refresh()
    }

    private func decide(_ entries: [PortManagerEntry]) {
        waiting = nil
        let servers = ForkQuickActionLogic.devServers(entries.map {
            .init(port: $0.port, protocolName: $0.protocolName, processName: $0.processName, address: $0.address)
        })
        let picked = servers.compactMap { server in entries.first { $0.port == server.port && $0.address == server.address } }
        switch picked.count {
        case 0:
            appDelegate()?.closePopover()
            QuickToolHUD.show(icon: "iphone.slash", message: ForkQuickActionStrings.current.noDevServer)
        case 1:
            appDelegate()?.closePopover()
            ForkLocalQRController.shared.show(picked[0])
        default:
            choices = picked
            let menu = NSMenu()
            for (index, entry) in picked.enumerated() {
                let item = NSMenuItem(title: ":\(entry.port) · \(entry.processName)", action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard choices.indices.contains(item.tag) else { return }
        let entry = choices[item.tag]
        appDelegate()?.closePopover()
        ForkLocalQRController.shared.show(entry)
    }
}

// MARK: - The sound output

enum ForkSoundOutput {
    /// The output playing now, by the name macOS gives it.
    static func currentName() -> String? {
        let mixer = AppVolumeMixer.shared
        return mixer.outputDevices.first { $0.uid == mixer.currentOutputDeviceUID }?.name
    }

    static func switchToNext() {
        let mixer = AppVolumeMixer.shared
        let cycle = ForkQuickActionLogic.outputCycle(
            selected: SoundOutputSwitcher.shared.selectedDeviceUIDs(),
            available: mixer.outputDevices.filter(\.canBeDefaultOutput).map(\.uid))
        if !mixer.switchToNextSoundOutput(in: cycle) { NSSound.beep() }
    }
}

// MARK: - Presentation mode

/// Before a client demo: desktop icons hidden, the island's notifications
/// paused, the Mac kept awake and, with the two shortcuts made once in the
/// Shortcuts app, Do Not Disturb on. A second click puts back what it changed.
final class ForkPresentationMode: ObservableObject {
    static let shared = ForkPresentationMode()
    typealias Logic = ForkQuickActionLogic

    @Published private(set) var active = false
    /// Whether the Do Not Disturb shortcuts exist; nil until looked up.
    @Published private(set) var hasFocusShortcuts: Bool?

    private init() {
        active = snapshot != nil
    }

    private var snapshot: Logic.Snapshot? {
        get {
            UserDefaults.standard.data(forKey: DefaultsKey.forkPresentationSnapshot)
                .flatMap { try? JSONDecoder().decode(Logic.Snapshot.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: DefaultsKey.forkPresentationSnapshot)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.forkPresentationSnapshot)
            }
        }
    }

    private var now: Logic.Snapshot {
        Logic.Snapshot(desktopIconsShown: QuickTogglesService.shared.desktopIconsShown,
                       islandNotifications: UserDefaults.standard.bool(forKey: DefaultsKey.notchNotificationsEnabled),
                       keepAwakeActive: KeepAwakeManager.shared.isActive)
    }

    func toggle() {
        if let before = snapshot {
            apply(Logic.leaving(before, now: now))
            snapshot = nil
            active = false
        } else {
            let current = now
            snapshot = current
            apply(Logic.entering(current))
            active = true
        }
    }

    private func apply(_ changes: [Logic.Change]) {
        for change in changes {
            switch change {
            case .hideDesktopIcons, .showDesktopIcons: QuickTogglesService.shared.toggleDesktopIcons()
            case .pauseIslandNotifications, .resumeIslandNotifications:
                UserDefaults.standard.set(change == .resumeIslandNotifications, forKey: DefaultsKey.notchNotificationsEnabled)
                if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            case .startKeepAwake: KeepAwakeManager.shared.activate(minutes: 0)
            case .stopKeepAwake: if KeepAwakeManager.shared.isActive { KeepAwakeManager.shared.toggle() }
            case .focusOn: runShortcut(Logic.focusOnShortcut)
            case .focusOff: runShortcut(Logic.focusOffShortcut)
            }
        }
    }

    private static let shortcutsTool = "/usr/bin/shortcuts"

    /// A missing shortcut fails quietly: the rest of presentation mode still works.
    private func runShortcut(_ name: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = BoundedProcessRunner.run(Self.shortcutsTool, ["run", name], timeout: 20, maxOutputBytes: 1 << 16)
        }
    }

    func lookUpShortcuts() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = BoundedProcessRunner.run(Self.shortcutsTool, ["list"], timeout: 10, maxOutputBytes: 1 << 20)
            let found = Logic.hasFocusShortcuts(in: String(decoding: result.output, as: UTF8.self))
            DispatchQueue.main.async { self?.hasFocusShortcuts = found }
        }
    }
}

// MARK: - Tiles and their edit list

/// One of the fork's tiles, lit while its tool runs.
struct ForkQuickActionTile: View {
    let action: ForkQuickActionLogic.Action
    @ObservedObject private var ambient = ForkAmbientPlayer.shared
    @ObservedObject private var camera = CameraPreviewService.shared
    @ObservedObject private var presentation = ForkPresentationMode.shared
    @ObservedObject private var todoist = ForkTodoist.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared

    var body: some View {
        let text = ForkQuickActionStrings.current
        // The tasks' tile carries how many are left today.
        let count = action == .tasks ? ForkTodoistLogic.badge(todoist.tasks.count).map(ForkTile.Badge.count) : nil
        ForkTile(title: title(text), symbol: Self.symbol(action), on: on,
                 tint: action == .presentation ? .orange : action == .recordScreen ? .red : .accentColor,
                 badge: count, busy: false, enabled: true) {
            ForkQuickActions.perform(action)
        }
    }

    private var on: Bool {
        switch action {
        case .ambient: return ambient.playing
        case .camera: return camera.state == .running || camera.state == .starting
        case .presentation: return presentation.active
        case .recordScreen: return recorder.isRecording
        default: return false
        }
    }

    private func title(_ text: ForkQuickActionStrings) -> String {
        if action == .soundOutput, let name = ForkSoundOutput.currentName() { return name }
        return text.title(action)
    }

    static func symbol(_ action: ForkQuickActionLogic.Action) -> String {
        switch action {
        case .tasks: return ForkTodoistLogic.islandSymbol
        case .colorPicker: return "eyedropper"
        case .screenText: return "text.viewfinder"
        case .phoneSite: return "iphone"
        case .ambient: return "waveform"
        case .note: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .presentation: return "person.wave.2.fill"
        case .camera: return "camera.fill"
        case .soundOutput: return "airpodspro"
        case .smartScan: return "wand.and.stars"
        case .recordScreen: return "record.circle"
        case .weather: return ForkWeatherLogic.pageSymbol
        case .translate: return ForkTranslateLogic.pageSymbol
        case .home: return ForkHomeLogic.pageSymbol
        case .printer: return ForkBambuLogic.pageSymbol
        }
    }
}

