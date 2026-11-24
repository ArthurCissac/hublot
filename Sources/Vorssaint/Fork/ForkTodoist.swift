// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Carbon.HIToolbox
import Combine
import Security
import SwiftUI

/// Todoist in Hublot (see `ForkTodoistLogic`): today's and overdue tasks of
/// the user's own account, ticked or added from a panel that drops from the
/// island, a tile of the island and of the menu, or Control-Option-N.
/// Everything goes through Todoist, so the phone and every other device see
/// it at once. The personal token lives in the Keychain only; it is never
/// written to preferences nor to a log.

// MARK: - The token

enum ForkTodoistKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "agency.nexflow.hublot") + ".todoist" }
    private static let account = "token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - The service

final class ForkTodoist: ObservableObject {
    static let shared = ForkTodoist()
    typealias Logic = ForkTodoistLogic

    enum Problem: Equatable { case unauthorized, offline, failed }

    @Published private(set) var tasks: [Logic.Item] = [] { didSet { islandChanged() } }
    @Published private(set) var loading = false
    @Published private(set) var adding = false
    @Published private(set) var problem: Problem?
    @Published private(set) var hasToken = false { didSet { islandChanged() } }
    @Published private(set) var shortcutTaken = false
    @Published private(set) var projects: [Logic.Project] = []
    /// The tasks done in the last days.
    @Published private(set) var done: [Logic.Item] = []
    @Published private(set) var loadingDone = false
    @Published private(set) var saving = false
    /// The task just deleted, put back by « Undo » until Todoist is told.
    @Published private(set) var deleted: Logic.Item?
    /// The task being done, pinned first (this Mac only).
    @Published private(set) var activeID = UserDefaults.standard.string(forKey: DefaultsKey.forkTodoistActiveTask)
    private var deletion: DispatchWorkItem?

