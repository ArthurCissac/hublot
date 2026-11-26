// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import SwiftUI

/// The AI page's Claude additions. While the page and Claude are on, reads
/// every three seconds the records Claude Code keeps beside its logs: a
/// session whose state turns to waiting (a permission, a question, a plan
/// to approve) gets a notice in the island and the Waiting card, and a click
/// opens it in the Claude app (or brings its terminal forward). Once a
/// minute, the latest projects worked on with Claude, from its logs, for the
/// Pick up again card: a project, there or in the Projects card, opens in
/// its most recent Claude Code session (the Claude app keeps one small file
/// per session, running or not), or in a new one in its folder, through the
/// Claude app's own links; a new session or the folder in the Finder are a
/// click away. Nothing is written anywhere. The logic is `ForkClaudeSessionsLogic`.
final class ForkClaudeSessions: ObservableObject {
    static let shared = ForkClaudeSessions()
    typealias Logic = ForkClaudeSessionsLogic

    @Published private(set) var waiting: [Logic.Session] = []
    @Published private(set) var recent: [Logic.Project] = []
    /// Every session whose process runs, to open a project where it is worked on.
    @Published private(set) var running: [Logic.Session] = []

    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var announced: Set<String> = []
    private var lastRecent = Date.distantPast
    /// The Claude app's session files already read, by path: only a file
    /// changed since is read again. Used on `queue` only.
    private var appSessionCache: [String: (date: Date, session: Logic.AppSession?)] = [:]
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.claude-sessions", qos: .utility)
    private static let claudeApp = "com.anthropic.claudefordesktop"

    private var claudeHome: URL {
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude", directoryHint: .isDirectory)
    }

    private var active: Bool {
        NotchAgentSupport.isEnabled() && UserDefaults.standard.bool(forKey: DefaultsKey.notchAgentsClaude)
    }

