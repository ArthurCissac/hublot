// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 9d: the maintenance window, opened from the Cleaner page's tools bar.
/// Checked jobs run on request: those needing administrator rights together,
/// behind one password prompt from macOS (the password is typed in macOS's
/// own dialog, never seen by the app), then "Open With" as the user.
final class ForkMaintenanceWindow {
    static let shared = ForkMaintenanceWindow()

    /// Opens the Care window on maintenance (lot 9i).
    func show() { ForkCareHub.shared.show(.performance) }
}

final class ForkMaintenanceModel: ObservableObject {
    typealias Logic = ForkMaintenanceLogic

    @Published private(set) var selection: [Logic.Job]
    @Published private(set) var lastRuns: [Logic.Job: Date]
    /// Each job's success in the last run of this window.
    @Published private(set) var results: [Logic.Job: Bool] = [:]
    @Published private(set) var running = false
    /// The jobs of the run under way or just finished, for the screens that follow.
    @Published private(set) var runJobs: [Logic.Job] = []
    /// A run finished and its summary has not been put away yet.
    @Published private(set) var summaryReady = false
    @Published private(set) var message: String?
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.maintenance", qos: .userInitiated)

    init() {
        let defaults = UserDefaults.standard
        selection = Logic.selection(stored: defaults.stringArray(forKey: DefaultsKey.forkMaintenanceSelection))
        lastRuns = Logic.lastRuns(stored: defaults.dictionary(forKey: DefaultsKey.forkMaintenanceLastRuns) as? [String: Double])
    }

    func isSelected(_ job: Logic.Job) -> Bool { selection.contains(job) }

    func set(_ job: Logic.Job, selected: Bool) {
        var jobs = selection.filter { $0 != job }
        if selected { jobs.append(job) }
        selection = Logic.selection(stored: Logic.stored(jobs))
        UserDefaults.standard.set(Logic.stored(selection), forKey: DefaultsKey.forkMaintenanceSelection)
    }

    func run() { run(jobs: selection) }

    /// Runs these jobs, the selection or the one-click scan's due jobs,
    /// leaving the saved selection as it is.
    func run(jobs: [Logic.Job]) {
        guard !jobs.isEmpty, !running else { return }
        let text = ForkMaintenanceStrings.current
        if jobs.contains(where: \.asksConfirmation) {
            let alert = NSAlert()
            alert.messageText = text.spotlightConfirm
            alert.informativeText = text.spotlightDetail
            alert.addButton(withTitle: text.reindex)
            alert.addButton(withTitle: text.cancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        running = true
        runJobs = jobs
        summaryReady = false
        results = [:]
        message = nil

        let script = Logic.administratorScript(jobs)
        let prompt = text.administratorPrompt(AppInfo.name)
        let cancelledNote = text.cancelled
        let failedNote = text.administratorFailed
        // An agent app's password dialog can open behind the frontmost app;
        // upstream's AdminShell brings the app forward first for that reason.
        if script != nil { NSApp.activate(ignoringOtherApps: true) }
        queue.async { [weak self] in
            var results: [Logic.Job: Bool] = [:]
            var note: String?
            if let script {
                let source = AdminShell.appleScriptSource(command: script, prompt: prompt)
                // A person typing a password is not a stuck command: the same
                // bound as upstream's administrator prompts.
                let answer = BoundedProcessRunner.run("/usr/bin/osascript", ["-e", source],
                                                      timeout: 600, maxOutputBytes: 1 << 20)
                switch Logic.administratorOutcome(status: answer.status,
                                                  output: String(decoding: answer.output, as: UTF8.self), jobs: jobs) {
                case .done(let done): results.merge(done) { $1 }
                case .cancelled: note = cancelledNote
                case .failed: note = failedNote
                }
            }
            if jobs.contains(.launchServices) {
                results[.launchServices] = Logic.launchServicesRuns.allSatisfy { arguments in
                    BoundedProcessRunner.run(Logic.lsregisterPath, arguments, timeout: 180, maxOutputBytes: 1 << 20).status == 0
                }
            }
            DispatchQueue.main.async { self?.finish(results, note: note) }
        }
    }

    private func finish(_ results: [Logic.Job: Bool], note: String?) {
        self.results = results
        let now = Date()
        for (job, ok) in results where ok { lastRuns[job] = now }
        UserDefaults.standard.set(Logic.stored(lastRuns), forKey: DefaultsKey.forkMaintenanceLastRuns)
        message = note
        summaryReady = true
        running = false
    }

    /// Back to the welcome screen once the summary is read.
    func dismissSummary() {
        summaryReady = false
        results = [:]
        message = nil
    }
}


/// Three screens on the maintenance gradient: welcome with one round
/// "Run" button (the list of jobs folded behind a link), the jobs under way,
/// then a summary of how each went.
struct ForkMaintenanceView: View {
    typealias Logic = ForkMaintenanceLogic
    @ObservedObject var model: ForkMaintenanceModel
    @State private var showingJobs = false

    var body: some View {
        let text = ForkMaintenanceStrings.current
        let care = ForkCareStrings.current
        let stage = ForkCareLogic.stage(working: model.running, summaryReady: model.summaryReady)
        ZStack {
            ForkCareBackground(tool: .maintenance)
            Group {
                switch stage {
                case .welcome: welcome(text, care)
                case .working: working(text, care)
                case .summary: summary(text, care)
                }
            }
            .transition(.opacity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.22), value: stage)
        .environment(\.forkCareTool, .maintenance)
    }

    // MARK: - Welcome

    private func welcome(_ text: ForkMaintenanceStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            if showingJobs {
                jobList(text)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ForkCareHero(symbol: "wrench.and.screwdriver", title: text.title, subtitle: care.maintenanceSubtitle)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            ForkCareRoundButton(title: text.run, enabled: !model.selection.isEmpty) { model.run() }
            ForkCareLink(title: showingJobs ? care.hideJobs : "\(care.chosen(model.selection.count)) · \(care.chooseJobs)",
                         symbol: showingJobs ? "chevron.down" : "list.bullet") {
                withAnimation(.easeOut(duration: 0.22)) { showingJobs.toggle() }
            }
        }
    }

    private func jobList(_ text: ForkMaintenanceStrings) -> some View {
        ForkCareCard {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Logic.Job.allCases) { job in
                        jobRow(job, text)
                        if job != Logic.Job.allCases.last {
                            Rectangle().fill(Color.careVeil(0.10)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: 580)
    }

    private func jobRow(_ job: Logic.Job, _ text: ForkMaintenanceStrings) -> some View {
        let words = Self.words(job, text)
        let selected = Binding(get: { model.isSelected(job) }, set: { model.set(job, selected: $0) })
        return HStack(alignment: .top, spacing: 12) {
            Toggle(words.title, isOn: selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)
            Image(systemName: job.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.carePrimary)
                .frame(width: 24)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(words.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.carePrimary)
                    if job.needsAdministrator {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.careSecondary)
                            .accessibilityLabel(text.needsPassword)
                    }
                }
                Text(words.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.careSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lastRun(job, text))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.careSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { selected.wrappedValue.toggle() }
    }

    // MARK: - Working

    private func working(_ text: ForkMaintenanceStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.working, working: true) {}
            Text(text.running)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.carePrimary)
            ForkCareCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.runJobs) { job in
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(Self.words(job, text).title).foregroundStyle(Color.carePrimary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: 420)
            Spacer(minLength: 8)
        }
    }

