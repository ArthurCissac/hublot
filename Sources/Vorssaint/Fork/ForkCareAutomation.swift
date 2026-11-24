// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import SwiftUI
import UserNotifications

/// Lot 9 in the background (see `ForkCareAutomationLogic`), each part with
/// its own switch: the antivirus's signatures checked once a day, new
/// downloads scanned as they land, and the one-click scan on a schedule.
/// Each waits for the charger or a battery above half, and none cleans or
/// removes anything: a scheduled scan only tells what it found, in a
/// notification the island shows; a click opens its results.
final class ForkCareAutomation {
    static let shared = ForkCareAutomation()
    typealias Logic = ForkCareAutomationLogic

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var signatureUpdater: ForkAntivirusModel?
    private var lastSignatureAttempt: Date?
    private var scheduledScan: ForkSmartScanModel?
    private var scanFinished = false
    private var scanWatch: AnyCancellable?
    private let downloads = ForkDownloadsGuard()
    private lazy var settingsChanged = ForkCoalescedMainAction { [weak self] in self?.downloads.sync() }

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                // The network needs a moment after waking.
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self?.tick() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.settingsChanged.schedule()
            })
        downloads.sync()
        // Not in the launch's rush.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.tick() }
    }

    private func tick() {
        updateSignaturesIfDue()
        runScheduledScanIfDue()
        downloads.sync()
    }

    private var powerAllows: Bool {
        guard let battery = SystemInfo.batterySnapshot() else { return true }
        return Logic.powerAllows(onBattery: battery.isOnBattery, percent: battery.percent)
    }

    // MARK: - Signatures

    private func updateSignaturesIfDue() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.forkAntivirusAutoUpdate), signatureUpdater == nil else { return }
        let model = ForkAntivirusModel()
        guard model.clamscan != nil, model.freshclam != nil,
              Logic.signaturesDue(lastCheck: model.freshness, lastAttempt: lastSignatureAttempt, now: Date()),
              powerAllows else { return }
        lastSignatureAttempt = Date()
        signatureUpdater = model
        model.update { [weak self] _ in self?.signatureUpdater = nil }
    }

    // MARK: - The scheduled scan

    struct Schedule {
        let frequency: Logic.Frequency
        let weekday: Int
        let hour: Int

        static var saved: Schedule {
            let defaults = UserDefaults.standard
            return Schedule(
                frequency: Logic.Frequency(rawValue: defaults.string(forKey: DefaultsKey.forkSmartScanSchedule) ?? "") ?? .off,
                weekday: min(7, max(1, defaults.integer(forKey: DefaultsKey.forkSmartScanWeekday))),
                hour: min(23, max(0, defaults.integer(forKey: DefaultsKey.forkSmartScanHour))))
        }
    }

    /// A changed schedule counts from now: no scan for a slot already gone.
    static func scheduleChanged() {
        UserDefaults.standard.set(Date(), forKey: DefaultsKey.forkSmartScanLastAuto)
    }

    private func runScheduledScanIfDue() {
        let schedule = Schedule.saved
        guard schedule.frequency != .off, scheduledScan == nil else { return }
        guard let lastRun = UserDefaults.standard.object(forKey: DefaultsKey.forkSmartScanLastAuto) as? Date else {
            Self.scheduleChanged()
            return
        }
        guard Logic.scanDue(now: Date(), lastRun: lastRun, frequency: schedule.frequency,
                            weekday: schedule.weekday, hour: schedule.hour),
              powerAllows, !ForkSmartScanWindow.shared.isOpen else { return }
        UserDefaults.standard.set(Date(), forKey: DefaultsKey.forkSmartScanLastAuto)
        Notifier.requestPermission()
        let model = ForkSmartScanModel()
        scheduledScan = model
        scanFinished = false
        scanWatch = model.$phase.receive(on: DispatchQueue.main).sink { [weak self, weak model] phase in
            guard let self, let model, phase == .results, !self.scanFinished else { return }
            self.scanFinished = true
            self.scanWatch = nil
            self.announce(model)
        }
        model.scan()
    }

    private func announce(_ model: ForkSmartScanModel) {
        let text = ForkCareAutomationStrings.current
        var parts: [String] = []
        if model.plan.cleanBytes > 0 {
            parts.append(text.toFree(ByteCountFormatter.string(fromByteCount: model.plan.cleanBytes, countStyle: .file)))
        }
        if !model.plan.jobs.isEmpty { parts.append(text.jobsDue(model.plan.jobs.count)) }
        switch model.protection {
        case .threats(let count): parts.append(text.threats(count))
        case .clean: parts.append(text.noThreat)
        case .notInstalled: break
        }
        let body = model.plan.hasWork || parts.contains(where: { $0 != text.noThreat }) ? parts.joined(separator: " · ") : text.allGood
        ForkNotifications.post(.smartScan, title: text.scanDone, body: body)
    }

    /// The scheduled scan for the window, under way or with its results;
    /// taken once. Opened while it scans, the window follows it and no
    /// notification comes.
    func takeScheduledScan() -> ForkSmartScanModel? {
        guard let model = scheduledScan else { return nil }
        scheduledScan = nil
        scanWatch = nil
        scanFinished = false
        return model
    }

    func openThreats() {
        ForkAntivirusWindow.shared.show(model: downloads.takeThreats())
    }
}