    func start() {
        ForkAgentCardsLogic.sessionWaits = { [weak self] in !(self?.waiting.isEmpty ?? true) }
        Logic.goToWaiting = { [weak self] in self?.goToWaiting() }
        Logic.takeRecords = { records, now in ForkAgentTime.shared.update(records, now: now) }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.sync() }
        sync()
    }

    private func sync() {
        if active {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            poll()
        } else if timer != nil {
            timer?.invalidate()
            timer = nil
            waiting = []
            recent = []
            running = []
            announced = []
            lastRecent = .distantPast
        }
    }

    private func poll() {
        let home = claudeHome
        let readsRecent = Date().timeIntervalSince(lastRecent) >= 60
        if readsRecent { lastRecent = Date() }
        queue.async { [weak self] in
            let sessions = Self.readSessions(in: home.appending(path: "sessions", directoryHint: .isDirectory))
            let running = sessions.filter { AgentSessionRegistry.isRunning($0.pid) }
            let waiting = Logic.waiting(running, isRunning: { _ in true })
            let recent = readsRecent ? Self.readRecentProjects(in: home.appending(path: "projects", directoryHint: .isDirectory)) : nil
            DispatchQueue.main.async {
                guard let self, self.timer != nil else { return }
                if self.waiting != waiting { self.waiting = waiting }
                if self.running != running { self.running = running }
                if let recent, self.recent != recent { self.recent = recent }
                self.announce(waiting)
            }
        }
    }

    private static func readSessions(in folder: URL) -> [Logic.Session] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            (try? Data(contentsOf: folder.appending(path: name))).flatMap(Logic.session(from:))
        }
    }

    /// The newest log of each project folder names its working folder in
    /// its first lines; only the most recent few are opened.
    private static func readRecentProjects(in folder: URL) -> [Logic.Project] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var newest: [(log: URL, date: Date)] = []
        for project in projects {
            guard let logs = try? manager.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let dated = logs.filter { $0.pathExtension == "jsonl" }.compactMap { log -> (URL, Date)? in
                (try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (log, $0) }
            }
            if let latest = dated.max(by: { $0.1 < $1.1 }) { newest.append((latest.0, latest.1)) }
        }
        let candidates = newest.sorted { $0.date > $1.date }.prefix(12).compactMap { entry -> (path: String, date: Date)? in
            guard let handle = try? FileHandle(forReadingFrom: entry.log) else { return nil }
            defer { try? handle.close() }
            let head = String(decoding: (try? handle.read(upToCount: 1 << 16)) ?? Data(), as: UTF8.self)
            return Logic.workingFolder(inLogHead: head).map { (path: $0, date: entry.date) }
        }
        return Logic.recentProjects(Array(candidates))
    }

    // MARK: - The Claude app's sessions

    private var appSessionsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/claude-code-sessions", directoryHint: .isDirectory)
    }

    /// Reads the Claude app's sessions as they are now, then acts with them.
    private func withAppSessions(_ action: @escaping ([Logic.AppSession]) -> Void) {
        let folder = appSessionsFolder
        queue.async { [weak self] in
            guard let self else { return }
            let sessions = self.readAppSessions(in: folder)
            DispatchQueue.main.async { action(sessions) }
        }
    }

    private func readAppSessions(in folder: URL) -> [Logic.AppSession] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles]) else { return [] }
        var seen = Set<String>()
        var sessions: [Logic.AppSession] = []
        for case let url as URL in files {
            if files.level > 3 { files.skipDescendants(); continue }
            guard url.lastPathComponent.hasPrefix("local_"), url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: Set(keys)), let date = values.contentModificationDate,
                  values.fileSize ?? 0 <= Logic.maximumAppSessionSize else { continue }
            seen.insert(url.path)
            let session: Logic.AppSession?
            if let cached = appSessionCache[url.path], cached.date == date {
                session = cached.session
            } else {
                session = (try? Data(contentsOf: url)).flatMap(Logic.appSession(from:))
                appSessionCache[url.path] = (date, session)
            }
            if let session { sessions.append(session) }
        }
        appSessionCache = appSessionCache.filter { seen.contains($0.key) }
        return sessions
    }

    private func open(_ session: Logic.AppSession) -> Bool {
        guard let url = Logic.continueURL(appSession: session.id) else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - The notice

    private func announce(_ waiting: [Logic.Session]) {
        let now = Date()
        announced.formIntersection(waiting.map(Logic.key))
        guard UserDefaults.standard.bool(forKey: DefaultsKey.forkAgentsWaitingAlert), NotchSupport.isEnabled() else {
            announced.formUnion(waiting.map(Logic.key))
            return
        }
        let fresh = Logic.toAnnounce(waiting, announced: announced, now: now)
        guard let first = fresh.first else { return }
        announced.formUnion(fresh.map(Logic.key))
        let text = ForkAgentCardsStrings.current
        _ = NotchService.shared.show(NotchNotice(event: .agents, title: text.waitingTitle,
                                                 detail: fresh.count > 1 ? text.several(fresh.count) : first.name,
                                                 symbol: Logic.noticeSymbol, agent: .claude))
    }

    // MARK: - Actions

    /// The longest waiting session, from the notice.
    func goToWaiting() {
        if let first = waiting.first { goTo(first) }
    }

    /// A Claude app session opens where it is; for a session in a terminal,
    /// the app that started its process comes forward.
    func goTo(_ session: Logic.Session) {
        if session.host == .terminal, Self.activateOwner(of: session.pid) { return }
        if let id = session.appSession, let url = Logic.continueURL(appSession: id) {
            NSWorkspace.shared.open(url)
        } else {
            openClaude()
        }
    }

    private static func activateOwner(of pid: pid_t) -> Bool {
        var current: pid_t? = pid
        for _ in 0..<12 {
            guard let process = current else { return false }
            if let app = NSRunningApplication(processIdentifier: process), app.activationPolicy == .regular {
                return app.activate()
            }
            current = parent(of: process)
        }
        return false
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }

    private func openClaude() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeApp) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The project's most recent session in the Claude app (never an
    /// archived one), else the one running in its folder (a terminal's
    /// too), else a new one there.
    func resume(_ project: Logic.Project) {
        withAppSessions { [weak self] sessions in
            guard let self else { return }
            if let latest = Logic.latestAppSession(forFolder: project.path, in: sessions), self.open(latest) { return }
            if let session = Logic.openSession(for: project.path, in: self.running) {
                self.goTo(session)
            } else {
                self.newSession(project)
            }
        }
    }

    /// A project of the AI page, known by its folder's name: its most recent
    /// session, else one running in a folder of that name, else a new one
    /// in its folder when it is known.
    func openProject(named name: String) {
        withAppSessions { [weak self] sessions in
            guard let self else { return }
            if let latest = Logic.latestAppSession(named: name, in: sessions), self.open(latest) { return }
            if let session = self.running.filter({ Logic.projectName($0.cwd) == name })
                .max(by: { ($0.since ?? .distantPast) < ($1.since ?? .distantPast) }) {
                self.goTo(session)
            } else if let folder = self.recent.first(where: { $0.name == name })?.path ?? Logic.folder(named: name, in: sessions),
                      let url = Logic.newSessionURL(folder: folder) {
                NSWorkspace.shared.open(url)
            } else {
                self.openClaude()
            }
        }
    }

    /// A turn of the AI page's In progress card: its Claude Code session,
    /// found by the log it writes, else one running in a folder of its name.
    func open(_ live: AgentLiveSession) {
        let log = (live.id.components(separatedBy: "#").first ?? live.id) as NSString
        let id = (log.lastPathComponent as NSString).deletingPathExtension
        if let session = running.first(where: { $0.id == id })
            ?? running.filter({ Logic.projectName($0.cwd) == live.project }).max(by: { ($0.since ?? .distantPast) < ($1.since ?? .distantPast) }) {
            goTo(session)
        } else {
            openClaude()
        }
    }

    func newSession(_ project: Logic.Project) {
        if let url = Logic.newSessionURL(folder: project.path) { NSWorkspace.shared.open(url) } else { openClaude() }
    }

    func reveal(_ project: Logic.Project) {
        NSWorkspace.shared.open(URL(fileURLWithPath: project.path, isDirectory: true))
    }
}