    // MARK: - Summary

    private func summary(_ text: ForkMaintenanceStrings, _ care: ForkCareStrings) -> some View {
        let outcome = ForkCareLogic.maintenanceOutcome(model.runJobs.compactMap { model.results[$0] })
        let look: (symbol: String, tint: Color, headline: String)
        switch outcome {
        case .allDone(let count): look = ("checkmark.seal.fill", Color.careAccent(.cleaning), care.allDone(count))
        case let .partly(done, failed): look = ("exclamationmark.triangle.fill", Color.careAccent(.warning), care.partly(done, failed))
        case .nothingRan: look = ("xmark.circle.fill", Color.careAccent(.warning), care.nothingRan)
        }
        let success: Bool
        if case .allDone = outcome { success = true } else { success = false }
        return VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForkCareSummary(symbol: look.symbol, tint: look.tint, headline: look.headline, detail: nil, success: success)
            ForkCareCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.runJobs) { job in resultRow(job, text, care) }
                }
                .padding(16)
            }
            .frame(maxWidth: 440)
            .forkCareAppear(index: 2)
            if let message = model.message { ForkCareNotice(text: message) }
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.finish) { model.dismissSummary() }
            ForkCareLink(title: care.runAgain, symbol: "arrow.clockwise") { model.run() }
        }
    }

    private func resultRow(_ job: Logic.Job, _ text: ForkMaintenanceStrings, _ care: ForkCareStrings) -> some View {
        let result = model.results[job]
        let symbol = result.map { $0 ? "checkmark.circle.fill" : "xmark.octagon.fill" } ?? "minus.circle"
        let tint: Color = result.map { $0 ? Color.green : Color.red } ?? Color.careSecondary
        let label = result.map { $0 ? text.done : text.failed } ?? care.notRun
        return HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(Self.words(job, text).title).foregroundStyle(Color.carePrimary)
            Spacer(minLength: 8)
            Text(label).font(.system(size: 12)).foregroundStyle(Color.careSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func words(_ job: Logic.Job, _ text: ForkMaintenanceStrings) -> (title: String, caption: String) {
        switch job {
        case .dns: return (text.dnsTitle, text.dnsCaption)
        case .launchServices: return (text.launchServicesTitle, text.launchServicesCaption)
        case .memory: return (text.memoryTitle, text.memoryCaption)
        case .spotlight: return (text.spotlightTitle, text.spotlightCaption)
        }
    }

    private func lastRun(_ job: Logic.Job, _ text: ForkMaintenanceStrings) -> String {
        guard let date = model.lastRuns[job] else { return text.never }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.shared.language == .fr ? "fr" : "en")
        return text.lastRun(formatter.localizedString(for: date, relativeTo: Date()))
    }
}
