// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreBluetooth
import Foundation
import os

/// Lot 8: Hublot's own Bluetooth link with this Mac's iPhones and iPads, the
/// way Juicy keeps one. macOS connects them only now and then (Continuity),
/// so waiting for it leaves their battery unread for hours.
///
/// A short search finds them once: only devices paired with this Mac and
/// named like an iPhone or an iPad are kept (a neighbour's phone shows no
/// name). They are then remembered by identifier, and a connection request
/// stays pending: macOS completes it as soon as the device comes in range.
/// Once connected they send their level whenever it changes (0x2A19
/// notifies), so nothing is polled. Runs only while the battery item asks;
/// stopping drops every link. Main thread only.
final class ForkBluetoothDevices: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = ForkBluetoothDevices()
    typealias Logic = ForkBatteryPanelLogic

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let deviceInformation = CBUUID(string: "180A")
    private static let modelNumber = CBUUID(string: "2A24")
    private static let searchDuration: TimeInterval = 12

    /// The iPhones and iPads Hublot knows, nearby or not.
    @Published private(set) var devices: [Logic.Device] = []
    @Published private(set) var isSearching = false

    private struct Record: Codable, Equatable {
        var name: String
        var model: String?
        var percent: Int?
        var lastSeen: Date?
        /// When the level last rose and fell, to tell a device charging.
        var lastRise: Date?
        var lastFall: Date?
    }

    /// By peripheral identifier, kept between launches: this Mac's own.
    private var records: [String: Record] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var central: CBCentralManager?
    private var pairedNames: [String] = []
    private var active = false
    private var searchEnd: DispatchWorkItem?
    /// What happened, for `log show --predicate 'category == "battery"'`.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hublot", category: "battery")

    private override init() {
        super.init()
        records = Self.loadRecords()
        publish()
    }

    /// On while the battery item shows, off when it goes. Refused Bluetooth
    /// starts nothing (the settings say so).
    func setActive(_ wanted: Bool) {
        let refused = CBManager.authorization == .denied || CBManager.authorization == .restricted
        let run = wanted && !refused
        guard run != active else { return }
        active = run
        if run { startCentral() } else { stopCentral() }
    }

    /// A short search for this Mac's iPhones and iPads, from the panel.
    func search() {
        guard active, let central, central.state == .poweredOn, !isSearching else { return }
        isSearching = true
        log.notice("searching for iPhones and iPads")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        let end = DispatchWorkItem { [weak self] in self?.stopSearch() }
        searchEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchDuration, execute: end)
    }

    // MARK: - Central

    private func startCentral() {
        loadPairedNames()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func stopCentral() {
        stopSearch()
        for peripheral in peripherals.values {
            peripheral.delegate = nil
            central?.cancelPeripheralConnection(peripheral)
        }
        peripherals.removeAll()
        central?.delegate = nil
        central = nil
        publish()
    }

    private func stopSearch() {
        searchEnd?.cancel()
        searchEnd = nil
        if isSearching { central?.stopScan() }
        isSearching = false
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central else { return }
        guard central.state == .poweredOn else {
            // Off or refused: the links are gone, the last levels stay greyed.
            stopSearch()
            peripherals.removeAll()
            publish()
            return
        }
        let known = records.keys.compactMap(UUID.init(uuidString:))
        central.retrievePeripherals(withIdentifiers: known).forEach(adopt)
        central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
            .filter { Logic.kind(model: nil, name: $0.name ?? "").isHeldByHublot }
            .forEach(adopt)
        if records.isEmpty || !unknownPaired.isEmpty { search() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripherals[peripheral.identifier] == nil,
              Logic.isOwnPhoneOrTablet(name: peripheral.name, pairedNames: pairedNames) else { return }
        log.notice("found a device of this Mac's")
        adopt(peripheral)
        if unknownPaired.isEmpty { stopSearch() }
    }

    /// Keeps a device and asks for its link. The request has no time limit:
    /// macOS completes it whenever the device is in range, again after each
    /// disconnection.
    private func adopt(_ peripheral: CBPeripheral) {
        guard let central, peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        let id = peripheral.identifier.uuidString
        var record = records[id] ?? Record(name: peripheral.name ?? "?", model: nil, percent: nil, lastSeen: nil)
        if let name = peripheral.name, !name.isEmpty { record.name = name }
        records[id] = record
        central.connect(peripheral)
        saveAndPublish()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService, Self.deviceInformation])
        publish()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        publish()
        reconnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Asked again a little later, rather than in a tight loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.reconnect(peripheral) }
    }

    private func reconnect(_ peripheral: CBPeripheral) {
        guard active, let central, central.state == .poweredOn, peripherals[peripheral.identifier] === peripheral else { return }
        central.connect(peripheral)
    }

    // MARK: - Peripheral

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            } else if service.uuid == Self.deviceInformation {
                peripheral.discoverCharacteristics([Self.modelNumber], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.batteryLevel {
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
            } else if characteristic.uuid == Self.modelNumber {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier.uuidString
        guard error == nil, let value = characteristic.value, records[id] != nil else { return }
        if characteristic.uuid == Self.batteryLevel, let percent = Logic.batteryLevel([UInt8](value)) {
            let now = Date()
            if let before = records[id]?.percent {
                if percent > before { records[id]?.lastRise = now }
                if percent < before { records[id]?.lastFall = now }
            }
            records[id]?.percent = percent
            records[id]?.lastSeen = now
        } else if characteristic.uuid == Self.modelNumber {
            let model = String(decoding: value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            if !model.isEmpty { records[id]?.model = model }
        } else {
            return
        }
        saveAndPublish()
    }

    // MARK: - Records

    private var unknownPaired: [String] {
        Logic.unknownPhonesOrTablets(pairedNames: pairedNames, known: records.values.map(\.name))
    }

    /// The devices paired with this Mac, read once per start, off the main thread.
    private func loadPairedNames() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = BoundedProcessRunner.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"],
                                                  timeout: 3, maxOutputBytes: 4 * 1024 * 1024)
            let names = result.status == 0 ? Logic.pairedNames(fromSystemProfilerJSON: result.output) : []
            DispatchQueue.main.async {
                guard let self else { return }
                self.pairedNames = names
                if self.active, self.central?.state == .poweredOn, !self.unknownPaired.isEmpty { self.search() }
            }
        }
    }

    private func publish() {
        let connected = Set(peripherals.values.filter { $0.state == .connected }.map(\.identifier.uuidString))
        let next = records.map { id, record in
            Logic.Device(id: id, name: record.name, kind: Logic.kind(model: record.model, name: record.name),
                         percent: record.percent, isNearby: connected.contains(id) && record.percent != nil,
                         lastSeen: record.lastSeen,
                         isCharging: Logic.isCharging(lastRise: record.lastRise, lastFall: record.lastFall, now: Date()))
        }
        if next != devices { devices = next }
    }

    private func saveAndPublish() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.forkBluetoothDeviceCache)
        }
        publish()
    }

    private static func loadRecords() -> [String: Record] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.forkBluetoothDeviceCache),
              let records = try? JSONDecoder().decode([String: Record].self, from: data) else { return [:] }
        return records
    }
}
