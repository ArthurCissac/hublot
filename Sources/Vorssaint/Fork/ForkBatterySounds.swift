// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import UniformTypeIdentifiers

/// Lot 8, the battery sounds: Hublot's own (composed note by note), the
/// macOS alert sounds, and the sounds the user imports. Imported files are
/// copied into Hublot's own folder in Application Support, after checking
/// their type and size (`ForkBatteryAlertRules.isImportableSound`); nothing
/// is read from where they came from afterwards. Main thread only.
final class ForkBatterySounds: ObservableObject {
    static let shared = ForkBatterySounds()
    typealias Panel = ForkBatteryPanelLogic
    typealias Rules = ForkBatteryAlertRules

    /// The imported sounds, by file name.
    @Published private(set) var importedNames: [String] = []
    private var sound: NSSound?

    private init() {
        importedNames = Self.listImported()
    }

    var systemNames: [String] { TextSnippetSupport.alertSoundNames }

    /// A stored choice resolved against what this Mac has.
    func choice(_ stored: String?, fallback: Panel.SoundChoice) -> Panel.SoundChoice {
        Panel.soundChoice(stored: stored, fallback: fallback, systemNames: systemNames, fileNames: importedNames)
    }

    func play(_ choice: Panel.SoundChoice) {
        sound?.stop()
        switch choice {
        case .none:
            sound = nil
        case .hublot(let tune):
            let rate = 44_100
            let samples = ForkBatteryLogic.samples(for: ForkBatteryLogic.tones(for: tune), sampleRate: Double(rate))
            sound = NSSound(data: ForkBatteryLogic.wavData(samples, sampleRate: rate))
        case .system(let name):
            sound = NSSound(contentsOf: TextSnippetSupport.soundFileURL(for: name), byReference: true)
        case .file(let name):
            sound = Self.folder.map { NSSound(contentsOf: $0.appendingPathComponent(name), byReference: true) } ?? nil
        }
        sound?.play()
    }

    /// Asks for a sound file and copies it among Hublot's sounds. Returns its
    /// stored choice, or nil when cancelled or refused (`refused` is true then).
    func importSound(refused: inout Bool) -> String? {
        refused = false
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url, let folder = Self.folder else { return nil }
        let name = source.lastPathComponent
        let bytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard Rules.isImportableSound(fileName: name, bytes: bytes) else {
            refused = true
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            refused = true
            return nil
        }
        importedNames = Self.listImported()
        return Panel.SoundChoice.file(name).stored
    }

    /// Application Support/<bundle id>/Sounds.
    private static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Hublot", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    private static func listImported() -> [String] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { Rules.importableSoundExtensions.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }
}
