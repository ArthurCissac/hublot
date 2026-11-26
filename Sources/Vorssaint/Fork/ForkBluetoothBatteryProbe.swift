// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreBluetooth
import Foundation

#if VORSSAINT_DEVELOPMENT
/// A probe for lot 8, Developer builds only: what does a connected iPad or
/// iPhone tell over Bluetooth LE about its battery? It lists, for each
/// device offering the battery service (0x180F), every characteristic of
/// that service with its properties and value, then quits. Nothing else of
/// the app starts.
///
///     open -n "Hublot (Developer).app" --args --probe-bluetooth-battery /path/out.txt
enum ForkBluetoothBatteryProbe {
    static let flag = "--probe-bluetooth-battery"

    static let scanFlag = "--probe-bluetooth-scan"

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        if let index = arguments.firstIndex(of: scanFlag) {
            let path = index + 1 < arguments.count ? arguments[index + 1]
                : NSTemporaryDirectory() + "bluetooth-scan-probe.txt"
            let probe = ScanProbe()
            probe.start()
            RunLoop.main.run(until: Date().addingTimeInterval(24))
            probe.finish()
            try? probe.report.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            exit(0)
        }
        guard let index = arguments.firstIndex(of: flag) else { return }
        let path = index + 1 < arguments.count ? arguments[index + 1]
            : NSTemporaryDirectory() + "bluetooth-battery-probe.txt"
        let probe = Probe()
        probe.start()
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        try? probe.report.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Can Hublot find the iPhone and the iPad itself, as Juicy does, when
    /// nothing else has connected them? Scans 10 s, lists Apple devices
    /// (manufacturer 0x004C) by name, then connects to those named iPhone or
    /// iPad and reads their battery level. Also tries the identifiers of the
    /// previous run, read from `<path>.ids`, to see whether they stay stable.
    private final class ScanProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        private static let batteryService = CBUUID(string: "180F")
        private static let batteryLevel = CBUUID(string: "2A19")
        private var central: CBCentralManager?
        private var seen: [UUID: CBPeripheral] = [:]
        private var connecting: [UUID: CBPeripheral] = [:]
        var report: [String] = []
        private let started = Date()

        private var stamp: String {
            String(format: "%5.1fs", locale: Locale(identifier: "en_US_POSIX"), Date().timeIntervalSince(started))
        }

        func start() {
            report.append("Bluetooth scan probe, \(ProcessInfo.processInfo.operatingSystemVersionString)")
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }

        func finish() {
            central?.stopScan()
            for peripheral in connecting.values { central?.cancelPeripheralConnection(peripheral) }
            report.append("identifiers: " + connecting.keys.map(\.uuidString).joined(separator: " "))
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            report.append("\(stamp) state \(central.state.rawValue) authorization \(CBManager.authorization.rawValue)")
            guard central.state == .poweredOn else { return }
            let previous = (CommandLine.arguments.last.flatMap { try? String(contentsOfFile: $0 + ".ids", encoding: .utf8) } ?? "")
                .split(whereSeparator: \.isWhitespace).compactMap { UUID(uuidString: String($0)) }
            let retrieved = central.retrievePeripherals(withIdentifiers: previous)
            report.append("\(stamp) previous identifiers \(previous.count), retrieved \(retrieved.count): "
                          + retrieved.map { "\($0.name ?? "?") state \($0.state.rawValue)" }.joined(separator: ", "))
            for peripheral in retrieved { connect(peripheral, reason: "by identifier") }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                central.stopScan()
                self.report.append("\(self.stamp) scan stopped, \(self.seen.count) Apple devices seen")
            }
        }

        func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                            advertisementData: [String: Any], rssi RSSI: NSNumber) {
            guard let maker = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                  maker.count >= 3, maker[maker.startIndex] == 0x4C, maker[maker.startIndex + 1] == 0x00,
                  seen[peripheral.identifier] == nil else { return }
            seen[peripheral.identifier] = peripheral
            let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let type = String(format: "%02x", maker[maker.startIndex + 2])
            report.append("\(stamp) seen \(peripheral.identifier.uuidString.prefix(8)) name \(peripheral.name ?? "nil") local \(local ?? "nil") type \(type) rssi \(RSSI)")
            let name = (peripheral.name ?? local ?? "").lowercased()
            if name.contains("iphone") || name.contains("ipad") { connect(peripheral, reason: "by scan") }
        }

        private func connect(_ peripheral: CBPeripheral, reason: String) {
            guard connecting[peripheral.identifier] == nil else { return }
            connecting[peripheral.identifier] = peripheral
            peripheral.delegate = self
            report.append("\(stamp) connect \(peripheral.name ?? "?") \(reason)")
            central?.connect(peripheral)
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            report.append("\(stamp) connected \(peripheral.name ?? "?")")
            peripheral.discoverServices([Self.batteryService])
        }

        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            report.append("\(stamp) failed \(peripheral.name ?? "?") \(error?.localizedDescription ?? "")")
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
                report.append("\(stamp) \(peripheral.name ?? "?") no battery service \(error?.localizedDescription ?? "")")
                return
            }
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            guard let level = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
            peripheral.readValue(for: level)
            peripheral.setNotifyValue(true, for: level)
        }

        func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            let value = characteristic.value?.first.map { "\($0) %" } ?? "nil"
            report.append("\(stamp) battery \(peripheral.name ?? "?") \(value) \(error?.localizedDescription ?? "")")
        }

        func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            report.append("\(stamp) notify \(peripheral.name ?? "?") \(characteristic.isNotifying) \(error?.localizedDescription ?? "")")
        }
    }

    private final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        private static let batteryService = CBUUID(string: "180F")
        private var central: CBCentralManager?
        private var peripherals: [CBPeripheral] = []
        var report: [String] = []

        func start() {
            report.append("Bluetooth battery probe, \(ProcessInfo.processInfo.operatingSystemVersionString)")
            report.append("authorization: \(CBManager.authorization.rawValue) (3 = allowed)")
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            report.append("state: \(central.state.rawValue) (5 = on)")
            guard central.state == .poweredOn else { return }
            let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
            report.append("connected with a battery service: \(connected.count)")
            for peripheral in connected {
                peripherals.append(peripheral)
                peripheral.delegate = self
                report.append("- \(peripheral.name ?? "?")")
                central.connect(peripheral)
            }
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            // Every service, to see whether another one tells about charging.
            peripheral.discoverServices(nil)
        }

        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            report.append("  \(peripheral.name ?? "?"): connection failed")
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            let services = peripheral.services ?? []
            report.append("  \(peripheral.name ?? "?") services: " + services.map(\.uuid.uuidString).joined(separator: ", "))
            for service in services { peripheral.discoverCharacteristics(nil, for: service) }
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            for characteristic in service.characteristics ?? [] {
                report.append("    \(service.uuid.uuidString) / \(characteristic.uuid.uuidString) properties \(characteristic.properties.rawValue)")
                if characteristic.properties.contains(.read), service.uuid == Self.batteryService
                    || ["180A", "1805"].contains(service.uuid.uuidString) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }

        func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            let bytes = (characteristic.value ?? Data()).map { String(format: "%02x", $0) }.joined(separator: " ")
            report.append("    value \(characteristic.service?.uuid.uuidString ?? "?") / \(characteristic.uuid.uuidString): [\(bytes)]"
                          + (error.map { " error \($0.localizedDescription)" } ?? ""))
        }
    }
}
#endif