    private var lastFetch: Date?
    private var timer: Timer?
    private var lastReminderCheck: Date?
    private var recalled: Set<String> = []
    /// What the closed island last drew, so it is refreshed only on a change.
    private var islandShown: (shows: Bool, reading: String?, mark: String?, doing: Bool) = (false, nil, nil, false)
    private let hotkey = QuickToolHotkey(id: 9_104)
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.syncWithPreferences() }

    static let defaultShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_N), modifiers: [.control, .option])

    var enabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkTodoistEnabled) }

    func start() {
        Logic.islandActivityShown = { ForkTodoist.shared.showsIsland }
        Logic.islandStripWing = { Logic.stripWing(title: ForkTodoist.shared.islandReading, mark: ForkTodoist.shared.islandMark, in: $0) }
        Logic.islandReading = { ForkTodoist.shared.islandReading }
        hasToken = ForkTodoistKeychain.load() != nil
        hotkey.onPress = { ForkTodoistPanel.shared.toggle() }
        DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.resync.schedule()
            }
        }
        // Every 20 s, so a reminder comes within the minute and a task enters
        // or leaves the closed island on time; the list itself reloads every
        // five minutes (`refreshIfDue`).
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.refreshIfDue()
            self?.checkReminders()
            self?.islandChanged()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.refreshIfDue() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = enabled && defaults.bool(forKey: DefaultsKey.forkTodoistShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.forkTodoistShortcut, fallback: Self.defaultShortcut)
        let registered = hotkey.sync(enabled: wanted, shortcut: shortcut, storageKey: DefaultsKey.forkTodoistShortcut)
        if shortcutTaken != (wanted && !registered) { shortcutTaken = wanted && !registered }
        if !enabled {
            if !tasks.isEmpty { tasks = [] }
            ForkTodoistPanel.shared.close()
        }
        islandChanged()
    }

    // MARK: - In sight

    /// The task the closed island shows now: the one being done, or one with
    /// a time near it (`Logic.islandTask`); none otherwise, so it isn't there all day.
    var islandTask: Logic.Item? {
        let lead = Logic.islandLead(minutes: UserDefaults.standard.integer(forKey: DefaultsKey.forkTodoistIslandLead))
        return Logic.islandTask(tasks, active: activeID, now: Date(), lead: lead)
    }

    var showsIsland: Bool {
        Logic.showsIslandActivity(enabled: enabled, wanted: UserDefaults.standard.bool(forKey: DefaultsKey.forkTodoistIslandActivity),
                                  hasToken: hasToken, hasTask: islandTask != nil)
    }

    var islandReading: String? { Logic.islandReading(islandTask) }
    var islandMark: String? { Logic.islandMark(islandTask) }
    var islandDoing: Bool { islandTask.map { $0.id == activeID } ?? false }

    private func islandChanged() {
        let task = islandTask
        let now = (shows: showsIsland, reading: Logic.islandReading(task), mark: Logic.islandMark(task),
                   doing: task.map { $0.id == activeID } ?? false)
        guard now != islandShown else { return }
        islandShown = now
        // The task can change with the clock alone: the strip is told too.
        objectWillChange.send()
        guard NotchSupport.isEnabled() else { return }
        NotchService.shared.refreshPresentation()
    }

    /// A task whose time just came shows in the island, the companion
    /// startled; a click on it opens the tasks' page. Several at once show
    /// the earliest.
    private func checkReminders(now: Date = Date()) {
        defer { lastReminderCheck = now }
        guard enabled, hasToken, UserDefaults.standard.bool(forKey: DefaultsKey.forkTodoistReminders),
              NotchSupport.isEnabled() else { return }
        let due = Logic.reminders(tasks, last: lastReminderCheck, now: now, recalled: recalled)
        guard let first = due.first else { return }
        if recalled.count > 500 { recalled.removeAll() }
        recalled.formUnion(due.map(Logic.reminderKey))
        let text = ForkTodoistStrings.current
        _ = NotchService.shared.show(NotchNotice(event: .timer, title: Logic.plainTitle(first.content),
                                                 detail: text.reminderDetail(first.due?.time ?? ""),
                                                 symbol: Logic.reminderSymbol, mascot: .surprised))
    }

    func refreshIfDue() {
        guard enabled, hasToken, !loading, Logic.refreshDue(lastFetch: lastFetch, now: Date()) else { return }
        refresh()
    }

    func refresh() {
        guard enabled, !loading else { return }
        guard let token = ForkTodoistKeychain.load() else {
            hasToken = false
            return
        }
        loading = true
        fetch(token: token, cursor: nil, collected: [], pages: 0)
    }

    private func request(_ url: URL, token: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func fetch(token: String, cursor: String?, collected: [Logic.Item], pages: Int) {
        guard let url = Logic.filterURL(cursor: cursor) else { return finishFetch(nil, status: nil) }
        _ = ForkSpotifyHTTP.send(request(url, token: token), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            guard status == 200, let data, let page = Logic.page(from: data) else { return self.finishFetch(nil, status: status) }
            let all = collected + page.results
            if let next = page.nextCursor, !next.isEmpty, pages + 1 < Logic.maximumPages {
                self.fetch(token: token, cursor: next, collected: all, pages: pages + 1)
            } else {
                self.finishFetch(all, status: status)
            }
        }
    }

    private func finishFetch(_ items: [Logic.Item]?, status: Int?) {
        loading = false
        lastFetch = Date()
        if let items {
            // A task waiting to be deleted stays gone; the one being done is
            // forgotten once it leaves the list (done or moved elsewhere).
            let kept = items.filter { $0.id != deleted?.id }
            if let activeID, !kept.contains(where: { $0.id == activeID }) { setActive(nil) }
            tasks = Logic.sorted(kept, today: Logic.dayString(Date()), active: activeID)
            problem = nil
        } else {
            problem = Self.problem(for: status)
        }
    }

    private static func problem(for status: Int?) -> Problem {
        switch status {
        case 401, 403: return .unauthorized
        case nil: return .offline
        default: return .failed
        }
    }

    /// Todoist reads the date, the project (#) and the priority (p1) from the words.
    func add(_ text: String, done: @escaping (Bool) -> Void) {
        guard let token = ForkTodoistKeychain.load(), let body = Logic.quickAddBody(text) else { return done(false) }
        adding = true
        let request = request(Logic.quickAddURL, token: token, method: "POST", body: body)
        _ = ForkSpotifyHTTP.send(request, maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            let ok = (200...299).contains(status ?? 0)
            guard ok else {
                self.adding = false
                self.problem = Self.problem(for: status)
                return done(false)
            }
            self.problem = nil
            done(true)
            // Without a date it would not be in today's list: it gets today.
            if let task = Logic.addedTask(from: data), Logic.needsToday(task),
               let url = Logic.taskURL(task.id), let today = Logic.todayBody() {
                _ = ForkSpotifyHTTP.send(self.request(url, token: token, method: "POST", body: today),
                                         maximumBytes: Logic.maximumSize) { [weak self] _, _ in self?.added() }
            } else {
                self.added()
            }
        }
    }

    private func added() {
        adding = false
        lastFetch = nil
        refresh()
    }

    /// Ticked at once here; put back if Todoist refuses.
    func complete(_ item: Logic.Item) {
        guard let token = ForkTodoistKeychain.load(), let url = Logic.closeURL(item.id),
              let index = tasks.firstIndex(of: item) else { return }
        if activeID == item.id { setActive(nil) }
        tasks.remove(at: index)
        ForkMascotDay.shared.taskCompleted(remaining: tasks.filter { $0.checked != true }.count)
        _ = ForkSpotifyHTTP.send(request(url, token: token, method: "POST"), maximumBytes: 1 << 16) { [weak self] status, _ in
            guard let self else { return }
            if (200...299).contains(status ?? 0) { return }
            self.tasks.insert(item, at: min(index, self.tasks.count))
            self.problem = Self.problem(for: status)
        }
    }

    @discardableResult
    func setToken(_ raw: String) -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ForkTodoistLogic.isPlausibleToken(token), ForkTodoistKeychain.save(token) else { return false }
        hasToken = true
        problem = nil
        lastFetch = nil
        refresh()
        return true
    }

    func disconnect() {
        ForkTodoistKeychain.delete()
        hasToken = false
        tasks = []
        projects = []
        done = []
        problem = nil
    }

    // MARK: - Making, changing, deleting

    /// Pins `item` first as the task being done, or none.
    func setActive(_ item: Logic.Item?) {
        activeID = item?.id
        if let id = item?.id {
            UserDefaults.standard.set(id, forKey: DefaultsKey.forkTodoistActiveTask)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.forkTodoistActiveTask)
        }
        tasks = Logic.sorted(tasks, today: Logic.dayString(Date()), active: activeID)
    }

    func create(_ draft: Logic.Draft, done finished: @escaping (Bool) -> Void) {
        guard let token = ForkTodoistKeychain.load(), let body = Logic.createBody(draft) else { return finished(false) }
        send([(Logic.tasksURL, body)], token: token, finished: finished)
    }

    /// The task's own fields, then its project if it moved.
    func update(_ item: Logic.Item, to draft: Logic.Draft, done finished: @escaping (Bool) -> Void) {
        guard let token = ForkTodoistKeychain.load() else { return finished(false) }
        var steps: [(URL, Data)] = []
        if let body = Logic.updateBody(draft, from: item), let url = Logic.taskURL(item.id) { steps.append((url, body)) }
        if let body = Logic.moveBody(projectID: draft.projectID, from: item), let url = Logic.moveURL(item.id) { steps.append((url, body)) }
        guard !steps.isEmpty else { return finished(true) }
        send(steps, token: token, finished: finished)
    }

    /// Posts each step in turn, then reloads the list.
    private func send(_ steps: [(URL, Data)], token: String, finished: @escaping (Bool) -> Void) {
        guard let (url, body) = steps.first else {
            saving = false
            problem = nil
            lastFetch = nil
            refresh()
            return finished(true)
        }
        saving = true
        _ = ForkSpotifyHTTP.send(request(url, token: token, method: "POST", body: body),
                                 maximumBytes: Logic.maximumSize) { [weak self] status, _ in
            guard let self else { return }
            guard (200...299).contains(status ?? 0) else {
                self.saving = false
                self.problem = Self.problem(for: status)
                return finished(false)
            }
            self.send(Array(steps.dropFirst()), token: token, finished: finished)
        }
    }

    /// Gone from the list at once; Todoist is told after `undoDelay`, unless undone.
    func delete(_ item: Logic.Item) {
        commitDeletion()
        guard let index = tasks.firstIndex(of: item) else { return }
        if activeID == item.id { setActive(nil) }
        tasks.remove(at: index)
        deleted = item
        let work = DispatchWorkItem { [weak self] in self?.commitDeletion() }
        deletion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Logic.undoDelay, execute: work)
    }

    func undoDelete() {
        deletion?.cancel()
        deletion = nil
        guard let item = deleted else { return }
        deleted = nil
        tasks = Logic.sorted(tasks + [item], today: Logic.dayString(Date()), active: activeID)
    }

    private func commitDeletion() {
        deletion?.cancel()
        deletion = nil
        guard let item = deleted else { return }
        deleted = nil
        guard let token = ForkTodoistKeychain.load(), let url = Logic.taskURL(item.id) else { return }
        _ = ForkSpotifyHTTP.send(request(url, token: token, method: "DELETE"), maximumBytes: 1 << 16) { [weak self] status, _ in
            guard let self, !(200...299).contains(status ?? 0) else { return }
            self.problem = Self.problem(for: status)
            self.lastFetch = nil
            self.refresh()
        }
    }

    // MARK: - Done tasks and projects

    func loadDone() {
        guard enabled, !loadingDone, let token = ForkTodoistKeychain.load() else { return }
        loadingDone = true
        fetchDone(token: token, cursor: nil, collected: [], pages: 0)
    }

    private func fetchDone(token: String, cursor: String?, collected: [Logic.Item], pages: Int) {
        guard let url = Logic.completedURL(now: Date(), cursor: cursor) else { return finishDone(nil, status: nil) }
        _ = ForkSpotifyHTTP.send(request(url, token: token), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            guard status == 200, let data, let page = Logic.completed(from: data) else { return self.finishDone(nil, status: status) }
            let all = collected + page.items
            if let next = page.nextCursor, !next.isEmpty, pages + 1 < Logic.maximumPages {
                self.fetchDone(token: token, cursor: next, collected: all, pages: pages + 1)
            } else {
                self.finishDone(all, status: status)
            }
        }
    }

    private func finishDone(_ items: [Logic.Item]?, status: Int?) {
        loadingDone = false
        if let items { done = items } else { problem = Self.problem(for: status) }
    }

    /// Back to the tasks to do.
    func reopen(_ item: Logic.Item) {
        guard let token = ForkTodoistKeychain.load(), let url = Logic.reopenURL(item.id) else { return }
        done.removeAll { $0.id == item.id }
        _ = ForkSpotifyHTTP.send(request(url, token: token, method: "POST"), maximumBytes: 1 << 16) { [weak self] status, _ in
            guard let self else { return }
            if (200...299).contains(status ?? 0) {
                self.lastFetch = nil
                self.refresh()
            } else {
                self.problem = Self.problem(for: status)
                self.loadDone()
            }
        }
    }

    func loadProjects() {
        guard enabled, projects.isEmpty, let token = ForkTodoistKeychain.load() else { return }
        fetchProjects(token: token, cursor: nil, collected: [], pages: 0)
    }

    private func fetchProjects(token: String, cursor: String?, collected: [Logic.Project], pages: Int) {
        guard let url = Logic.projectsURL(cursor: cursor) else { return }
        _ = ForkSpotifyHTTP.send(request(url, token: token), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self, status == 200, let data, let page = Logic.projects(from: data) else { return }
            let all = collected + page.results
            if let next = page.nextCursor, !next.isEmpty, pages + 1 < Logic.maximumPages {
                self.fetchProjects(token: token, cursor: next, collected: all, pages: pages + 1)
            } else {
                // The inbox first, then Todoist's own order.
                self.projects = all.filter(\.isInbox) + all.filter { !$0.isInbox }
            }
        }
    }

    func open(_ item: Logic.Item) {
        if let app = Logic.appURL(item.id), NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
            NSWorkspace.shared.open(app)
        } else if let web = Logic.webURL(item.id) {
            NSWorkspace.shared.open(web)
        }
    }
}

