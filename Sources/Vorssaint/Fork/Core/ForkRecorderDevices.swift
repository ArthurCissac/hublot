// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation

/// The microphones this Mac has, for `ForkRecorderMicrophone` to choose from,
/// and the one a recording should open. Read by one line in upstream's
/// `RecorderCaptureEngine`, in place of the system's default input.
///
/// Not pure logic, yet kept in `Core`: the tests compile upstream's capture
/// engine whole, so what its one line calls has to be compiled with them too.
enum ForkRecorderDevices {
    /// What macOS reports for a device built into the Mac ('bltn').
    private static let builtInTransport: Int32 = 0x626C_746E

    static func microphones() -> [(device: AVCaptureDevice, info: ForkRecorderMicrophone.Device)] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                       mediaType: .audio, position: .unspecified)
        return session.devices.map { device in
            (device, ForkRecorderMicrophone.Device(id: device.uniqueID, name: device.localizedName,
                                                   isBuiltIn: device.transportType == builtInTransport))
        }
    }

    /// The microphone to record with: the one chosen in the recording bar,
    /// while it is plugged in; otherwise the Mac's own. Nil when macOS lists
    /// none, and upstream's own choice then applies.
    static func captureMicrophone(defaults: UserDefaults = .standard) -> AVCaptureDevice? {
        let all = microphones()
        let chosen = ForkRecorderMicrophone.selected(
            storedID: defaults.string(forKey: DefaultsKey.forkRecorderMicrophoneID) ?? "",
            among: all.map(\.info))
        return all.first { $0.info == chosen }?.device
    }
}
