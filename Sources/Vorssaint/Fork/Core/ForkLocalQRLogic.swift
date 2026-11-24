// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreImage
import Foundation

/// Opening a local dev server on a phone: the address the phone can reach,
/// and the QR code that carries it. The phone and the Mac must share a
/// network; a server bound to the loopback only cannot be reached at all.
enum ForkLocalQRLogic {
    /// Where a listening socket accepts connections from, read from lsof's
    /// endpoint (`*:3000`, `127.0.0.1:5173`, `[::1]:8080`, `192.168.1.10:3000`).
    enum Reach: Equatable {
        case everywhere
        case loopback
        case address(String)
    }

    static func reach(of endpoint: String) -> Reach {
        guard let separator = endpoint.lastIndex(of: ":") else { return .loopback }
        var host = String(endpoint[..<separator])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        switch host {
        case "*", "0.0.0.0", "::": return .everywhere
        case "", "localhost", "::1": return .loopback
        default: return host.hasPrefix("127.") ? .loopback : .address(host)
        }
    }

    /// One of the Mac's IPv4 addresses, with the system's name for its
    /// connection when it has one ("Wi-Fi", "Ethernet").
    struct Address: Equatable {
        let ip: String
        let connection: String?
    }

    /// Reads `NetworkAddressService`'s lines: "192.168.1.10 (Wi-Fi)" or a bare address.
    static func address(fromReading reading: String) -> Address {
        let trimmed = reading.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.firstIndex(of: "(") else {
            return Address(ip: trimmed, connection: nil)
        }
        let ip = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let name = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        return Address(ip: ip, connection: name.isEmpty ? nil : String(name))
    }

    /// The ranges a home or office network hands out (RFC 1918).
    static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
    }

    /// The address a phone on the same network most likely reaches: a
    /// private one, Wi-Fi first, never a self-assigned 169.254 address.
    static func preferred(_ addresses: [Address]) -> Address? {
        let usable = addresses.filter { !$0.ip.hasPrefix("169.254.") && !$0.ip.isEmpty }
        func rank(_ address: Address) -> Int {
            (isPrivate(address.ip) ? 0 : 2) + (address.connection == "Wi-Fi" ? 0 : 1)
        }
        return usable.min { (rank($0), $0.ip) < (rank($1), $1.ip) }
    }

    enum Destination: Equatable {
        /// The address to open, and the connection the phone must share.
        case url(URL, connection: String?)
        /// The server answers this Mac only.
        case localOnly
        /// The Mac has no network address a phone could reach.
        case noNetwork
    }

    static func destination(port: Int, endpoint: String, readings: [String]) -> Destination {
        let addresses = readings.map(address(fromReading:))
        let host: String
        let connection: String?
        switch reach(of: endpoint) {
        case .loopback:
            return .localOnly
        case .address(let ip):
            host = ip.contains(":") ? "[\(ip)]" : ip
            connection = addresses.first { $0.ip == ip }?.connection
        case .everywhere:
            guard let chosen = preferred(addresses) else { return .noNetwork }
            host = chosen.ip
            connection = chosen.connection
        }
        guard (1...65535).contains(port), let url = URL(string: "http://\(host):\(port)") else { return .noNetwork }
        return .url(url, connection: connection)
    }

    /// The ports dev servers usually take: Next.js and friends on 3000,
    /// Astro on 4321, Vite on 5173, Django and others on 8000 or 8080,
    /// Parcel on 1234, Storybook on 6006.
    static let devPorts: [ClosedRange<Int>] = [1234...1234, 3000...5999, 6006...6006, 8000...8999]

    /// macOS's own listeners on those ports (AirPlay takes 5000 and 7000).
    static let systemProcesses: Set<String> = ["controlcenter", "rapportd", "launchd", "sharingd",
                                               "airplayxpchelper", "mdnsresponder", "remoted"]

    /// Whether a port's row shows the QR button; any TCP port keeps the
    /// context menu entry.
    static func showsButton(port: Int, protocolName: String, processName: String) -> Bool {
        protocolName == "TCP" && devPorts.contains { $0.contains(port) }
            && !systemProcesses.contains(processName.lowercased())
    }

    /// The QR code for `text`, black on white with the four-module quiet zone
    /// scanners expect, each module `moduleSize` pixels.
    static func image(for text: String, moduleSize: CGFloat = 10) -> CGImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        let scaled = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: moduleSize, y: moduleSize))
        let frame = scaled.extent.insetBy(dx: -4 * moduleSize, dy: -4 * moduleSize)
        let page = scaled.composited(over: CIImage(color: .white).cropped(to: frame))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(page, from: frame)
    }
}
