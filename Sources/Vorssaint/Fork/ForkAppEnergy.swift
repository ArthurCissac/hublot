// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Darwin

/// Lot 8, Juicy's energy per app (`ForkAppEnergyLogic`). While the battery
/// item shows, the energy macOS counts for each of this user's processes is
/// read every minute (every 5 s while the panel is open, for the live view)
/// and added up per app. The hours and days are kept in a file of Hublot's
/// own in Application Support, on this Mac only. An app drawing a lot for
/// minutes on battery shows an alert pill. Stopping drops everything but the
/// file. Main thread only; processes are read off it.
final class ForkAppEnergy: ObservableObject {
    static let shared = ForkAppEnergy()
    typealias Logic = ForkAppEnergyLogic

    /// Watts per app at the last reading.
    @Published private(set) var live: [String: Double] = [:]
    @Published private(set) var store = Logic.Store()

    private var previous: [Int32: UInt64]?
    private var lastRead: Date?
    private var recent: [String: [Double]] = [:]
    private var lastAlert: [String: Date] = [:]
    private var slowTimer: Timer?
    private var fastTimer: Timer?
    private var active = false
    private var reading = false
    private var savedAt = Date.distantPast
    private let queue = DispatchQueue(label: "hublot.battery.energy", qos: .utility)
    private var icons: [String: NSImage] = [:]

    private init() {}

    func setActive(_ wanted: Bool) {
        guard wanted != active else { return }
        active = wanted
        if wanted {
            store = Self.load()
            read(slow: true)
            slowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.read(slow: true) }
            slowTimer?.tolerance = 10
        } else {
            slowTimer?.invalidate()
            slowTimer = nil
            setLive(false)
            save()
            previous = nil
            lastRead = nil
            live = [:]
            recent = [:]
        }
    }

    /// Faster readings while the panel shows the live view.
    func setLive(_ wanted: Bool) {
        fastTimer?.invalidate()
        fastTimer = nil
        guard wanted, active else { return }
        read(slow: false)
        fastTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.read(slow: false) }
        fastTimer?.tolerance = 1
    }

    func icon(for bundle: String) -> NSImage {
        if let icon = icons[bundle] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        icons[bundle] = icon
        return icon
    }

    // MARK: - Reading

    private func read(slow: Bool) {
        guard active, !reading else { return }
        reading = true
        queue.async { [weak self] in
            let processes = Self.processes()
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                self.ingest(processes, slow: slow)
            }
        }
    }

    private func ingest(_ processes: [Logic.Process], slow: Bool) {
        guard active else { return }
        let now = Date()
        let joules = Logic.joules(previous: previous, current: processes)
        let interval = lastRead.map { now.timeIntervalSince($0) } ?? 0
        previous = Dictionary(processes.map { ($0.pid, $0.energy) }, uniquingKeysWith: max)
        lastRead = now
        guard interval > 0.5 else { return }
        let watts = joules.mapValues { $0 / interval }
        live = watts
        store = Logic.adding(joules, at: now, to: store)
        if now.timeIntervalSince(savedAt) > 300 { save() }
        guard slow else { return }
        recent = Logic.remembering(watts, in: recent)
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.forkAppEnergyAlerts) else { return }
        let onBattery = ForkBatteryPanelModel.readMac().map { !$0.onPower } ?? false
        let drifting = Logic.drifting(recent: recent, threshold: defaults.double(forKey: DefaultsKey.forkAppEnergyThreshold),
                                      onBattery: onBattery, lastAlert: lastAlert, now: now)
        for bundle in drifting {
            lastAlert[bundle] = now
            ForkBatteryAlerts.shared.showAppDrift(name: Logic.name(bundle: bundle), watts: watts[bundle] ?? 0)
        }
    }

    /// This user's processes inside an app, with the energy each used so far.
    private static func processes() -> [Logic.Process] {
        let estimate = max(1, Int(proc_listallpids(nil, 0)))
        var pids = [pid_t](repeating: 0, count: estimate + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            Int(proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size)))
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var result: [Logic.Process] = []
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  let bundle = Logic.appBundle(executable: String(cString: path)) else { continue }
            var info = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard status == 0 else { continue }
            result.append(Logic.Process(pid: pid, bundle: bundle, energy: info.ri_energy_nj))
        }
        return result
    }

    // MARK: - The file

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Hublot", isDirectory: true)
            .appendingPathComponent("battery-app-energy.json")
    }

    private func save() {
        savedAt = Date()
        guard let file = Self.file, let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func load() -> Logic.Store {
        guard let file, let data = try? Data(contentsOf: file),
              let store = try? JSONDecoder().decode(Logic.Store.self, from: data) else { return Logic.Store() }
        return store
    }
}