/// Watches the top of Downloads and scans each finished new item with
/// ClamAV, a few seconds after the folder goes quiet. Items already there
/// when watching starts are left to the antivirus's own scans.
final class ForkDownloadsGuard {
    typealias Logic = ForkCareAutomationLogic

    private var source: DispatchSourceFileSystemObject?
    private var seen = Set<String>()
    private var queued: [String] = []
    private var work: DispatchWorkItem?
    private var scanner: ForkAntivirusModel?
    private var waiting: AnyCancellable?
    private var withThreats: ForkAntivirusModel?

    private var folder: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true) }

    func sync() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.forkAntivirusWatchDownloads)
            && ForkAntivirusLogic.tool("clamscan", existing: { FileManager.default.isExecutableFile(atPath: $0) }) != nil
        if wanted, source == nil { begin() } else if !wanted, source != nil { end() }
    }

    private func names() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func begin() {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        seen = Set(names())
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .rename, .link], queue: .main)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        Notifier.requestPermission()
    }

    private func end() {
        source?.cancel()
        source = nil
        work?.cancel()
        work = nil
        scanner?.cancel()
        scanner = nil
        waiting = nil
        queued = []
    }

    private func changed() {
        work?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.check() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Logic.settleDelay, execute: item)
    }

    private func check() {
        let current = names()
        let fresh = Logic.newDownloads(current, seen: seen)
        seen = Set(current)
        guard !fresh.isEmpty else { return }
        queued += fresh.map { folder.appendingPathComponent($0).path }
        scanQueued()
    }

    private func scanQueued() {
        guard scanner == nil, !queued.isEmpty else { return }
        let targets = queued.filter { FileManager.default.fileExists(atPath: $0) }
        queued = []
        guard !targets.isEmpty else { return }
        let model = ForkAntivirusModel()
        scanner = model
        model.scan(targets)
        guard model.activity != .idle else {
            scanner = nil
            return
        }
        waiting = model.$showingSummary.receive(on: DispatchQueue.main).first(where: { $0 }).sink { [weak self] _ in
            self?.finished(model)
        }
    }

    private func finished(_ model: ForkAntivirusModel) {
        scanner = nil
        waiting = nil
        if let first = model.threats.first {
            withThreats = model
            let text = ForkCareAutomationStrings.current
            let name = (first.path as NSString).lastPathComponent
            let body = model.threats.count == 1 ? "\(name) · \(first.signature)" : text.threatsIn(model.threats.count, name)
            ForkNotifications.post(.threat, title: text.downloadThreat, body: body)
        }
        scanQueued()
    }

    /// The scan that found threats, so the antivirus window lists them.
    func takeThreats() -> ForkAntivirusModel? {
        defer { withThreats = nil }
        return withThreats
    }
}

/// The fork's own notifications, marked so a click on them, in the island or
/// in Notification Center, opens the right window.
enum ForkNotifications {
    static let kindKey = "agency.nexflow.hublot.fork.notification"

