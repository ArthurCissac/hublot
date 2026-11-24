// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import SwiftUI

/// Lot 9f: the one-click scan (see `ForkSmartScanLogic`), opened first from
/// the Cleaner page's tools bar. It drives upstream's cleaner
/// (`JunkCleaner.shared`, so its finds also show on the Cleaner page), the
/// antivirus and the maintenance jobs, one after the other. With the window
/// closed it runs only on its schedule (`ForkCareAutomation`), which finds
/// and tells; nothing is removed before "Run".
final class ForkSmartScanWindow {
    static let shared = ForkSmartScanWindow()

    /// The Care window holds the one-click scan while it is open.
    var isOpen: Bool { ForkCareHub.shared.model != nil }

    /// Opens the Care window on the one-click scan (lot 9i).
    func show() { ForkCareHub.shared.show(.smartScan) }
}

final class ForkSmartScanModel: ObservableObject {
    typealias Logic = ForkSmartScanLogic

    enum Phase: Equatable {
        case welcome
        case scanning(Logic.Step)
        case results
        case running
        case done
    }

    @Published private(set) var phase = Phase.welcome
    /// The protection step's share of places scanned, for the ring.
    @Published private(set) var protectionFraction = 0.0
    /// The antivirus is fetching its signatures, the first time or once a day.
    @Published private(set) var protectionUpdating = false
    @Published private(set) var plan = Logic.Plan()
    @Published private(set) var protection = Logic.Protection.notInstalled
    @Published private(set) var cleanerAvailable = true
    @Published private(set) var outcome = Logic.Outcome()
    /// Something to say about the run, such as a dismissed password prompt.
    @Published private(set) var note: String?

    /// Kept for "Look": the antivirus window opens on this scan's threats.
    let antivirus = ForkAntivirusModel()
    private let maintenance = ForkMaintenanceModel()
    private var waiting: AnyCancellable?
    private var following: AnyCancellable?

    /// Waits for the first value of `publisher` that `done` accepts, on the
    /// main thread, then goes on. `@Published` sends before the value is
    /// stored; hopping to the main queue reads it once it is.
    private func wait<P: Publisher>(for publisher: P, until done: @escaping (P.Output) -> Bool,
                                    then next: @escaping (P.Output) -> Void) where P.Failure == Never {
        waiting = publisher.receive(on: DispatchQueue.main).first(where: done).sink { next($0) }
    }

    // MARK: - Scan

    func scan() {
        switch phase {
        case .welcome, .results, .done: break
        case .scanning, .running: return
        }
        note = nil
        plan = Logic.Plan()
        outcome = Logic.Outcome()
        scanCleaning()
    }

    private func scanCleaning() {
        phase = .scanning(.cleaning)
        cleanerAvailable = AppFeature.cleaner.isAvailable
        guard cleanerAvailable else { return scanProtection() }
        let cleaner = JunkCleaner.shared
        if cleaner.phase != .scanning {
            cleaner.reset()
            // Unattended: the screenshot search reads the user's own folders
            // and can ask for access; screenshots are never checked by itself anyway.
            cleaner.scan(attended: false)
        }
        wait(for: cleaner.$phase, until: { $0 == .results }) { [weak self] _ in
            guard let self else { return }
            let safe = JunkCleaner.shared.items.filter(\.recommended)
            self.plan.cleanCount = safe.count
            self.plan.cleanBytes = safe.reduce(0) { $0 + $1.size }
            self.scanProtection()
        }
    }

    private func scanProtection() {
        phase = .scanning(.protection)
        protectionFraction = 0
        antivirus.refresh()
        guard antivirus.clamscan != nil else {
            protection = .notInstalled
            return scanPerformance()
        }
        let apps = ForkAntivirusModel.recentAppPaths().map { path in
            Logic.RecentApp(path: path, bundleID: Bundle(path: path)?.bundleIdentifier,
                            fromAppStore: FileManager.default.fileExists(atPath: "\(path)/Contents/_MASReceipt/receipt"))
        }
        let targets = Logic.protectionTargets(recentDownloads: Self.recentDownloads(), home: NSHomeDirectory(),
                                              recentApps: Logic.quickAppTargets(apps))
            .filter { FileManager.default.fileExists(atPath: $0) }
        antivirus.scan(targets)
        guard antivirus.activity != .idle else {
            protection = .clean
            return scanPerformance()
        }
        following = antivirus.$activity.receive(on: DispatchQueue.main).sink { [weak self] activity in
            self?.protectionUpdating = activity == .updating
            if case let .scanning(done, total, _) = activity, total > 0 {
                self?.protectionFraction = Double(done) / Double(total)
            }
        }
        wait(for: antivirus.$showingSummary, until: { $0 }) { [weak self] _ in
            guard let self else { return }
            self.following = nil
            self.protectionUpdating = false
            self.protection = Logic.protection(installed: true, threats: self.antivirus.threats.count)
            self.scanPerformance()
        }
    }

