// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine

/// Runs the two Do Not Disturb shortcuts when a recording starts and ends,
/// whatever started it: the capture menu, upstream's shortcut or the island.
/// It only watches upstream's published recording state; nothing runs while
/// no recording starts, and nothing at all when the option is off.
final class ForkRecorderFocusService: ObservableObject {
    static let shared = ForkRecorderFocusService()

    /// The pair found in the Shortcuts app, for the settings page.
    @Published private(set) var found: (on: String?, off: String?) = (nil, nil)

    private var watcher: AnyCancellable?
    private var wasRecording = false
    private var turnedOn = false
    private var warnedMissing = false
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.recorder-focus")
    private static let tool = "/usr/bin/shortcuts"

    func start() {
        watcher = ScreenRecorderService.shared.$isRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in self?.recordingChanged(recording) }
    }

    private func recordingChanged(_ isRecording: Bool) {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.forkRecorderDoNotDisturb)
        let action = ForkRecorderFocus.action(wasRecording: wasRecording, isRecording: isRecording,
                                              enabled: enabled, turnedOn: turnedOn)
        wasRecording = isRecording
        switch action {
        case .turnOn:
            listShortcuts { [weak self] found in
                guard let self, let on = found.on, found.off != nil else {
                    self?.warnMissingOnce()
                    return
                }
                // Still recording by the time the list came back.
                guard self.wasRecording else { return }
                self.turnedOn = true
                self.run(on)
            }
        case .turnOff:
            turnedOn = false
            listShortcuts { [weak self] found in
                if let off = found.off { self?.run(off) }
            }
        case nil:
            break
        }
    }

    /// Reads the Shortcuts app's list off the main thread and answers on it.
    func refresh() {
        listShortcuts { _ in }
    }

    private func listShortcuts(_ completion: @escaping ((on: String?, off: String?)) -> Void) {
        queue.async { [weak self] in
            let result = BoundedProcessRunner.run(Self.tool, ["list"], timeout: 10, maxOutputBytes: 256 * 1024)
            let listed = result.status == 0 && !result.timedOut
                ? String(decoding: result.output, as: UTF8.self).components(separatedBy: .newlines)
                : []
            let found = ForkRecorderFocus.find(in: listed, appName: AppInfo.name)
            DispatchQueue.main.async {
                self?.found = found
                completion(found)
            }
        }
    }

    private func run(_ name: String) {
        queue.async {
            _ = BoundedProcessRunner.run(Self.tool, ["run", name], timeout: 15, maxOutputBytes: 64 * 1024)
        }
    }

    /// Said once per launch, so a missing shortcut does not nag at every recording.
    private func warnMissingOnce() {
        guard !warnedMissing else { return }
        warnedMissing = true
        QuickToolHUD.show(icon: "moon", message: ForkStrings.current.focusShortcutsMissing)
    }

    /// Opens the Shortcuts app on a new shortcut for each one still missing.
    func createMissing() {
        let names = ForkRecorderFocus.names(appName: AppInfo.name, french: L10n.shared.language == .fr)
        var missing: [String] = []
        if found.on == nil { missing.append(names.on) }
        if found.off == nil { missing.append(names.off) }
        for (index, name) in missing.enumerated() {
            guard let url = ForkRecorderFocus.createURL(name: name) else { continue }
            // One after the other: the Shortcuts app takes a moment to open the first.
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.5) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