    enum Kind: String {
        case smartScan, threat
    }

    static func post(_ kind: Kind, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.userInfo = [kindKey: kind.rawValue]
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Called from upstream's notification delegate; false for a notification not the fork's.
    @discardableResult
    static func handle(_ response: UNNotificationResponse) -> Bool {
        guard let raw = response.notification.request.content.userInfo[kindKey] as? String,
              let kind = Kind(rawValue: raw) else { return false }
        DispatchQueue.main.async {
            switch kind {
            case .smartScan: ForkSmartScanWindow.shared.show()
            case .threat: ForkCareAutomation.shared.openThreats()
            }
        }
        return true
    }
}

// MARK: - Their switches, where each tool lives

/// Under the antivirus's welcome: the daily check and the downloads' watch.
struct ForkAntivirusAutomationOptions: View {
    @AppStorage(DefaultsKey.forkAntivirusAutoUpdate) private var autoUpdate = true
    @AppStorage(DefaultsKey.forkAntivirusWatchDownloads) private var watchDownloads = true

    var body: some View {
        let text = ForkCareAutomationStrings.current
        HStack(spacing: 18) {
            Toggle(text.dailyUpdate, isOn: $autoUpdate)
            Toggle(text.watchDownloads, isOn: $watchDownloads)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(size: 12))
        .foregroundStyle(Color.careSecondary)
        .fixedSize()
    }
}

/// Under the one-click scan's button: when it runs by itself, and a popover
/// to change that.
struct ForkSmartScanScheduleLink: View {
    @AppStorage(DefaultsKey.forkSmartScanSchedule) private var frequency = ForkCareAutomationLogic.Frequency.weekly.rawValue
    @AppStorage(DefaultsKey.forkSmartScanWeekday) private var weekday = ForkCareAutomationLogic.defaultWeekday
    @AppStorage(DefaultsKey.forkSmartScanHour) private var hour = ForkCareAutomationLogic.defaultHour
    @State private var editing = false

    private var schedule: ForkCareAutomationLogic.Frequency { .init(rawValue: frequency) ?? .off }

    var body: some View {
        let text = ForkCareAutomationStrings.current
        ForkCareLink(title: summary(text), symbol: "calendar.badge.clock") { editing = true }
            .popover(isPresented: $editing, arrowEdge: .bottom) { editor(text) }
            .frame(height: 28)
    }

    private func summary(_ text: ForkCareAutomationStrings) -> String {
        switch schedule {
        case .off: return text.scheduleOff
        case .daily: return text.everyDay(Self.hourText(hour))
        case .weekly: return text.everyWeek(Self.weekdayName(weekday), Self.hourText(hour))
        }
    }

    private func editor(_ text: ForkCareAutomationStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.scheduleTitle).font(.headline)
            Picker(text.frequency, selection: binding($frequency)) {
                Text(text.off).tag(ForkCareAutomationLogic.Frequency.off.rawValue)
                Text(text.weekly).tag(ForkCareAutomationLogic.Frequency.weekly.rawValue)
                Text(text.daily).tag(ForkCareAutomationLogic.Frequency.daily.rawValue)
            }
            if schedule == .weekly {
                Picker(text.day, selection: binding($weekday)) {
                    ForEach(Self.weekOrder, id: \.self) { day in Text(Self.weekdayName(day)).tag(day) }
                }
            }
            if schedule != .off {
                Picker(text.time, selection: binding($hour)) {
                    ForEach(0..<24, id: \.self) { value in Text(Self.hourText(value)).tag(value) }
                }
                Text(text.scheduleNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    /// Any change counts from now, so a slot already gone does not fire at once.
    private func binding<Value>(_ source: Binding<Value>) -> Binding<Value> {
        Binding(get: { source.wrappedValue }, set: {
            source.wrappedValue = $0
            ForkCareAutomation.scheduleChanged()
        })
    }

    /// The week as this Mac starts it.
    private static var weekOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private static func weekdayName(_ day: Int) -> String {
        let names = Calendar.current.standaloneWeekdaySymbols
        return names.indices.contains(day - 1) ? names[day - 1] : ""
    }

    private static func hourText(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
