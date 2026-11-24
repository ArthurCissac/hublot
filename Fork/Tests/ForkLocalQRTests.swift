// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation
import Vision

/// The QR code that opens a local dev server on a phone: which address the
/// phone reaches, which rows show the button, and a code that reads back.
enum ForkLocalQRTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkLocalQRLogic

        suite.expect(Logic.reach(of: "*:3000") == .everywhere && Logic.reach(of: "[::]:3000") == .everywhere
            && Logic.reach(of: "0.0.0.0:8080") == .everywhere,
                     "a wildcard bind is reachable from the network")
        suite.expect(Logic.reach(of: "127.0.0.1:5173") == .loopback && Logic.reach(of: "[::1]:5173") == .loopback
            && Logic.reach(of: "localhost:3000") == .loopback && Logic.reach(of: "127.0.1.1:3000") == .loopback,
                     "a loopback bind answers this Mac only")
        suite.expect(Logic.reach(of: "192.168.1.20:3000") == .address("192.168.1.20"),
                     "a bind to one address keeps that address")

        suite.expect(Logic.address(fromReading: "192.168.1.10 (Wi-Fi)") == .init(ip: "192.168.1.10", connection: "Wi-Fi")
            && Logic.address(fromReading: "10.0.0.4") == .init(ip: "10.0.0.4", connection: nil),
                     "the network reader's lines give an address and its connection's name")
        suite.expect(Logic.isPrivate("192.168.0.2") && Logic.isPrivate("10.1.2.3") && Logic.isPrivate("172.20.0.1")
            && !Logic.isPrivate("172.40.0.1") && !Logic.isPrivate("8.8.8.8") && !Logic.isPrivate("nonsense"),
                     "private ranges are those of RFC 1918")
        let readings = ["169.254.3.4 (Thunderbolt Bridge)", "100.64.0.9", "10.0.0.7 (Ethernet)", "192.168.1.10 (Wi-Fi)"]
        suite.expect(Logic.preferred(readings.map(Logic.address(fromReading:)))?.ip == "192.168.1.10"
            && Logic.preferred([Logic.address(fromReading: "169.254.3.4")]) == nil,
                     "the phone gets the Wi-Fi's private address, never a self-assigned one")

        suite.expect(Logic.destination(port: 3000, endpoint: "*:3000", readings: readings)
            == .url(URL(string: "http://192.168.1.10:3000")!, connection: "Wi-Fi"),
                     "a wildcard server opens at the Wi-Fi address, on its own port")
        suite.expect(Logic.destination(port: 5173, endpoint: "127.0.0.1:5173", readings: readings) == .localOnly
            && Logic.destination(port: 3000, endpoint: "*:3000", readings: []) == .noNetwork,
                     "a loopback server or a Mac without network says why instead of a code")
        suite.expect(Logic.destination(port: 3000, endpoint: "10.0.0.7:3000", readings: readings)
            == .url(URL(string: "http://10.0.0.7:3000")!, connection: "Ethernet"),
                     "a server bound to one address opens there")

        suite.expect(Logic.showsButton(port: 3000, protocolName: "TCP", processName: "node")
            && Logic.showsButton(port: 5173, protocolName: "TCP", processName: "node")
            && Logic.showsButton(port: 8080, protocolName: "TCP", processName: "python3")
            && !Logic.showsButton(port: 5000, protocolName: "TCP", processName: "ControlCenter")
            && !Logic.showsButton(port: 3000, protocolName: "UDP", processName: "node")
            && !Logic.showsButton(port: 49152, protocolName: "TCP", processName: "Spotify"),
                     "the button shows on usual dev server ports, not on macOS's own listeners")

        let link = "http://192.168.1.10:3000"
        guard let image = Logic.image(for: link) else {
            suite.expect(false, "a QR code is drawn for a link")
            return
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let read = request.results?.compactMap(\.payloadStringValue).first
        suite.expect(read == link && image.width == image.height && Logic.image(for: "") == nil,
                     "the QR code is square and reads back as the same link")
    }
}