    /// Downloads' top level with when each item arrived there.
    private static func recentDownloads() -> [String] {
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        let entries: [(path: String, arrived: Date)] = items.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard let date = values?.addedToDirectoryDate ?? values?.contentModificationDate else { return nil }
            return (url.path, date)
        }
        return Logic.recentDownloads(entries, now: Date())
    }

    private func scanPerformance() {
        phase = .scanning(.performance)
        let stored = UserDefaults.standard.dictionary(forKey: DefaultsKey.forkMaintenanceLastRuns) as? [String: Double]
        plan.jobs = Logic.dueJobs(lastRuns: ForkMaintenanceLogic.lastRuns(stored: stored), now: Date())
        phase = .results
    }

    /// Stops a scan under way and goes back to the welcome screen. A run in
    /// progress (a password prompt, files moving to the Trash) is left to end.
    func stopScanning() {
        guard case .scanning = phase else { return }
        waiting = nil
        following = nil
        if JunkCleaner.shared.phase == .scanning { JunkCleaner.shared.reset() }
        antivirus.cancel()
        phase = .welcome
    }

    func backToWelcome() {
        guard phase == .results || phase == .done else { return }
        phase = .welcome
    }

    // MARK: - Run

    /// The jobs due first, so their one password prompt comes at once, then
    /// the safe junk to the Trash. Threats are left for the antivirus.
    func run() {
        guard phase == .results, plan.hasWork else { return }
        phase = .running
        note = nil
        runJobs()
    }

    private func runJobs() {
        guard !plan.jobs.isEmpty else { return runCleaning(jobResults: []) }
        maintenance.run(jobs: plan.jobs)
        guard maintenance.running else { return runCleaning(jobResults: []) }
        wait(for: maintenance.$summaryReady, until: { $0 }) { [weak self] _ in
            guard let self else { return }
            let results = self.plan.jobs.compactMap { self.maintenance.results[$0] }
            self.note = self.maintenance.message
            self.maintenance.dismissSummary()
            self.runCleaning(jobResults: results)
        }
    }

    private func runCleaning(jobResults: [Bool]) {
        let cleaner = JunkCleaner.shared
        guard plan.cleanCount > 0, cleaner.phase == .results else {
            return finish(freed: 0, failed: 0, jobResults: jobResults)
        }
        // Exactly what the cleaner checks by itself, whatever was ticked on
        // the Cleaner page since; nothing else goes.
        cleaner.items = cleaner.items.map { item in
            var item = item
            item.include = item.recommended
            return item
        }
        // No escalation: what the Trash refuses stays put rather than
        // raising a second password prompt; the Cleaner page offers it.
        cleaner.cleanSelected(escalate: false)
        wait(for: cleaner.$phase, until: { phase in
            if case .done = phase { return true }
            return phase == .idle
        }) { [weak self] phase in
            guard case let .done(freed, failed) = phase else {
                self?.finish(freed: 0, failed: 0, jobResults: jobResults)
                return
            }
            self?.finish(freed: freed, failed: failed, jobResults: jobResults)
        }
    }

    private func finish(freed: Int64, failed: Int, jobResults: [Bool]) {
        outcome = Logic.outcome(freed: freed, cleanFailed: failed, jobResults: jobResults)
        phase = .done
    }

    // MARK: - Details

    func openCleaner() { ForkCareHub.shared.show(.cleanup) }

    func openAntivirus() { ForkAntivirusWindow.shared.show(model: antivirus) }

    func openMaintenance() { ForkMaintenanceWindow.shared.show() }

    /// The protection card's chip: ClamAV installed from here, after the
    /// antivirus's own confirmation; a new scan then counts it.
    func installAntivirus() { antivirus.install() }
}

/// Screens on the one-click gradient: welcome, the three steps under way,
/// the results in three tiles with one round "Run", the run, and its summary.
struct ForkSmartScanView: View {
    typealias Logic = ForkSmartScanLogic
    @ObservedObject var model: ForkSmartScanModel

