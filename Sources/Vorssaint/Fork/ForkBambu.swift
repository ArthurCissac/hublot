// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import CryptoKit
import Network
import Security
import SwiftUI

/// A Bambu Lab printer in the island, reached directly on the local network
/// (see `ForkBambuLogic`). The camera and the print state are read only
/// while the Printer page is open; the search listens for the printer's
/// announcement for a few seconds when asked. Nothing goes to the cloud.
///
/// Security: the access code lives in the Keychain only, read when a
/// connection logs in, never kept in memory, preferences, backups nor logs.
/// It goes to a local address only, over TLS. The printer signs its own
/// certificates, so each port's is remembered at the first connection and
/// a different one is refused (`forkBambuPins`) until the user forgets it.

// MARK: - The access code

enum ForkBambuKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "agency.nexflow.hublot") + ".bambu" }
    private static let account = "access-code"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func exists() -> Bool {
        var search = query
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(search as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func save(_ code: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: Data(code.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - The service

final class ForkBambu: ObservableObject {
    typealias Logic = ForkBambuLogic

    static let shared = ForkBambu()

    enum Link: Equatable {
        case off, needsSetup
        /// Set up, connected only while the page is open.
        case idle
        case connecting, live
        /// The printer refused the access code.
        case refused
        case unreachable
        /// The printer showed another certificate than the one remembered.
        case certificateChanged
    }

    @Published private(set) var link: Link = .off
    @Published private(set) var hasCode = false
    @Published private(set) var status = Logic.Status()
    @Published private(set) var picture: NSImage?
    @Published private(set) var cameraFailed = false
    @Published private(set) var found: [Logic.Printer] = []
    @Published private(set) var searching = false
    /// A search has ended: an empty list then means nothing answered.
    @Published private(set) var searched = false

    private let queue = DispatchQueue(label: "agency.nexflow.hublot.bambu", qos: .userInitiated)
    private var camera: NWConnection?
    private var mqtt: NWConnection?
    private var listener: NWListener?
    /// Used on `queue` only.
    private var pictures = Logic.PictureReader()
    private var packets = Logic.PacketReader()
    private var pingTimer: Timer?
    private var retryStatus: DispatchWorkItem?
    private var retryCamera: DispatchWorkItem?
    private var open = false
    private var observer: NSObjectProtocol?

    private var defaults: UserDefaults { .standard }
    var enabled: Bool { defaults.bool(forKey: DefaultsKey.forkBambuEnabled) }
    var host: String? { Logic.host(defaults.string(forKey: DefaultsKey.forkBambuHost) ?? "") }
    var serial: String? { (defaults.string(forKey: DefaultsKey.forkBambuSerial)).flatMap { Logic.isSerial($0) ? $0 : nil } }
    var name: String? { defaults.string(forKey: DefaultsKey.forkBambuName).flatMap { $0.isEmpty ? nil : $0 } }
    private var ready: Bool { enabled && host != nil && hasCode }

    func start() {
        Logic.contentHeight = { width in ForkBambu.shared.ready ? Logic.pageHeight(width: width) : nil }
        hasCode = ForkBambuKeychain.exists()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.sync() }
        sync()
    }

    private func sync() {
        if !enabled {
            close()
            if link != .off { link = .off }
        } else if !ready {
            close()
            if link != .needsSetup { link = .needsSetup }
        } else if link == .off || link == .needsSetup {
            if open { connect() } else { link = .idle }
        }
    }

    // MARK: The page

    func pageOpened() {
        open = true
        guard ready else { return sync() }
        connect()
    }

    func pageClosed() {
        open = false
        close()
        if ready, link != .refused, link != .certificateChanged { link = .idle }
    }

    /// Tries again now (the settings' Test button too).
    func reconnect() {
        guard ready else { return sync() }
        connect()
        // From the settings, with the page closed: just long enough to see the answer.
        if !open {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self, !self.open else { return }
                self.close()
                if self.link == .live || self.link == .connecting { self.link = .idle }
            }
        }
    }

    private func connect() {
        close()
        guard ready, let host else { return }
        link = .connecting
        cameraFailed = false
        openStatus(host: host)
        if open { openCamera(host: host) }
    }

    private func close() {
        retryStatus?.cancel(); retryStatus = nil
        retryCamera?.cancel(); retryCamera = nil
        pingTimer?.invalidate(); pingTimer = nil
        if let mqtt { mqtt.send(content: Logic.disconnect, completion: .idempotent); mqtt.cancel() }
        camera?.cancel()
        mqtt = nil
        camera = nil
        queue.async { [weak self] in
            self?.pictures = Logic.PictureReader()
            self?.packets = Logic.PacketReader()
        }
    }

    /// While the page is open, a dropped connection is tried again a little later, on its own.
    private func scheduleRetry(camera: Bool) {
        guard open, ready, let host, (camera ? retryCamera : retryStatus) == nil, link != .refused,
              link != .certificateChanged else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.open else { return }
            if camera {
                self.retryCamera = nil
                if self.camera == nil { self.openCamera(host: host) }
            } else {
                self.retryStatus = nil
                if self.mqtt == nil { self.openStatus(host: host) }
            }
        }
        if camera { retryCamera = work } else { retryStatus = work }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: TLS with a remembered certificate

    private func parameters(port: UInt16) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, trust, complete in
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(ref) as? [SecCertificate], let leaf = chain.first else {
                return complete(false)
            }
            let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
            let subject = SecCertificateCopySubjectSummary(leaf) as String?
            DispatchQueue.main.async {
                complete(self?.accept(fingerprint, subject: subject, port: port) ?? false)
            }
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 8
        return NWParameters(tls: tls, tcp: tcp)
    }

    private func accept(_ fingerprint: String, subject: String?, port: UInt16) -> Bool {
        let stored = defaults.string(forKey: DefaultsKey.forkBambuPins)
        switch Logic.trust(fingerprint, pins: Logic.pins(stored, port: port)) {
        case .known: break
        case .first: defaults.set(Logic.adding(fingerprint, port: port, to: stored), forKey: DefaultsKey.forkBambuPins)
        case .changed:
            link = .certificateChanged
            return false
        }
        // The certificate is made out to the printer's serial number.
        if serial == nil, let subject, Logic.isSerial(subject) { defaults.set(subject, forKey: DefaultsKey.forkBambuSerial) }
        return true
    }

    /// After the user checked the printer: its new certificates are accepted once.
    func forgetCertificates() {
        defaults.removeObject(forKey: DefaultsKey.forkBambuPins)
        if link == .certificateChanged { link = .connecting }
        reconnect()
    }

    // MARK: The camera

    private func openCamera(host: String) {
        guard let port = NWEndpoint.Port(rawValue: Logic.cameraPort) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters(port: Logic.cameraPort))
        camera = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                guard let code = ForkBambuKeychain.load(), let login = Logic.cameraLogin(code: code) else { return connection.cancel() }
                connection.send(content: login, completion: .contentProcessed { _ in })
                self?.receivePictures(on: connection)
            case .failed, .waiting:
                DispatchQueue.main.async {
                    guard let self, self.camera === connection else { return }
                    self.cameraFailed = true
                    connection.cancel()
                    self.camera = nil
                    self.scheduleRetry(camera: true)
                }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receivePictures(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            let latest = data.flatMap { self.pictures.feed($0).last }
            if let latest, let image = NSImage(data: latest) {
                DispatchQueue.main.async {
                    guard self.camera === connection else { return }
                    self.picture = image
                    self.cameraFailed = false
                }
            }
            if done || error != nil || self.pictures.broken {
                DispatchQueue.main.async {
                    guard self.camera === connection else { return }
                    connection.cancel()
                    self.camera = nil
                    self.cameraFailed = true
                    self.scheduleRetry(camera: true)
                }
            } else {
                self.receivePictures(on: connection)
            }
        }
    }

    // MARK: The print state

    private func openStatus(host: String) {
        guard let port = NWEndpoint.Port(rawValue: Logic.statusPort) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters(port: Logic.statusPort))
        mqtt = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                let client = "hublot-" + UUID().uuidString.prefix(8).lowercased()
                guard let code = ForkBambuKeychain.load(), let hello = Logic.connect(clientID: client, code: code) else {
                    return connection.cancel()
                }
                connection.send(content: hello, completion: .contentProcessed { _ in })
                self?.receivePackets(on: connection)
            case .failed, .waiting:
                DispatchQueue.main.async {
                    guard let self, self.mqtt === connection else { return }
                    connection.cancel()
                    self.mqtt = nil
                    if self.link != .certificateChanged { self.link = .unreachable }
                    self.scheduleRetry(camera: false)
                }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receivePackets(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            let incoming = data.map { self.packets.feed($0) } ?? []
            let broken = self.packets.broken
            DispatchQueue.main.async {
                guard self.mqtt === connection else { return }
                for packet in incoming { self.handle(packet, on: connection) }
                if done || error != nil || broken {
                    connection.cancel()
                    self.mqtt = nil
                    if self.link == .live || self.link == .connecting { self.link = .unreachable }
                    self.scheduleRetry(camera: false)
                }
            }
            if !(done || error != nil || broken) { self.receivePackets(on: connection) }
        }
    }

    private func handle(_ packet: Logic.Incoming, on connection: NWConnection) {
        switch packet {
        case .connected(let accepted):
            guard accepted else {
                link = .refused
                connection.cancel()
                mqtt = nil
                return
            }
            link = .live
            // Without the serial yet, every printer's reports: the first names it.
            let topic = serial.map(Logic.reportTopic(serial:)) ?? Logic.anyReportTopic
            connection.send(content: Logic.subscribe(id: 1, topic: topic), completion: .contentProcessed { _ in })
            if let serial { askEverything(on: connection, serial: serial) }
            startPing(on: connection)
        case .message(let topic, let payload):
            if serial == nil, let named = Logic.serial(fromTopic: topic) {
                defaults.set(named, forKey: DefaultsKey.forkBambuSerial)
                askEverything(on: connection, serial: named)
            }
            guard let serial, topic == Logic.reportTopic(serial: serial) else { return }
            let next = Logic.merging(payload, into: status)
            if next != status { status = next }
        case .subscribed, .pong, .other:
            break
        }
    }

    private func askEverything(on connection: NWConnection, serial: String) {
        connection.send(content: Logic.publish(topic: Logic.requestTopic(serial: serial), payload: Logic.pushAll()),
                        completion: .contentProcessed { _ in })
    }

    private func startPing(on connection: NWConnection) {
        pingTimer?.invalidate()
        let timer = Timer(timeInterval: 25, repeats: true) { [weak self, weak connection] _ in
            guard let connection, self?.mqtt === connection else { return }
            connection.send(content: Logic.ping, completion: .contentProcessed { _ in })
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    // MARK: Finding the printer

    /// Listens a few seconds for printers announcing themselves on the network.
    func search() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Logic.announcePort) else { return }
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else { return }
        self.listener = listener
        searching = true
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.read(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { DispatchQueue.main.async { self?.stopSearching() } }
        }
        listener.start(queue: queue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.stopSearching() }
    }

    private func read(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, data.count <= 4096, let text = String(data: data, encoding: .utf8),
               let printer = Logic.printer(fromAnnouncement: text) {
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let index = self.found.firstIndex(where: { $0.serial == printer.serial }) {
                        self.found[index] = printer
                    } else {
                        self.found.append(printer)
                    }
                }
            }
            if error == nil, self?.listener != nil { self?.read(connection) } else { connection.cancel() }
        }
    }

    private func stopSearching() {
        guard listener != nil || searching else { return }
        listener?.cancel()
        listener = nil
        searching = false
        searched = true
    }

    /// The printer chosen in the search: its address, serial and name.
    func choose(_ printer: Logic.Printer) {
        defaults.set(printer.host, forKey: DefaultsKey.forkBambuHost)
        defaults.set(printer.serial, forKey: DefaultsKey.forkBambuSerial)
        defaults.set(printer.name, forKey: DefaultsKey.forkBambuName)
    }

    // MARK: The access code

    @discardableResult
    func setCode(_ raw: String) -> Bool {
        guard let code = Logic.cleanCode(raw), ForkBambuKeychain.save(code) else { return false }
        hasCode = true
        sync()
        return true
    }

    func forgetCode() {
        ForkBambuKeychain.delete()
        hasCode = false
        sync()
    }
}
