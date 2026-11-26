// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The Printer page: a local address and a code only, the camera's login
/// and pictures, MQTT's packets, the print state, the printer's
/// announcement and the certificate remembered.
enum ForkBambuTests {
    typealias Logic = ForkBambuLogic

    static func run(_ suite: TestSuite) {
        addresses(suite)
        camera(suite)
        mqtt(suite)
        status(suite)
        discovery(suite)
    }

    private static func addresses(_ suite: TestSuite) {
        suite.expect(Logic.host(" 192.168.1.50 ") == "192.168.1.50" && Logic.host("bambu-a1.local") == "bambu-a1.local"
            && Logic.host("8.8.8.8") == nil && Logic.host("http://192.168.1.50") == nil && Logic.host("printer.example.com") == nil,
                     "a printer is reached on the local network only, by a bare address")
        suite.expect(Logic.cleanCode(" 12345678 ") == "12345678" && Logic.cleanCode("12 34") == nil && Logic.cleanCode("12") == nil,
                     "the access code is letters and digits")
    }

    private static func camera(_ suite: TestSuite) {
        let login = Logic.cameraLogin(code: "12345678")
        suite.expect(login?.count == 80 && login.map { Array($0.prefix(8)) } == [0x40, 0, 0, 0, 0, 0x30, 0, 0]
            && login.map { Array($0[16..<20]) } == Array("bblp".utf8)
            && login.map { Array($0[48..<56]) } == Array("12345678".utf8) && login?[56] == 0
            && Logic.cameraLogin(code: "bad code") == nil,
                     "the camera's login: four words, then the user and the code in 32 bytes each")
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]
        var header = [UInt8](repeating: 0, count: 16)
        header[0] = UInt8(jpeg.count)
        let stream = Data(header + jpeg + header + jpeg)
        var reader = Logic.PictureReader()
        let first = reader.feed(stream.prefix(20))
        let rest = reader.feed(stream.dropFirst(20))
        suite.expect(first.isEmpty && rest.count == 2 && rest.first == Data(jpeg) && reader.buffer.isEmpty,
                     "pictures are cut out of the stream, even split across reads")
        var broken = Logic.PictureReader()
        _ = broken.feed(Data([0xFF, 0xFF, 0xFF, 0x7F] + [UInt8](repeating: 0, count: 12)))
        suite.expect(broken.broken, "a header claiming a huge picture marks the stream broken")
    }

    private static func mqtt(_ suite: TestSuite) {
        suite.expect(Logic.remainingLength(0) == [0] && Logic.remainingLength(127) == [127]
            && Logic.remainingLength(128) == [0x80, 0x01] && Logic.remainingLength(16_383) == [0xFF, 0x7F],
                     "MQTT lengths take seven bits a byte")
        let connect = Logic.connect(clientID: "hublot", code: "12345678")
        let expectedBody: [UInt8] = [0, 4] + Array("MQTT".utf8) + [4, 0xC2, 0, 30] + [0, 6] + Array("hublot".utf8)
            + [0, 4] + Array("bblp".utf8) + [0, 8] + Array("12345678".utf8)
        suite.expect(connect == Data([0x10, UInt8(expectedBody.count)] + expectedBody),
                     "CONNECT carries MQTT 3.1.1, a clean session, the user bblp and the code")
        suite.expect(Logic.subscribe(id: 1, topic: "device/ABC123/report")
                        == Data([0x82, 25, 0, 1, 0, 20] + Array("device/ABC123/report".utf8) + [0]),
                     "SUBSCRIBE asks for the printer's reports")
        var reader = Logic.PacketReader()
        let payload = Data(#"{"print":{"mc_percent":42}}"#.utf8)
        let publish = Logic.publish(topic: "device/ABC123/report", payload: payload)
        let packets = reader.feed(Data([0x20, 0x02, 0x00, 0x00]) + publish.prefix(10))
            + reader.feed(publish.dropFirst(10) + Data([0x90, 0x03, 0x00, 0x01, 0x00, 0xD0, 0x00]))
        suite.expect(packets == [.connected(accepted: true), .message(topic: "device/ABC123/report", payload: payload), .subscribed, .pong],
                     "packets are read in order, a message split across reads included")
        var refused = Logic.PacketReader()
        suite.expect(refused.feed(Data([0x20, 0x02, 0x00, 0x05])) == [.connected(accepted: false)], "a refused code is read")
        suite.expect(Logic.decode(first: 0x32, body: [0, 1] + Array("t".utf8) + [0, 9] + Array("x".utf8))
                        == .message(topic: "t", payload: Data("x".utf8)),
                     "a message with QoS 1 skips its packet id")
        suite.expect(Logic.isSerial("03919A3B1200123") && !Logic.isSerial("bad/serial")
            && Logic.serial(fromTopic: "device/03919A3B1200123/report") == "03919A3B1200123"
            && Logic.serial(fromTopic: "device/x/y/report") == nil,
                     "serials are letters and digits, and a report's topic names one")
    }

    private static func status(_ suite: TestSuite) {
        var status = Logic.Status()
        status = Logic.merging(Data(#"{"print":{"gcode_state":"RUNNING","mc_percent":45,"mc_remaining_time":70,"layer_num":50,"total_layer_num":200,"nozzle_temper":219.6,"nozzle_target_temper":220,"bed_temper":40.2,"bed_target_temper":65,"subtask_name":"Benchy"}}"#.utf8), into: status)
        status = Logic.merging(Data(#"{"print":{"mc_percent":46,"command":"push_status"}}"#.utf8), into: status)
        suite.expect(status.percent == 46 && status.layer == 50 && status.job == "Benchy" && status.printing,
                     "reports merge into what is known")
        suite.expect(Logic.stateText(status, french: true) == "Impression" && Logic.remaining(70) == "1 h 10" && Logic.remaining(45) == "45 min"
            && Logic.temperature(status.nozzle, target: status.nozzleTarget) == "220 °C"
            && Logic.temperature(status.bed, target: status.bedTarget) == "40 → 65 °C",
                     "the state reads in words, time left in hours, temperatures with their target while heating")
        suite.expect(Logic.merging(Data("nope".utf8), into: status) == status, "a broken report changes nothing")
        let finished = Logic.merging(Data(#"{"print":{"gcode_state":"FINISH"}}"#.utf8), into: status)
        suite.expect(!finished.printing && Logic.stateText(finished, french: true) == "Terminé", "a finished print is not printing")
    }

    private static func discovery(_ suite: TestSuite) {
        let announcement = """
        NOTIFY * HTTP/1.1\r
        HOST: 239.255.255.250:1990\r
        Location: 192.168.1.140\r
        NT: urn:bambulab-com:device:3dprinter:1\r
        USN: 03919A3B1200123\r
        DevModel.bambu.com: N2S\r
        DevName.bambu.com: Atelier\r
        DevConnect.bambu.com: cloud\r
        """
        suite.expect(Logic.printer(fromAnnouncement: announcement)
                        == Logic.Printer(host: "192.168.1.140", serial: "03919A3B1200123", name: "Atelier", model: "A1"),
                     "a printer's announcement gives its address, serial, name and model")
        suite.expect(Logic.printer(fromAnnouncement: announcement.replacingOccurrences(of: "192.168.1.140", with: "8.8.8.8")) == nil
            && Logic.printer(fromAnnouncement: "NOTIFY * HTTP/1.1\nNT: upnp:rootdevice\nLocation: 192.168.1.2\nUSN: X1234567") == nil,
                     "an announcement from elsewhere or from another device is ignored")
        let pin = String(repeating: "a", count: 64)
        suite.expect(Logic.trust(pin, pins: []) == .first && Logic.trust(pin, pins: [pin]) == .known
            && Logic.trust(String(repeating: "b", count: 64), pins: [pin]) == .changed
            && Logic.pins(Logic.adding(pin, port: 6000, to: "8883:bad"), port: 6000) == [pin]
            && Logic.pins(Logic.adding(pin, port: 6000, to: nil), port: 8883).isEmpty,
                     "the certificate is remembered the first time and another refused after")
        suite.expect(Logic.pageHeight(width: 492) == 270 + 66 + 8 + 8 && Logic.title(french: true) == "Imprimante"
            && Defaults.registeredDefaults[DefaultsKey.forkBambuEnabled] as? Bool == false,
                     "the page is 16:9 plus its state, and starts off")
    }
}
