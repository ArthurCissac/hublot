// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import CoreBluetooth

/// Lot 8: whether an iPhone's or an iPad's battery can be read over
/// Bluetooth, for the battery card (see `ForkBatteryLogic.bluetoothStatus`).
/// Reading `CBManager.authorization` never asks; `ask()` makes macOS ask,
/// once. While the card is shown and access is allowed, a central manager
/// watches the radio so the card can say Bluetooth is off; it connects to
/// nothing, and goes with the card. Main thread only.
final class ForkBluetoothAccess: NSObject, ObservableObject, CBCentralManagerDelegate {
    typealias Logic = ForkBatteryLogic

    @Published private(set) var status: Logic.BluetoothStatus = .ready
    private var central: CBCentralManager?

    /// When the card shows, and when the app comes back from System Settings.
    func start() {
        if Self.access == .allowed { watchRadio() }
        update()
    }

    func stop() {
        central?.delegate = nil
        central = nil
    }

    /// macOS shows its Bluetooth prompt the first time a central manager is
    /// made; the answer comes back as a change of state.
    func ask() {
        guard Self.access == .notAsked else { return }
        watchRadio()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        update()
    }

    private func watchRadio() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func update() {
        let radio: Logic.BluetoothRadio
        switch central?.state {
        case .poweredOn: radio = .on
        case .poweredOff: radio = .off
        default: radio = .unknown
        }
        status = Logic.bluetoothStatus(access: Self.access, radio: radio)
    }

    private static var access: Logic.BluetoothAccess {
        switch CBManager.authorization {
        case .allowedAlways: return .allowed
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .refused
        @unknown default: return .refused
        }
    }
}