// MARK: - The panel

/// Drops just under the menu bar, in the middle of the screen the pointer
/// is on, as from the island; takes the keyboard for its field without
/// bringing the app forward. Esc or a click elsewhere closes it.
final class ForkTodoistPanel {
    static let shared = ForkTodoistPanel()
    static let size = CGSize(width: 360, height: 470)
    private var panel: NSPanel?
    private var monitors: [Any] = []

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    /// The island's own page when the island shows it; this panel otherwise.
    static var islandHostsPage: Bool {
        NotchSupport.isEnabled() && NotchSupport.modules().contains(.tasks)
    }

    func show() {
        guard ForkTodoist.shared.enabled else { return }
        if Self.islandHostsPage {
            close()
            NotchService.shared.open(.tasks)
            return
        }
        close()
        ForkTodoist.shared.refresh()
        let host = NSHostingView(rootView: ForkTodoistPanelView(model: .shared) { [weak self] in self?.close() })
        host.sizingOptions = []
        let panel = ForkTodoistKeyPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(CGRect(x: visible.midX - Self.size.width / 2, y: visible.maxY - Self.size.height - 8,
                              width: Self.size.width, height: Self.size.height), display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        install(for: panel)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
    }

    private func install(for panel: NSPanel) {
        if let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.window === panel, Int(event.keyCode) == kVK_Escape else { return event }
            self?.close()
            return nil
        }) { monitors.append(key) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
    }
}

