// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The island's Printer page (`forkBambuEnabled`): a Bambu Lab A1 (or P1)
/// reached directly on the local network, without its cloud nor Home
/// Assistant. Its camera sends JPEG pictures over TLS on port 6000 after an
/// 80-byte login; its state comes over MQTT (TLS, port 8883); both take the
/// user `bblp` and the printer's access code. The printer announces itself
/// on UDP port 2021. Pure: the login, the pictures cut out of the stream,
/// the MQTT packets, the announcements, the print state and its words.
enum ForkBambuLogic {
    static let cameraPort: UInt16 = 6000
    static let statusPort: UInt16 = 8883
    static let announcePort: UInt16 = 2021
    static let user = "bblp"

    // MARK: - The printer's address and code

    /// A printer is reached on the local network only: an IP address or a
    /// local name, nothing else (no scheme, path or port).
    static func host(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.count <= 253,
              host.range(of: #"^[A-Za-z0-9.\-:]+$"#, options: .regularExpression) != nil,
              ForkHomeLogic.isLocal(host: host) else { return nil }
        return host
    }

    /// The access code shown on the printer's screen: letters and digits.
    static func cleanCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...32).contains(code.count),
              code.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return code
    }

    // MARK: - The camera

    /// The camera's login: four little-endian words (0x40, 0x3000, 0, 0),
    /// then the user and the code, each in 32 bytes padded with zeros.
    static func cameraLogin(code: String) -> Data? {
        guard let code = cleanCode(code) else { return nil }
        var data = Data()
        for word: UInt32 in [0x40, 0x3000, 0, 0] {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        for text in [user, code] {
            let bytes = Array(text.utf8.prefix(32))
            data.append(contentsOf: bytes)
            data.append(contentsOf: [UInt8](repeating: 0, count: 32 - bytes.count))
        }
        return data
    }

    /// A picture is well under a megabyte; a header claiming more is a broken stream.
    static let maximumPicture = 4 << 20

    /// Cuts the camera's stream into pictures: each comes after a 16-byte
    /// header whose first four bytes give its size, little-endian.
    struct PictureReader {
        private(set) var buffer = Data()
        private(set) var broken = false

        mutating func feed(_ chunk: Data) -> [Data] {
            buffer.append(chunk)
            var pictures: [Data] = []
            while buffer.count >= 16 {
                let start = buffer.startIndex
                let size = Int(buffer[start]) | Int(buffer[start + 1]) << 8 | Int(buffer[start + 2]) << 16
                    | Int(buffer[start + 3]) << 24
                guard size > 0, size <= ForkBambuLogic.maximumPicture else {
                    broken = true
                    buffer.removeAll()
                    break
                }
                guard buffer.count >= 16 + size else { break }
                let picture = buffer.subdata(in: (start + 16)..<(start + 16 + size))
                buffer = buffer.subdata(in: (start + 16 + size)..<buffer.endIndex)
                if picture.starts(with: [0xFF, 0xD8]) { pictures.append(picture) }
            }
            return pictures
        }
    }

    // MARK: - MQTT

    /// MQTT's lengths: seven bits a byte, the high bit saying more follow.
    static func remainingLength(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value > 0 && bytes.count < 4
        return bytes
    }

    private static func string(_ text: String) -> [UInt8] {
        let bytes = Array(text.utf8.prefix(0xFFFF))
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }

    private static func packet(_ first: UInt8, _ body: [UInt8]) -> Data {
        Data([first] + remainingLength(body.count) + body)
    }

    static func connect(clientID: String, code: String, keepAlive: UInt16 = 30) -> Data? {
        guard let code = cleanCode(code) else { return nil }
        // Protocol MQTT 3.1.1, user name, password and a clean session.
        let header: [UInt8] = string("MQTT") + [4, 0xC2, UInt8(keepAlive >> 8), UInt8(keepAlive & 0xFF)]
        return packet(0x10, header + string(clientID) + string(user) + string(code))
    }

    static func subscribe(id: UInt16, topic: String) -> Data {
        packet(0x82, [UInt8(id >> 8), UInt8(id & 0xFF)] + string(topic) + [0])
    }

    static func publish(topic: String, payload: Data) -> Data {
        packet(0x30, string(topic) + Array(payload))
    }

    static let ping = Data([0xC0, 0x00])
    static let disconnect = Data([0xE0, 0x00])

    static func reportTopic(serial: String) -> String { "device/\(serial)/report" }
    static func requestTopic(serial: String) -> String { "device/\(serial)/request" }

    /// Asks the printer for its whole state (an A1 otherwise sends changes only).
    static func pushAll() -> Data {
        Data(#"{"pushing":{"command":"pushall","push_target":1,"sequence_id":"0","version":1}}"#.utf8)
    }

    static let anyReportTopic = "device/+/report"

    /// The serial a report's topic names (« device/<serial>/report »).
    static func serial(fromTopic topic: String) -> String? {
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "device", parts[2] == "report", isSerial(parts[1]) else { return nil }
        return parts[1]
    }

    static func isSerial(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9]{6,32}$"#, options: .regularExpression) != nil
    }

    enum Incoming: Equatable {
        case connected(accepted: Bool)
        case subscribed
        case message(topic: String, payload: Data)
        case pong
        case other
    }

    static let maximumPacket = 4 << 20

    /// Cuts MQTT's stream into packets.
    struct PacketReader {
        private(set) var buffer = Data()
        private(set) var broken = false

        mutating func feed(_ chunk: Data) -> [Incoming] {
            buffer.append(chunk)
            var packets: [Incoming] = []
            while let (packet, used) = next() {
                packets.append(packet)
                buffer = buffer.subdata(in: (buffer.startIndex + used)..<buffer.endIndex)
            }
            return packets
        }

        private mutating func next() -> (Incoming, Int)? {
            let bytes = [UInt8](buffer.prefix(5))
            guard bytes.count >= 2 else { return nil }
            var length = 0, multiplier = 1, index = 1
            while true {
                guard index < bytes.count else { return bytes.count == 5 ? fail() : nil }
                let byte = bytes[index]
                length += Int(byte & 0x7F) * multiplier
                index += 1
                if byte & 0x80 == 0 { break }
                multiplier *= 128
                if index > 4 { return fail() }
            }
            guard length <= ForkBambuLogic.maximumPacket else { return fail() }
            guard buffer.count >= index + length else { return nil }
            let start = buffer.startIndex
            let body = [UInt8](buffer[(start + index)..<(start + index + length)])
            return (ForkBambuLogic.decode(first: bytes[0], body: body), index + length)
        }

        private mutating func fail() -> (Incoming, Int)? {
            broken = true
            buffer.removeAll()
            return nil
        }
    }

    static func decode(first: UInt8, body: [UInt8]) -> Incoming {
        switch first >> 4 {
        case 2: return .connected(accepted: body.count >= 2 && body[1] == 0)
        case 9: return .subscribed
        case 13: return .pong
        case 3:
            guard body.count >= 2 else { return .other }
            let length = Int(body[0]) << 8 | Int(body[1])
            var offset = 2 + length
            guard body.count >= offset, let topic = String(bytes: body[2..<offset], encoding: .utf8) else { return .other }
            if (first >> 1) & 0x03 > 0 { offset += 2 }  // a packet id follows when QoS is above 0
            guard body.count >= offset else { return .other }
            return .message(topic: topic, payload: Data(body[offset...]))
        default: return .other
        }
    }

    // MARK: - The print state

    struct Status: Equatable {
        var state: String?
        var percent: Int?
        var remainingMinutes: Int?
        var layer: Int?
        var totalLayers: Int?
        var nozzle: Double?
        var nozzleTarget: Double?
        var bed: Double?
        var bedTarget: Double?
        var job: String?

        var printing: Bool { ["RUNNING", "PREPARE", "PAUSE"].contains(state ?? "") }
    }

    /// A report merged into what is known: the printer sends only what changed.
    static func merging(_ payload: Data, into status: Status) -> Status {
        guard payload.count <= maximumPacket,
              let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let print = json["print"] as? [String: Any] else { return status }
        var next = status
        func int(_ key: String) -> Int? { (print[key] as? NSNumber)?.intValue ?? (print[key] as? String).flatMap { Int($0) } }
        func double(_ key: String) -> Double? { (print[key] as? NSNumber)?.doubleValue }
        if let state = print["gcode_state"] as? String, !state.isEmpty { next.state = state.uppercased() }
        if let value = int("mc_percent") { next.percent = min(100, max(0, value)) }
        if let value = int("mc_remaining_time") { next.remainingMinutes = max(0, value) }
        if let value = int("layer_num") { next.layer = max(0, value) }
        if let value = int("total_layer_num") { next.totalLayers = max(0, value) }
        if let value = double("nozzle_temper") { next.nozzle = value }
        if let value = double("nozzle_target_temper") { next.nozzleTarget = value }
        if let value = double("bed_temper") { next.bed = value }
        if let value = double("bed_target_temper") { next.bedTarget = value }
        if let job = (print["subtask_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty {
            next.job = job
        }
        return next
    }

    static func stateText(_ status: Status, french: Bool) -> String {
        switch status.state ?? "" {
        case "IDLE": return french ? "Au repos" : "Idle"
        case "PREPARE": return french ? "Préparation" : "Preparing"
        case "RUNNING": return french ? "Impression" : "Printing"
        case "PAUSE": return french ? "En pause" : "Paused"
        case "FINISH": return french ? "Terminé" : "Finished"
        case "FAILED": return french ? "Échec" : "Failed"
        case "SLICING": return french ? "Découpage" : "Slicing"
        case "": return "—"
        default: return ForkHomeLogic.words(status.state?.lowercased() ?? "", french: french)
        }
    }

    /// « 1 h 10 », « 45 min ».
    static func remaining(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// « 220 °C », or « 180 → 220 °C » while heating up to its target.
    static func temperature(_ value: Double?, target: Double?) -> String? {
        guard let value else { return nil }
        let now = Int(value.rounded())
        if let target, target > 0, abs(target - value) >= 3 { return "\(now) → \(Int(target.rounded())) °C" }
        return "\(now) °C"
    }

    // MARK: - Finding the printer

    struct Printer: Equatable, Identifiable {
        let host: String
        let serial: String
        var name: String
        var model: String?
        var id: String { serial }
    }

    /// A printer's announcement (SSDP-like, on UDP port 2021).
    static func printer(fromAnnouncement text: String) -> Printer? {
        guard text.utf8.count <= 4096 else { return nil }
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard (headers["nt"] ?? "").lowercased().contains("bambulab"),
              let host = headers["location"].flatMap(host), let serial = headers["usn"], isSerial(serial) else { return nil }
        let name = headers["devname.bambu.com"].flatMap { $0.isEmpty ? nil : String($0.prefix(64)) } ?? serial
        return Printer(host: host, serial: serial, name: name, model: headers["devmodel.bambu.com"].map(modelName))
    }

    /// The model behind Bambu's codes.
    static func modelName(_ code: String) -> String {
        switch code.uppercased() {
        case "N2S": return "A1"
        case "N1": return "A1 mini"
        case "C11": return "P1P"
        case "C12": return "P1S"
        case "BL-P001", "3DPRINTER-X1-CARBON": return "X1 Carbon"
        case "BL-P002", "3DPRINTER-X1": return "X1"
        default: return code
        }
    }

    // MARK: - The certificate

    /// The printer signs its own certificates: Hublot remembers each port's
    /// the first time and refuses another after (`forkBambuPins`, « port:sha256 »).
    static func pins(_ stored: String?, port: UInt16) -> Set<String> {
        Set((stored ?? "").split(separator: ",").compactMap { entry -> String? in
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == String(port),
                  parts[1].range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
            return parts[1]
        })
    }

    static func adding(_ fingerprint: String, port: UInt16, to stored: String?) -> String {
        let entries = Set((stored ?? "").split(separator: ",").map(String.init)).union(["\(port):\(fingerprint)"])
        return entries.filter { !$0.isEmpty }.sorted().joined(separator: ",")
    }

    enum Trust: Equatable { case known, first, changed }

    static func trust(_ fingerprint: String, pins: Set<String>) -> Trust {
        if pins.contains(fingerprint) { return .known }
        return pins.isEmpty ? .first : .changed
    }

    // MARK: - The page

    static let statusHeight: CGFloat = 66
    static let pagePadding: CGFloat = 8

    /// The page's height: the camera in 16:9, its state below.
    static func pageHeight(width: CGFloat) -> CGFloat {
        min(330, (max(0, width - 12) * 9 / 16).rounded()) + statusHeight + pagePadding + 8
    }

    /// Set by ForkBambu once it runs, for upstream's island, which the tests
    /// compile without it: the page's height at a width, nil to fill the island.
    static var contentHeight: (_ width: CGFloat) -> CGFloat? = { _ in nil }

    static func title(french: Bool) -> String { french ? "Imprimante" : "Printer" }

    static let pageSymbol = "printer.fill"

    static func pageAvailable(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: DefaultsKey.forkBambuEnabled) }

    static func islandControlAvailable(in defaults: UserDefaults) -> Bool { pageAvailable(in: defaults) }

    static func pageSummary(french: Bool) -> String {
        french ? "Votre imprimante Bambu Lab en direct : caméra, progression, temps restant, couches, températures."
            : "Your Bambu Lab printer, live: camera, progress, time left, layers, temperatures."
    }

    static func searchTerms(french: Bool) -> [String] {
        [title(french: french), "Bambu Lab", "A1", french ? "impression 3D" : "3D printing", french ? "caméra" : "camera"]
    }
}