    var body: some View {
        let text = ForkSmartScanStrings.current
        let care = ForkCareStrings.current
        ZStack {
            ForkCareBackground(tool: .smartScan)
            Group {
                switch model.phase {
                case .welcome: welcome(text, care)
                case .scanning(let step): scanning(step, text, care)
                case .results: results(text, care)
                case .running: running(text, care)
                case .done: done(text, care)
                }
            }
            .transition(.opacity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.22), value: model.phase)
        .environment(\.forkCareTool, .smartScan)
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static func name(_ step: Logic.Step, _ text: ForkSmartScanStrings) -> String {
        switch step {
        case .cleaning: return text.cleaning
        case .protection: return text.protection
        case .performance: return text.performance
        }
    }

    private static func symbol(_ step: Logic.Step) -> String {
        switch step {
        case .cleaning: return "trash"
        case .protection: return "checkmark.shield"
        case .performance: return "gauge.with.dots.needle.67percent"
        }
    }

    // MARK: - Welcome and scan

    private func welcome(_ text: ForkSmartScanStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForkCareHero(symbol: "wand.and.stars", title: text.title, subtitle: text.subtitle)
            steps(current: nil, text)
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.analyze) { model.scan() }
            ForkSmartScanScheduleLink()
        }
    }

    /// The three steps in a row: done ones ticked, the current one turning.
    private func steps(current: Logic.Step?, _ text: ForkSmartScanStrings) -> some View {
        HStack(spacing: 22) {
            ForEach(Logic.Step.allCases, id: \.self) { step in
                HStack(spacing: 7) {
                    if let current, step.rawValue < current.rawValue {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                    } else if step == current {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: Self.symbol(step)).foregroundStyle(Color.careSecondary)
                    }
                    Text(Self.name(step, text))
                        .font(.system(size: 13, weight: step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? Color.carePrimary : Color.careSecondary)
                }
            }
        }
    }

    private func scanning(_ step: Logic.Step, _ text: ForkSmartScanStrings, _ care: ForkCareStrings) -> some View {
        let line: String
        switch step {
        case .cleaning: line = text.scanningCleaning
        case .protection:
            line = model.protectionUpdating ? ForkDiskToolsStrings.current.updating : text.scanningProtection
        case .performance: line = text.scanningPerformance
        }
        let fraction = step == .protection ? model.protectionFraction : 0
        return VStack(spacing: 22) {
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.working, working: true,
                                progress: Logic.progress(step: step, fraction: fraction)) {}
            Text(line).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.carePrimary)
            steps(current: step, text)
            ForkCareLink(title: care.stop, symbol: "stop.fill") { model.stopScanning() }
            Spacer(minLength: 8)
        }
    }

    // MARK: - Results

    private func results(_ text: ForkSmartScanStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            Text(text.resultsTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.carePrimary)
                .forkCareAppear()
            HStack(alignment: .top, spacing: 14) {
                cleaningTile(text).forkCareAppear(index: 1)
                protectionTile(text).forkCareAppear(index: 2)
                performanceTile(text).forkCareAppear(index: 3)
            }
            .frame(maxWidth: 760)
            Spacer(minLength: 8)
            Group {
                if model.plan.hasWork {
                    ForkCareRoundButton(title: text.run) { model.run() }
                } else {
                    Text(text.allGood).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.carePrimary)
                    ForkCareRoundButton(title: care.finish) { model.backToWelcome() }
                }
            }
            .forkCareAppear(index: 4)
            ForkCareLink(title: text.rescan, symbol: "arrow.clockwise") { model.scan() }
        }
    }

    /// What a card offers: a link to the tool, or a filled chip when
    /// something waits to be done there.
    private enum TileAction {
        case link(String, () -> Void)
        case chip(String, () -> Void)
    }

    private func cleaningTile(_ text: ForkSmartScanStrings) -> some View {
        let plan = model.plan
        let category = ForkCareLogic.Category.cleaning
        let value: AnyView
        if model.cleanerAvailable, plan.cleanCount > 0 {
            value = AnyView(ForkCareCountUp(target: Double(plan.cleanBytes)) { text.toFree(Self.bytes(Int64($0))) }
                .foregroundStyle(Color.careAccent(category)))
        } else {
            value = AnyView(Text(text.nothingToClean).foregroundStyle(Color.carePrimary))
        }
        let detail = !model.cleanerAvailable ? text.cleanerOff
            : (plan.cleanCount > 0 ? text.safeItems(plan.cleanCount) : nil)
        return tile(.cleaning, text, category: category, value: value, detail: detail,
                    action: model.cleanerAvailable ? .link(text.seeDetails, model.openCleaner) : nil)
    }

    private func protectionTile(_ text: ForkSmartScanStrings) -> some View {
        let care = ForkCareStrings.current
        let disk = ForkDiskToolsStrings.current
        switch model.protection {
        case .notInstalled:
            return tile(.protection, text, category: .warning,
                        value: AnyView(Text(text.notInstalled).foregroundStyle(Color.careAccent(.warning))),
                        detail: text.installHint, action: .chip(care.install, model.installAntivirus))
        case .clean:
            return tile(.protection, text, category: .protection,
                        value: AnyView(Text(care.noThreat).foregroundStyle(Color.careAccent(.protection))),
                        detail: text.cleanHint, action: .link(text.seeDetails, model.openAntivirus))
        case .threats(let count):
            return tile(.protection, text, category: .danger,
                        value: AnyView(ForkCareCountUp(target: Double(count)) { disk.threatsFound(Int($0.rounded())) }
                            .foregroundStyle(Color.careAccent(.danger))),
                        detail: text.threatsHint, action: .chip(text.look, model.openAntivirus))
        }
    }

    private func performanceTile(_ text: ForkSmartScanStrings) -> some View {
        let jobs = model.plan.jobs
        let maintenance = ForkMaintenanceStrings.current
        let names = jobs.map { job -> String in
            switch job {
            case .dns: return maintenance.dnsTitle
            case .launchServices: return maintenance.launchServicesTitle
            case .memory: return maintenance.memoryTitle
            case .spotlight: return maintenance.spotlightTitle
            }
        }
        let accent = Color.careAccent(.performance)
        let value = jobs.isEmpty
            ? AnyView(Text(text.upToDate).foregroundStyle(accent))
            : AnyView(ForkCareCountUp(target: Double(jobs.count)) { text.jobsDue(Int($0.rounded())) }.foregroundStyle(accent))
        return tile(.performance, text, category: .performance, value: value,
                    detail: jobs.isEmpty ? text.upToDateHint : names.joined(separator: " · "),
                    action: .link(text.seeDetails, model.openMaintenance))
    }

    private func tile(_ step: Logic.Step, _ text: ForkSmartScanStrings, category: ForkCareLogic.Category,
                      value: AnyView, detail: String?, action: TileAction?) -> some View {
        let accent = Color.careAccent(category)
        return ForkCareCard(hoverable: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: Self.symbol(step))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(accent.opacity(0.18)))
                        .accessibilityHidden(true)
                    Text(Self.name(step, text))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.careSecondary)
                }
                value
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.careSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                switch action {
                case .link(let title, let perform):
                    ForkCareLink(title: title, symbol: "chevron.right", action: perform).padding(.leading, -10)
                case .chip(let title, let perform):
                    ForkCareActionChip(title: title, tint: accent, action: perform)
                case nil:
                    EmptyView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        }
    }

    // MARK: - Run and summary

    private func running(_ text: ForkSmartScanStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.working, working: true) {}
            Text(text.running).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.carePrimary)
            Spacer(minLength: 8)
        }
    }

    private func done(_ text: ForkSmartScanStrings, _ care: ForkCareStrings) -> some View {
        let outcome = model.outcome
        var parts: [String] = []
        if outcome.freedBytes > 0 { parts.append(text.freed(Self.bytes(outcome.freedBytes))) }
        if outcome.jobsDone > 0 { parts.append(care.allDone(outcome.jobsDone)) }
        let headline = parts.isEmpty ? care.nothingRan : parts.joined(separator: " · ")
        let failures = [outcome.cleanFailed > 0 ? text.cleanFailed(outcome.cleanFailed) : nil,
                        outcome.jobsFailed > 0 ? text.jobsFailed(outcome.jobsFailed) : nil].compactMap { $0 }
        let calm = failures.isEmpty && !outcome.nothingDone
        return VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForkCareSummary(symbol: "exclamationmark.triangle.fill",
                            tint: calm ? Color.careAccent(.cleaning) : Color.careAccent(.warning),
                            headline: headline, detail: nil, success: calm)
            ForEach(failures, id: \.self) { ForkCareNotice(text: $0) }
            if let note = model.note { ForkCareNotice(text: note) }
            if case .threats = model.protection {
                ForkCareLink(title: ForkDiskToolsStrings.current.threatsFound(model.antivirus.threats.count),
                             symbol: "exclamationmark.shield") { model.openAntivirus() }
            }
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.finish) { model.backToWelcome() }
            Color.clear.frame(height: 28)
        }
    }
}
