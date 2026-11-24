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

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: flag) else { return }
        let path = index + 1 < arguments.count ? arguments[index + 1]
            : NSTemporaryDirectory() + "bluetooth-battery-probe.txt"
        let probe = Probe()
        probe.start()
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        try? probe.report.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        exit(0)
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
