// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 9, the antivirus (see `ForkAntivirusLogic`): ClamAV's own programs,
/// installed with Homebrew after a confirmation, its signatures refreshed by
/// `freshclam` when older than a day, `clamscan` run on demand on the quick
/// scan's places or on a folder. A threat can be set aside in a quarantine
/// folder, then restored or deleted. Every program runs through upstream's
/// bounded runner, with a deadline and a cancel. In the background, only
/// what `ForkCareAutomation` was allowed to do: the daily signature check and
/// the scan of new downloads.
final class ForkAntivirusWindow {
    static let shared = ForkAntivirusWindow()

    /// Opens the Care window on Protection (lot 9i). `model` hands over a scan
    /// already made, by the one-click scan or the downloads' watch, so its
    /// threats show there.
    func show(model given: ForkAntivirusModel? = nil) { ForkCareHub.shared.show(.protection, antivirus: given) }
}

final class ForkAntivirusModel: ObservableObject {
    typealias Logic = ForkAntivirusLogic

    struct Threat: Identifiable, Equatable {
        let id = UUID()
        let path: String
        let signature: String
    }

    enum Activity: Equatable {
        case idle, installing, updating
        case scanning(done: Int, total: Int, target: String)
    }

    @Published private(set) var clamscan: String?
    @Published private(set) var freshclam: String?
    @Published private(set) var signaturesDate: Date?
    @Published private(set) var activity = Activity.idle
    @Published private(set) var threats: [Threat] = []
    @Published private(set) var lastScan: (date: Date, count: Int)?
    @Published private(set) var quarantine: [Logic.QuarantineItem] = []
    @Published var message: String?
    /// A scan finished and its summary is on screen (lot 9e).
    @Published private(set) var showingSummary = false
    private var cancellation = BoundedProcessCancellation()
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.antivirus", qos: .userInitiated)

    init() {
        refresh()
        loadQuarantine()
    }

    private static func exists(_ path: String) -> Bool { FileManager.default.isExecutableFile(atPath: path) }

    func refresh() {
        clamscan = Logic.tool("clamscan", existing: Self.exists)
        freshclam = Logic.tool("freshclam", existing: Self.exists)
        signaturesDate = clamscan.flatMap { tool in
            let folder = Logic.databaseDirectory(forTool: tool)
            return ["daily.cld", "daily.cvd"].compactMap { name in
                try? FileManager.default.attributesOfItem(atPath: "\(folder)/\(name)")[.modificationDate] as? Date
            }.max()
        }
    }

    func cancel() {
        cancellation.cancel()
    }

    /// When the signatures were last known current: their file's date, or a
    /// later check that found nothing newer.
    var freshness: Date? {
        ForkCareAutomationLogic.freshness(
            fileDate: signaturesDate,
            lastCheck: UserDefaults.standard.object(forKey: DefaultsKey.forkAntivirusLastCheck) as? Date)
    }

    private var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (Logic.prefixes.map { "\($0)/bin" } + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        return environment
    }