// MARK: - Time on each project

/// The time spent with an agent on each project, for each of the AI page's
/// periods, from the requests the usage service reads. Worked out at most
/// every twenty seconds, off the main thread.
final class ForkAgentTime: ObservableObject {
    static let shared = ForkAgentTime()
    @Published private(set) var periods: [AgentPeriod: [ForkClaudeSessionsLogic.ProjectTime]] = [:]
    private var last = Date.distantPast

    /// Called by the usage service each time it takes a snapshot.
    func update(_ records: [AgentUsageRecord], now: Date) {
        guard now.timeIntervalSince(last) >= 20 || now < last else { return }
        last = now
        let requests = records.map { (project: $0.project, date: $0.date) }
        var periods: [AgentPeriod: [ForkClaudeSessionsLogic.ProjectTime]] = [:]
        for period in AgentPeriod.allCases {
            periods[period] = ForkClaudeSessionsLogic.projectTimes(
                requests, from: ForkClaudeSessionsLogic.start(of: period.days, now: now), to: now)
        }
        DispatchQueue.main.async { [weak self] in
            if self?.periods != periods { self?.periods = periods }
        }
    }
}

// MARK: - The cards

/// One of the fork's cards, as the AI page lays it out.
struct ForkAgentCard: View {
    let card: NotchAgentCard
    let period: AgentPeriod
    let snapshot: AgentUsageSnapshot

    var body: some View {
        switch card {
        case .forkWaiting: ForkAgentWaitingCard()
        case .forkTime: ForkAgentTimeCard(period: period, snapshot: snapshot)
        default: ForkAgentResumeCard()
        }
    }
}

private struct ForkAgentWaitingCard: View {
    @ObservedObject private var sessions = ForkClaudeSessions.shared

    var body: some View {
        let text = ForkAgentCardsStrings.current
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.title(.forkWaiting), symbol: ForkClaudeSessionsLogic.noticeSymbol, tint: .orange) {
                    NotchAgentPulse(tint: .orange, size: 5)
                }
                if sessions.waiting.isEmpty {
                    Text(text.nobodyWaits).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(sessions.waiting.prefix(3)) { row($0, text: text) }
                    }
                }
            }
        }
    }

    private func row(_ session: ForkClaudeSessionsLogic.Session, text: ForkAgentCardsStrings) -> some View {
        Button { sessions.goTo(session) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(text.reason(ForkClaudeSessionsLogic.wait(session.waitingFor)))
                        .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(text.goThere)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.85)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help([session.name, ForkClaudeSessionsLogic.projectName(session.cwd)].joined(separator: " · "))
    }
}