final class ForkTodoistKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct ForkTodoistPanelView: View {
    @ObservedObject var model: ForkTodoist
    let close: () -> Void
    @State private var token = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = ForkTodoistStrings.current
        VStack(alignment: .leading, spacing: 12) {
            header(text)
            if model.hasToken {
                ForkTodoistBoard(focusOnAppear: true) { item in
                    close()
                    model.open(item)
                }
            } else {
                setup(text)
            }
        }
        .padding(16)
        .frame(width: ForkTodoistPanel.size.width, height: ForkTodoistPanel.size.height, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func header(_ text: ForkTodoistStrings) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ForkTodoistLogic.islandSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(text.today).font(.system(size: 15, weight: .semibold))
            if model.hasToken {
                Text(verbatim: "\(model.tasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if model.hasToken {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(model.loading && !reduceMotion ? 360 : 0))
                        .animation(model.loading && !reduceMotion
                                   ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.loading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(text.refresh)
            }
            Button {
                close()
                if let url = URL(string: "todoist://") { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(text.openApp)
        }
    }

    static func colour(_ level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .blue
        default: return .secondary
        }
    }

    private func setup(_ text: ForkTodoistStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.setupTitle).font(.system(size: 13, weight: .semibold))
            Text(text.setupDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(text.getToken) { NSWorkspace.shared.open(ForkTodoistLogic.tokenPage) }
            HStack(spacing: 8) {
                SecureField(text.token, text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveToken)
                Button(text.save, action: saveToken)
                    .disabled(!ForkTodoistLogic.isPlausibleToken(token.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            Spacer()
        }
    }

    private func saveToken() {
        if model.setToken(token) { token = "" }
    }
}

// MARK: - The island's tile

/// Among the island's controls: the list, its count of today's tasks on it.
struct ForkTodoistIslandTile: View {
    let service: NotchService
    @ObservedObject private var todoist = ForkTodoist.shared

    var body: some View {
        let text = ForkTodoistStrings.current
        let count = todoist.tasks.count
        Button { service.select(.tasks) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle().fill(Color.white.opacity(0.075))
                        .overlay(Image(systemName: ForkTodoistLogic.islandSymbol)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85)))
                        .frame(width: 40, height: 40)
                    if count > 0 {
                        Text(verbatim: "\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 6, y: -4)
                    }
                }
                Text(text.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.shortcutHeight)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .accessibilityLabel(text.title)
        .accessibilityValue(text.countLabel(count))
        .onAppear { todoist.refreshIfDue() }
    }
}

// MARK: - Settings

/// On the island's settings page: the switch, the account and the shortcut.
struct ForkTodoistSettingsSection: View {
    @AppStorage(DefaultsKey.forkTodoistEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkTodoistShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.forkTodoistShortcut) private var shortcutRaw = ""
    @AppStorage(DefaultsKey.forkTodoistIslandActivity) private var islandActivity = true
    @AppStorage(DefaultsKey.forkTodoistIslandLead) private var islandLead = ForkTodoistLogic.defaultIslandLead
    @AppStorage(DefaultsKey.forkTodoistReminders) private var reminders = true
    @ObservedObject private var todoist = ForkTodoist.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var token = ""
    @State private var shortcutError: String?

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: shortcutRaw) ?? ForkTodoist.defaultShortcut
    }

    var body: some View {
        let text = ForkTodoistStrings.current
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.headline)
            ForkOptionRow(symbol: ForkTodoistLogic.islandSymbol, title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                if todoist.hasToken {
                    ForkOptionRow(symbol: "person.crop.circle", title: text.account,
                                  caption: todoist.problem == .unauthorized ? text.problem(.unauthorized) : text.connected) {
                        Button(text.disconnect) { todoist.disconnect() }
                    }
                } else {
                    ForkOptionRow(symbol: "key", title: text.token, caption: text.setupDetail) {
                        HStack(spacing: 6) {
                            SecureField(text.token, text: $token).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 200)
                            Button(text.save) { if todoist.setToken(token) { token = "" } }
                                .disabled(!ForkTodoistLogic.isPlausibleToken(token.trimmingCharacters(in: .whitespacesAndNewlines)))
                            Button(text.getToken) { NSWorkspace.shared.open(ForkTodoistLogic.tokenPage) }
                        }
                    }
                }
                ForkOptionRow(symbol: "rectangle.topthird.inset.filled", title: text.islandActivity,
                              caption: text.islandActivityCaption) {
                    Toggle(text.islandActivity, isOn: $islandActivity).labelsHidden().toggleStyle(.switch)
                }
                if islandActivity {
                    ForkOptionRow(symbol: "clock", title: text.islandLead, caption: text.islandLeadCaption) {
                        Picker(text.islandLead, selection: $islandLead) {
                            ForEach(ForkTodoistLogic.islandLeadChoices, id: \.self) { Text(text.minutes($0)).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
                ForkOptionRow(symbol: "bell", title: text.reminders, caption: text.remindersCaption) {
                    Toggle(text.reminders, isOn: $reminders).labelsHidden().toggleStyle(.switch)
                }
                ForkOptionRow(symbol: "keyboard", title: text.shortcut,
                              caption: todoist.shortcutTaken ? text.shortcutTaken : shortcutError) {
                    HStack(spacing: 8) {
                        ShortcutRecorderButton(shortcut: shortcut,
                                               isEnabled: shortcutEnabled,
                                               waitingTitle: l10n.s.shortcutPressKeys,
                                               invalidAction: { shortcutError = l10n.s.shortcutInvalid },
                                               captureAction: { captured in
                                                   shortcutRaw = captured.storageValue
                                                   shortcutError = nil
                                               })
                            .frame(width: 150, height: 24)
                        Toggle(text.shortcut, isOn: $shortcutEnabled).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - The island's page

/// Todoist's own page in the island: the field to add, then today's and
/// overdue tasks with their round to tick, in the island's dark look.
struct ForkTodoistIslandPage: View {
    let size: CGSize
    @ObservedObject private var model = ForkTodoist.shared
    @State private var token = ""

    var body: some View {
        let text = ForkTodoistStrings.current
        VStack(alignment: .leading, spacing: 8) {
            if model.hasToken {
                ForkTodoistBoard(compact: true) { model.open($0) }
            } else {
                setup(text)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear { model.refresh() }
    }

    private func setup(_ text: ForkTodoistStrings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.setupTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Text(text.setupDetail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("", text: $token, prompt: Text(text.token).foregroundStyle(.white.opacity(0.45)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .onSubmit { if model.setToken(token) { token = "" } }
                NotchPillButton(title: text.save, prominent: true) { if model.setToken(token) { token = "" } }
                NotchPillButton(title: text.getToken) { NSWorkspace.shared.open(ForkTodoistLogic.tokenPage) }
            }
        }
    }
}