    /// Runs a program off the main thread and answers there.
    private func run(_ path: String, _ arguments: [String], timeout: TimeInterval,
                     completion: @escaping (BoundedProcessRunner.Result) -> Void) {
        let cancellation = self.cancellation
        let environment = self.environment
        queue.async {
            let result = BoundedProcessRunner.run(path, arguments, timeout: timeout, maxOutputBytes: 4 << 20,
                                                  environment: environment, cancellation: cancellation)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Installing and updating

    /// Asks first: ClamAV comes from Homebrew, with its signatures, some 300 MB.
    func install() {
        let text = ForkDiskToolsStrings.current
        guard let brew = Logic.brew(existing: Self.exists) else {
            message = text.noHomebrew
            return
        }
        let alert = NSAlert()
        alert.messageText = text.installConfirm
        alert.informativeText = text.installDetail
        alert.addButton(withTitle: text.install)
        alert.addButton(withTitle: text.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cancellation = BoundedProcessCancellation()
        activity = .installing
        message = nil
        run(brew, ["install", "clamav"], timeout: 30 * 60) { [weak self] result in
            guard let self else { return }
            self.refresh()
            guard result.status == 0, self.freshclam != nil else {
                self.activity = .idle
                self.message = result.timedOut ? text.timedOut : text.installFailed
                return
            }
            self.update { _ in }
        }
    }

    /// `freshclam` needs its settings file: written once from Homebrew's sample.
    private func prepareFreshclam(_ tool: String) -> Bool {
        let folder = Logic.configDirectory(forTool: tool)
        let config = "\(folder)/freshclam.conf"
        if FileManager.default.fileExists(atPath: config) { return true }
        guard let sample = try? String(contentsOfFile: "\(folder)/freshclam.conf.sample", encoding: .utf8) else { return false }
        return (try? Logic.freshclamConfig(fromSample: sample).write(toFile: config, atomically: true, encoding: .utf8)) != nil
    }

    func update(then next: @escaping (Bool) -> Void) {
        let text = ForkDiskToolsStrings.current
        guard let freshclam, prepareFreshclam(freshclam) else {
            message = text.updateFailed
            activity = .idle
            next(false)
            return
        }
        activity = .updating
        run(freshclam, ["--stdout"], timeout: 15 * 60) { [weak self] result in
            guard let self else { return }
            if result.status == 0 { UserDefaults.standard.set(Date(), forKey: DefaultsKey.forkAntivirusLastCheck) }
            self.refresh()
            self.activity = .idle
            let ok = result.status == 0 || self.signaturesDate != nil
            if !ok { self.message = result.timedOut ? text.timedOut : text.updateFailed }
            next(ok)
        }
    }

    // MARK: - Scanning

    func quickScan() {
        let targets = Logic.quickTargets(home: NSHomeDirectory(), recentApps: Self.recentAppPaths())
        scan(targets.filter { FileManager.default.fileExists(atPath: $0) })
    }

    /// The apps added to /Applications within the last 30 days.
    static func recentAppPaths() -> [String] {
        let applications = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        let apps: [(path: String, added: Date)] = applications.filter { $0.hasSuffix(".app") }.compactMap { name in
            let url = URL(fileURLWithPath: "/Applications/\(name)")
            let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            guard let date = values?.addedToDirectoryDate ?? values?.creationDate else { return nil }
            return (url.path, date)
        }
        return Logic.recentApps(apps, now: Date())
    }

    func scanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan([url.path])
    }

    /// Signatures refreshed first when stale, then each place in turn.
    func scan(_ targets: [String]) {
        guard clamscan != nil, !targets.isEmpty else { return }
        cancellation = BoundedProcessCancellation()
        threats = []
        message = nil
        showingSummary = false
        if Logic.signaturesAreStale(updated: freshness, now: Date()) {
            update { [weak self] _ in self?.runScan(targets) }
        } else {
            runScan(targets)
        }
    }

    /// One run of clamscan over every place at once: its signatures (about
    /// 100 MB) load once, not once per place, which took longer than many
    /// of the scans themselves.
    private func runScan(_ targets: [String]) {
        guard let clamscan, !cancellation.isCancelled else { return finishScan(found: 0) }
        let names = targets.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        activity = .scanning(done: 0, total: 0, target: names)
        // Infected files only: the output stays small whatever is scanned.
        run(clamscan, ["-r", "-i", "--stdout", "--no-summary"] + targets, timeout: 3 * 3600) { [weak self] result in
            guard let self else { return }
            var found = 0
            for line in String(decoding: result.output, as: UTF8.self).split(separator: "\n").map(String.init) {
                if case let .threat(path, signature) = Logic.parse(line) {
                    self.threats.append(Threat(path: path, signature: signature))
                    found += 1
                }
            }
            if result.timedOut { self.message = ForkDiskToolsStrings.current.timedOut }
            self.finishScan(found: found)
        }
    }

    private func finishScan(found: Int) {
        activity = .idle
        lastScan = (Date(), found)
        showingSummary = true
    }

    /// Back to the welcome screen; threats not yet set aside stay listed.
    func dismissSummary() { showingSummary = false }

    func reopenSummary() { showingSummary = true }

    func setAsideAll() {
        for threat in threats { setAside(threat) }
    }

    // MARK: - Quarantine

    private var quarantineFolder: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Library/Application Support"
        return "\(support)/\(AppInfo.name)/Quarantine"
    }

    private var indexPath: String { quarantineFolder + "/index.json" }

    private func loadQuarantine() {
        guard let data = FileManager.default.contents(atPath: indexPath),
              let items = try? JSONDecoder().decode([Logic.QuarantineItem].self, from: data) else { return }
        quarantine = items
    }

    private func saveQuarantine() {
        try? FileManager.default.createDirectory(atPath: quarantineFolder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(quarantine) { try? data.write(to: URL(fileURLWithPath: indexPath)) }
    }

    /// Moved into the quarantine folder and made unreadable to anything but this app's owner, never executable.
    func setAside(_ threat: Threat) {
        let id = UUID()
        let stored = Logic.quarantinePath(for: threat.path, id: id, in: quarantineFolder)
        do {
            try FileManager.default.createDirectory(atPath: (stored as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try FileManager.default.moveItem(atPath: threat.path, toPath: stored)
            try? FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: stored)
            quarantine.append(Logic.QuarantineItem(id: id, originalPath: threat.path, storedPath: stored,
                                                   signature: threat.signature, date: Date()))
            saveQuarantine()
            threats.removeAll { $0 == threat }
        } catch {
            message = ForkDiskToolsStrings.current.moveFailed(error.localizedDescription)
        }
    }

    func restore(_ item: Logic.QuarantineItem) {
        do {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: item.storedPath)
            try FileManager.default.moveItem(atPath: item.storedPath, toPath: item.originalPath)
            try? FileManager.default.removeItem(atPath: (item.storedPath as NSString).deletingLastPathComponent)
            quarantine.removeAll { $0.id == item.id }
            saveQuarantine()
        } catch {
            message = ForkDiskToolsStrings.current.moveFailed(error.localizedDescription)
        }
    }

    /// Asks first: deleted for good, not to the Trash.
    func delete(_ item: Logic.QuarantineItem) {
        let text = ForkDiskToolsStrings.current
        let alert = NSAlert()
        alert.messageText = text.deleteConfirm((item.originalPath as NSString).lastPathComponent)
        alert.informativeText = text.deleteDetail
        alert.addButton(withTitle: text.delete)
        alert.addButton(withTitle: text.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(atPath: (item.storedPath as NSString).deletingLastPathComponent)
        quarantine.removeAll { $0.id == item.id }
        saveQuarantine()
    }
}


/// Screens on the antivirus gradient: welcome (install, or one round "Scan"
/// button with the folder scan and the quarantine as links), the scan under
/// way, its summary, and the quarantine.
struct ForkAntivirusView: View {
    @ObservedObject var model: ForkAntivirusModel
    @State private var showingQuarantine = false

    var body: some View {
        let text = ForkDiskToolsStrings.current
        let care = ForkCareStrings.current
        let working = model.activity != .idle
        let stage = ForkCareLogic.stage(working: working, summaryReady: model.showingSummary)
        ZStack {
            ForkCareBackground(tool: .antivirus)
            Group {
                if showingQuarantine, !working {
                    quarantine(text, care)
                } else {
                    switch stage {
                    case .welcome: welcome(text, care)
                    case .working: progress(text, care)
                    case .summary: summary(text, care)
                    }
                }
            }
            .transition(.opacity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.22), value: stage)
        .animation(.easeOut(duration: 0.22), value: showingQuarantine)
        .environment(\.forkCareTool, .antivirus)
    }

    // MARK: - Welcome

    private func welcome(_ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            if model.clamscan == nil {
                ForkCareHero(symbol: "shield.slash", title: text.notInstalled, subtitle: text.notInstalledDetail)
                Spacer(minLength: 8)
                ForkCareRoundButton(title: care.install) { model.install() }
                // The room a link takes under the other screens' round button.
                Color.clear.frame(height: 28)
            } else {
                ForkCareHero(symbol: "checkmark.shield", title: text.antivirusTitle, subtitle: care.antivirusSubtitle)
                Text(model.signaturesDate.map { text.signatures($0) } ?? text.noSignatures)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.careSecondary)
                if ForkCareAutomationLogic.signaturesAreOld(freshness: model.freshness, now: Date()) {
                    Label(ForkCareAutomationStrings.current.signaturesOld, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 8)
                ForkCareRoundButton(title: care.analyze) { model.quickScan() }
                HStack(spacing: 4) {
                    ForkCareLink(title: text.scanFolder, symbol: "folder") { model.scanFolder() }
                    if !model.threats.isEmpty {
                        ForkCareLink(title: text.threatsFound(model.threats.count), symbol: "exclamationmark.shield") {
                            model.reopenSummary()
                        }
                    }
                    if !model.quarantine.isEmpty {
                        ForkCareLink(title: care.quarantine(model.quarantine.count), symbol: "archivebox") {
                            showingQuarantine = true
                        }
                    }
                }
            }
            if let message = model.message { ForkCareNotice(text: message) }
            if model.clamscan != nil { ForkAntivirusAutomationOptions() }
        }
    }

    // MARK: - Under way

    private func progress(_ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        let line: String
        var ring: Double?
        var cancellable = false
        switch model.activity {
        case .idle, .installing: line = text.installing
        case .updating: line = text.updating
        case let .scanning(done, total, target):
            line = text.scanningTarget(target)
            ring = ForkCareLogic.progress(done: done, total: total)
            cancellable = true
        }
        return VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.working, working: true, progress: ring) {}
            Text(line)
                .font(.system(size: 13))
                .foregroundStyle(Color.careSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            if cancellable { ForkCareLink(title: care.stop, symbol: "stop.fill") { model.cancel() } }
            Spacer(minLength: 8)
        }
    }

    // MARK: - Summary

    private func summary(_ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        let detail = model.lastScan.map { text.lastScan($0.date, $0.count) }
        return VStack(spacing: 20) {
            Spacer(minLength: 8)
            if model.threats.isEmpty {
                ForkCareSummary(symbol: "checkmark.shield.fill", tint: Color.careAccent(.cleaning),
                                headline: care.noThreat, detail: detail, success: true)
            } else {
                ForkCareSummary(symbol: "exclamationmark.shield.fill", tint: Color.careAccent(.danger),
                                headline: text.threatsFound(model.threats.count), detail: detail)
                ForkCareCard {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.threats) { threat in threatRow(threat, text) }
                        }
                        .padding(16)
                    }
                }
                .frame(maxWidth: 560, maxHeight: 220)
                ForkCareLink(title: care.quarantineAll, symbol: "archivebox") { model.setAsideAll() }
            }
            if let message = model.message { ForkCareNotice(text: message) }
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.finish) { model.dismissSummary() }
        }
    }

    private func threatRow(_ threat: ForkAntivirusModel.Threat, _ text: ForkDiskToolsStrings) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text((threat.path as NSString).lastPathComponent).foregroundStyle(Color.carePrimary).lineLimit(1)
                Text(threat.signature).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                Text(threat.path).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(text.setAside) { model.setAside(threat) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - Quarantine

    private func quarantine(_ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 18) {
            Text(text.quarantineTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.carePrimary)
            ForkCareCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.quarantine) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((item.originalPath as NSString).lastPathComponent)
                                        .foregroundStyle(Color.carePrimary).lineLimit(1)
                                    Text(item.signature).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                                }
                                Spacer(minLength: 8)
                                Button(text.restore) { model.restore(item) }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Button(text.delete, role: .destructive) { model.delete(item) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 580)
            if let message = model.message { ForkCareNotice(text: message) }
            ForkCareLink(title: care.back, symbol: "chevron.left") { showingQuarantine = false }
        }
        .onChange(of: model.quarantine.isEmpty) { _, empty in
            if empty { showingQuarantine = false }
        }
    }
}
