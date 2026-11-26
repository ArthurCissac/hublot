// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The AI page's Claude additions (ForkClaudeSessions): which Claude Code
/// session waits for an answer, how long was spent with an agent on each
/// project, and the projects to pick up again. Claude Code keeps one small
/// record per running session beside its logs (`sessions/<pid>.json`), with
/// its state; the logs themselves give each request's time and project.
enum ForkClaudeSessionsLogic {
    // MARK: - Sessions

    enum Status: String {
        case busy, shell, idle, waiting
    }

    /// Where a session runs, so going to it brings the right app forward.
    enum Host: Equatable {
        case claudeApp, terminal
    }

    struct Session: Equatable, Identifiable {
        let id: String
        let pid: Int32
        let name: String
        let cwd: String
        let status: Status
        let waitingFor: String?
        let host: Host
        let since: Date?
        /// The Claude app's own id for the session, which its links open.
        var appSession: String? = nil
    }

    /// One record, or nil when it is not a session's (or not finished being written).
    static func session(from data: Data) -> Session? {
        guard data.count < 1 << 16,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pid = json["pid"] as? Int, pid > 0, pid <= Int(Int32.max),
              let id = json["sessionId"] as? String, !id.isEmpty,
              let status = (json["status"] as? String).flatMap(Status.init(rawValue:)) else { return nil }
        let cwd = json["cwd"] as? String ?? ""
        let named = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let since = (json["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Session(id: id, pid: Int32(pid), name: named.isEmpty ? projectName(cwd) : named, cwd: cwd,
                       status: status, waitingFor: json["waitingFor"] as? String,
                       host: (json["entrypoint"] as? String) == "claude-desktop" ? .claudeApp : .terminal,
                       since: since, appSession: (json["hostSessionId"] as? String).flatMap(appSessionID))
    }

    /// The Claude app opens only ids of this shape.
    static func appSessionID(_ raw: String) -> String? {
        raw.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil ? raw : nil
    }

    // MARK: - The Claude app's links

    /// A session of the Claude app, opened where it is.
    static func continueURL(appSession: String) -> URL? {
        guard appSessionID(appSession) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: appSession)]
        return components.url
    }

    /// A new Claude Code session in a folder.
    static func newSessionURL(folder: String) -> URL? {
        guard folder.hasPrefix("/") else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/new"
        components.queryItems = [URLQueryItem(name: "folder", value: folder)]
        return components.url
    }

    /// The running session a project is worked on in: in its folder or one
    /// below it (a work tree), the one most recently active. Only the Claude
    /// app's sessions can be opened by a link.
    static func openSession(for project: String, in sessions: [Session]) -> Session? {
        let folder = project.hasSuffix("/") ? project : project + "/"
        return sessions.filter { $0.appSession != nil && ($0.cwd == project || $0.cwd.hasPrefix(folder)) }
            .max { ($0.since ?? .distantPast) < ($1.since ?? .distantPast) }
    }

    // MARK: - The Claude app's own sessions

    /// One of the Claude app's Code sessions as the app keeps it on disk
    /// (`claude-code-sessions/<account>/<org>/local_….json`), running or
    /// not: its id, its folder (and the project a work tree came from), when
    /// it was last active and whether it was archived.
    struct AppSession: Equatable {
        let id: String
        let cwd: String
        var origin: String? = nil
        let lastActivity: Date
        var archived = false
    }

    /// A session file is a few kilobytes to a few hundred; anything far
    /// larger is not one.
    static let maximumAppSessionSize = 8 << 20

    static func appSession(from data: Data) -> AppSession? {
        guard data.count <= maximumAppSessionSize,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = (json["sessionId"] as? String).flatMap(appSessionID),
              let cwd = json["cwd"] as? String, cwd.hasPrefix("/") else { return nil }
        let activity = (json["lastActivityAt"] as? Double) ?? (json["createdAt"] as? Double) ?? 0
        let origin = (json["originCwd"] as? String).flatMap { $0.hasPrefix("/") ? $0 : nil }
        return AppSession(id: id, cwd: cwd, origin: origin, lastActivity: Date(timeIntervalSince1970: activity / 1000),
                          archived: json["isArchived"] as? Bool ?? false)
    }

    /// The most recently active session not archived in a folder or one
    /// below it (a work tree), by its own folder or the one it came from.
    static func latestAppSession(forFolder path: String, in sessions: [AppSession]) -> AppSession? {
        let folder = path.hasSuffix("/") ? path : path + "/"
        return sessions.filter { session in
            !session.archived && [session.cwd, session.origin].compactMap { $0 }.contains { $0 == path || $0.hasPrefix(folder) }
        }
        .max { $0.lastActivity < $1.lastActivity }
    }

    /// The same for a project known by its folder's name, as the AI page names projects.
    static func latestAppSession(named name: String, in sessions: [AppSession]) -> AppSession? {
        guard !name.isEmpty else { return nil }
        return sessions.filter { session in
            !session.archived && [session.origin, session.cwd].compactMap { $0 }.contains { isProject($0) && projectName($0) == name }
        }
        .max { $0.lastActivity < $1.lastActivity }
    }

    /// The folder of a project known by its name, from the app's sessions.
    static func folder(named name: String, in sessions: [AppSession]) -> String? {
        latestAppSession(named: name, in: sessions).map { session in
            [session.origin, session.cwd].compactMap { $0 }.first { isProject($0) && projectName($0) == name } ?? session.cwd
        }
    }

    /// What a waiting session waits for, as far as its record says.
    enum Wait: Equatable {
        case question, plan, answer
    }

    static func wait(_ waitingFor: String?) -> Wait {
        let reason = waitingFor?.lowercased() ?? ""
        if reason.contains("input") { return .question }
        if reason.contains("plan") || reason.contains("goal") { return .plan }
        return .answer
    }

    /// The sessions waiting for the person, whose process still runs, longest waiting first.
    static func waiting(_ sessions: [Session], isRunning: (Int32) -> Bool) -> [Session] {
        sessions.filter { $0.status == .waiting && isRunning($0.pid) }
            .sorted { ($0.since ?? .distantFuture) < ($1.since ?? .distantFuture) }
    }

    /// A wait shorter than this is a prompt answered at once: no notice.
    static let noticeDelay: TimeInterval = 3

    /// The waiting sessions worth a notice now: waiting long enough, not
    /// announced since they started waiting.
    static func toAnnounce(_ waiting: [Session], announced: Set<String>, now: Date) -> [Session] {
        waiting.filter { session in
            !announced.contains(key(session)) && now.timeIntervalSince(session.since ?? now) >= noticeDelay
        }
    }

    /// A wait is announced once; the next one, after work resumed, is news again.
    static func key(_ session: Session) -> String {
        "\(session.id)|\(session.since?.timeIntervalSince1970 ?? 0)"
    }

    static let noticeSymbol = "hand.raised.fill"

    /// Set by ForkClaudeSessions once it runs, for upstream's island and
    /// usage service, which the tests compile without it.
    static var goToWaiting: () -> Void = {}
    static var takeRecords: (_ records: [AgentUsageRecord], _ now: Date) -> Void = { _, _ in }

    static func isNotice(symbol: String) -> Bool { symbol == noticeSymbol }

    /// The folder's name, as the AI page names projects.
    static func projectName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    // MARK: - Time on each project

    /// Two requests closer than this belong to one stretch of work; a longer
    /// gap is a pause and counts for nothing.
    static let pauseGap: TimeInterval = 10 * 60

    struct ProjectTime: Equatable, Identifiable {
        let project: String
        let seconds: TimeInterval
        var id: String { project }
    }

    /// The time covered by stretches of requests, gaps of a pause left out.
    static func activeTime(_ dates: [Date], gap: TimeInterval = pauseGap) -> TimeInterval {
        let sorted = dates.sorted()
        guard sorted.count > 1 else { return 0 }
        var total: TimeInterval = 0
        for index in 1..<sorted.count {
            let step = sorted[index].timeIntervalSince(sorted[index - 1])
            if step <= gap { total += step }
        }
        return total
    }

    /// Projects by time spent between `start` and `end`, most first; a
    /// project without a name is not one.
    static func projectTimes(_ requests: [(project: String, date: Date)], from start: Date, to end: Date,
                             gap: TimeInterval = pauseGap) -> [ProjectTime] {
        var dates: [String: [Date]] = [:]
        for request in requests where !request.project.isEmpty && request.date >= start && request.date <= end {
            dates[request.project, default: []].append(request.date)
        }
        return dates.map { ProjectTime(project: $0.key, seconds: activeTime($0.value, gap: gap)) }
            .filter { $0.seconds > 0 }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.project < $1.project }
    }

    /// The first moment of a period, as the AI page counts it: today from
    /// midnight, the week and the month as their last 7 and 30 days.
    static func start(of days: Int, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
    }

    /// How long ago, short: "now", "8 min", "2 h", "3 d" ("3 j" in French).
    static func ago(_ seconds: TimeInterval, french: Bool) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return french ? "à l’instant" : "now" }
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 24 * 60 { return "\(minutes / 60) h" }
        return "\(minutes / (24 * 60)) \(french ? "j" : "d")"
    }

    /// "2 h 05", "45 min", "< 1 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    // MARK: - Projects to pick up again

    struct Project: Equatable, Identifiable {
        let path: String
        let name: String
        let lastActivity: Date
        var id: String { path }
    }

    /// Places that are not projects: the Claude app's scratch spaces,
    /// temporary folders and work trees made for a single session.
    static func isProject(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/" else { return false }
        let excluded = ["/scratch-workspaces/", "/private/tmp/", "/private/var/folders/", "/.claude/worktrees/"]
        let folder = path.hasSuffix("/") ? path : path + "/"
        return !excluded.contains { folder.contains($0) } && !folder.hasPrefix("/tmp/") && !folder.hasPrefix("/var/folders/")
    }

    /// The latest projects, one entry per folder, most recent first.
    static func recentProjects(_ candidates: [(path: String, date: Date)], limit: Int = 3,
                               exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Project] {
        var latest: [String: Date] = [:]
        for candidate in candidates where isProject(candidate.path) {
            let path = candidate.path.count > 1 && candidate.path.hasSuffix("/") ? String(candidate.path.dropLast()) : candidate.path
            latest[path] = max(latest[path] ?? .distantPast, candidate.date)
        }
        return latest.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .filter { exists($0.key) }
            .prefix(limit)
            .map { Project(path: $0.key, name: projectName($0.key), lastActivity: $0.value) }
    }

    /// The working folder a Claude log names, read from its first lines.
    static func workingFolder(inLogHead head: String) -> String? {
        for line in head.split(separator: "\n").prefix(40) {
            guard let data = line.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let cwd = json["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }
}