private struct ForkAgentTimeCard: View {
    let period: AgentPeriod
    let snapshot: AgentUsageSnapshot
    @ObservedObject private var time = ForkAgentTime.shared

    var body: some View {
        let text = ForkAgentCardsStrings.current
        let shown = Array((time.periods[period] ?? []).prefix(3))
        let peak = max(shown.map(\.seconds).max() ?? 0, 1)
        let costs = Dictionary(snapshot.usage(period).projects.map { ($0.name, $0.totals.cost) }, uniquingKeysWith: +)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.title(.forkTime), symbol: ForkAgentCardsLogic.symbol(.forkTime)) {
                    EmptyView()
                }
                if shown.isEmpty {
                    Text(text.noTime).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(shown) { entry in
                            Button { ForkClaudeSessions.shared.openProject(named: entry.project) } label: { HStack(spacing: 6) {
                                Text(entry.project)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Capsule(style: .continuous)
                                    .fill(AgentProvider.claude.tint.opacity(0.85))
                                    .frame(width: max(3, 36 * entry.seconds / peak), height: 4)
                                    .frame(width: 36, alignment: .leading)
                                Text(ForkClaudeSessionsLogic.duration(entry.seconds))
                                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                            .frame(height: 14)
                            .contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .help([entry.project, ForkClaudeSessionsLogic.duration(entry.seconds),
                                   costs[entry.project].map { AgentFormat.cost($0) }].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                }
            }
        }
    }
}

private struct ForkAgentResumeCard: View {
    @ObservedObject private var sessions = ForkClaudeSessions.shared
    /// The row under the pointer shows its buttons in place of its time, so
    /// a name has the row's width the rest of the time.
    @State private var hovered: String?

    var body: some View {
        let text = ForkAgentCardsStrings.current
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.title(.forkResume), symbol: ForkAgentCardsLogic.symbol(.forkResume)) {
                    EmptyView()
                }
                if sessions.recent.isEmpty {
                    Text(text.noProject).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(sessions.recent) { row($0, text: text) }
                    }
                }
            }
        }
    }

    private func row(_ project: ForkClaudeSessionsLogic.Project, text: ForkAgentCardsStrings) -> some View {
        let open = ForkClaudeSessionsLogic.openSession(for: project.path, in: sessions.running)
        let tools = hovered == project.id
        return HStack(spacing: 6) {
            Button { sessions.resume(project) } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(open == nil ? Color.clear : Color.green)
                        .frame(width: 5, height: 5)
                    Text(project.name).font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.8).truncationMode(.middle)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    if !tools {
                        Text(ForkClaudeSessionsLogic.ago(Date().timeIntervalSince(project.lastActivity), french: text.french))
                            .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(project.name) · \(project.path)")
            if tools {
                icon("plus", help: text.newSession, label: "\(text.newSession) \(project.name)") { sessions.newSession(project) }
                icon("folder", help: text.showInFinder, label: "\(text.showInFinder) \(project.name)") { sessions.reveal(project) }
            }
        }
        .frame(height: 14)
        .onHover { inside in hovered = inside ? project.id : (hovered == project.id ? nil : hovered) }
        .accessibilityAction(named: text.newSession) { sessions.newSession(project) }
        .accessibilityAction(named: text.showInFinder) { sessions.reveal(project) }
    }

    private func icon(_ symbol: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .help(help)
        .accessibilityLabel(label)
    }
}

/// The waiting notice's switch, with the AI page's other alerts.
struct ForkAgentWaitingAlertRow: View {
    @AppStorage(DefaultsKey.forkAgentsWaitingAlert) private var on = true

    var body: some View {
        let text = ForkAgentCardsStrings.current
        ForkOptionRow(symbol: ForkClaudeSessionsLogic.noticeSymbol, title: text.alertTitle, caption: text.alertCaption) {
            Toggle(text.alertTitle, isOn: $on).labelsHidden().toggleStyle(.switch)
        }
    }
}
