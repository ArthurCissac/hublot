// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine

/// Listens to the keyboard while a recording runs with the keys option on,
/// and hands the presses to the editor when it first opens that recording.
///
/// Listening only, and only while recording: a global monitor sees nothing
/// typed in a password field (macOS keeps secure input from it), changes
/// nothing, and is removed the moment the recording stops. The presses stay
/// in memory until the editor turns them into captions; nothing is written
/// anywhere else.
final class ForkRecorderKeyCapture {
    static let shared = ForkRecorderKeyCapture()

    private struct Capture {
        let start: Date
        var end: Date?
        var presses: [ForkRecorderKeys.Press]
    }

    private var watchers: Set<AnyCancellable> = []
    private var monitors: [Any] = []
    private var current: Capture?
    private var finished: Capture?
    private var pausedSince: Date?
    private var pausedTotal: TimeInterval = 0

    func start() {
        let recorder = ScreenRecorderService.shared
        recorder.$isRecording.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] recording in recording ? self?.begin() : self?.end() }
            .store(in: &watchers)
        recorder.$isPaused.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] paused in self?.pause(paused) }
            .store(in: &watchers)
    }

    private func begin() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.forkRecorderShowsKeys), AXIsProcessTrusted() else { return }
        current = Capture(start: Date(), end: nil, presses: [])
        pausedSince = nil
        pausedTotal = 0
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            DispatchQueue.main.async { self?.record(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    private func end() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        guard var capture = current else { return }
        current = nil
        capture.end = Date()
        finished = capture.presses.isEmpty ? nil : capture
    }

    private func pause(_ paused: Bool) {
        guard current != nil else { return }
        if paused {
            pausedSince = Date()
        } else if let since = pausedSince {
            pausedTotal += Date().timeIntervalSince(since)
            pausedSince = nil
        }
    }

    private func record(_ event: NSEvent) {
        guard var capture = current, pausedSince == nil, !event.isARepeat else { return }
        let flags = event.modifierFlags
        guard let label = ForkRecorderKeys.label(
            keyCode: Int(event.keyCode), characters: event.characters,
            command: flags.contains(.command), option: flags.contains(.option),
            control: flags.contains(.control), shift: flags.contains(.shift),
            allKeys: UserDefaults.standard.bool(forKey: DefaultsKey.forkRecorderAllKeys),
            spaceName: ForkStrings.current.keySpace)
        else { return }
        let time = Date().timeIntervalSince(capture.start) - pausedTotal
        capture.presses.append(ForkRecorderKeys.Press(time: time, label: label.text, isTyping: label.isTyping))
        current = capture
    }

    /// Called by one line of upstream's editor once it has loaded a recording:
    /// the presses of that recording become captions, in one undoable step.
    static func addCaptions(to editor: RecorderEditorModel) {
        shared.addCaptions(to: editor)
    }

    private func addCaptions(to editor: RecorderEditorModel) {
        guard let capture = finished, let end = capture.end, editor.duration > 0,
              let created = try? editor.take.videoURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
              ForkRecorderKeys.belongs(videoCreated: created, start: capture.start, end: end)
        else { return }
        finished = nil
        let captions = ForkRecorderKeys.captions(for: capture.presses, duration: editor.duration)
        guard !captions.isEmpty else { return }
        var next = editor.document
        next.texts += captions.map {
            RecorderTextOverlay(text: $0.text, start: $0.start, end: $0.end, anchor: .bottom,
                                size: ForkRecorderKeys.captionSize, palette: .white)
        }
        editor.document = next
    }
}
