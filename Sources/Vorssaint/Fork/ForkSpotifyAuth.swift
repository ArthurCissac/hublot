// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import Foundation
import Network
import Security

/// Signing in to Spotify, and the tokens it gives.
///
/// Security posture:
/// - PKCE public client: the client ID is the user's own and public; there is
///   no client secret, in the code or anywhere else.
/// - The browser comes back to a listener bound to 127.0.0.1 only, open from
///   "Connect" until the code arrives or five minutes pass. It accepts only the
///   callback path with the state it generated; every other request gets a 404.
/// - Tokens are stored in the Keychain (this Mac only), never in preferences,
///   settings backups or logs. "Disconnect" deletes them.
/// - Requests go to accounts.spotify.com and api.spotify.com only, without
///   cookies or cache, redirects refused.
final class ForkSpotifyAuth: ObservableObject {
    static let shared = ForkSpotifyAuth()

    enum State: Equatable { case disconnected, waiting, connected, failed }
    @Published private(set) var state: State = .disconnected

    private var listener: NWListener?
    private var verifier: String?
    private var expectedState: String?
    private var timeout: DispatchWorkItem?
    private var waiters: [(String?) -> Void] = []
    private var refreshing = false

    private init() {
        state = ForkSpotifyKeychain.load() == nil ? .disconnected : .connected
    }

    var isConnected: Bool { state == .connected }

    // MARK: Connect

    func connect() {
        guard let clientID = ForkSpotify.clientID(), let verifier = ForkSpotify.makeVerifier(),
              let expected = ForkSpotify.makeState(),
              let url = ForkSpotify.authorizeURL(clientID: clientID, challenge: ForkSpotify.challenge(for: verifier),
                                                 state: expected) else { state = .failed; return }
        stopListening()
        do {
            let parameters = NWParameters.tcp
            // Loopback only: nothing outside this Mac can reach the listener.
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                         port: NWEndpoint.Port(rawValue: ForkSpotify.redirectPort)!)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { DispatchQueue.main.async { self?.finish(success: false) } }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed
            return
        }
        self.verifier = verifier
        expectedState = expected
        state = .waiting
        let work = DispatchWorkItem { [weak self] in self?.finish(success: false) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
        NSWorkspace.shared.open(url)
    }

    func disconnect() {
        stopListening()
        ForkSpotifyKeychain.delete()
        flushWaiters(nil)
        state = .disconnected
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let line = text.components(separatedBy: "\r\n").first ?? ""
            let result = ForkSpotify.callback(requestLine: line, state: self.expectedState ?? "")
            let strings = ForkMusicStrings.current
            switch result {
            case .ignored:
                self.respond(connection, status: "404 Not Found", message: nil)
            case .denied:
                self.respond(connection, status: "200 OK", message: strings.browserFailed(AppInfo.name))
                self.finish(success: false)
            case .code(let code):
                self.respond(connection, status: "200 OK", message: strings.browserConnected(AppInfo.name))
                self.exchange(code)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, message: String?) {
        let body = message.map {
            "<!doctype html><meta charset=\"utf-8\"><title>\(AppInfo.name)</title>"
                + "<body style=\"font:16px -apple-system,sans-serif;margin:4em auto;max-width:32em\"><p>\(escaped($0))</p>"
        } ?? ""
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n"
            + "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nCache-Control: no-store\r\n"
            + "Referrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func exchange(_ code: String) {
        guard let verifier, let clientID = ForkSpotify.clientID() else { finish(success: false); return }
        stopListening()
        ForkSpotifyHTTP.post(ForkSpotify.tokenEndpoint,
                             body: ForkSpotify.codeExchangeBody(code: code, verifier: verifier, clientID: clientID),
                             maximumBytes: ForkSpotify.maximumTokenBytes) { [weak self] status, data in
            guard let self else { return }
            let token = status == 200 ? data.flatMap { ForkSpotify.decodeToken($0) } : nil
            if let token, ForkSpotifyKeychain.save(token) {
                self.state = .connected
            } else {
                self.state = .failed
            }
        }
    }

    private func finish(success: Bool) {
        stopListening()
        if !success, state == .waiting { state = .failed }
    }

    private func stopListening() {
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        verifier = nil
        expectedState = nil
    }

    // MARK: Access token

    /// A valid access token, refreshed when needed, on the main queue. Nil when
    /// signed out, or when Spotify refused the refresh.
    func accessToken(_ completion: @escaping (String?) -> Void) {
        guard let token = ForkSpotifyKeychain.load() else { completion(nil); return }
        if token.isFresh(at: Date()) { completion(token.access); return }
        waiters.append(completion)
        guard !refreshing, let clientID = ForkSpotify.clientID() else {
            if !refreshing { flushWaiters(nil) }
            return
        }
        refreshing = true
        ForkSpotifyHTTP.post(ForkSpotify.tokenEndpoint,
                             body: ForkSpotify.refreshBody(refreshToken: token.refresh, clientID: clientID),
                             maximumBytes: ForkSpotify.maximumTokenBytes) { [weak self] status, data in
            guard let self else { return }
            self.refreshing = false
            if status == 200, let fresh = data.flatMap({ ForkSpotify.decodeToken($0, previousRefresh: token.refresh) }),
               ForkSpotifyKeychain.save(fresh) {
                self.flushWaiters(fresh.access)
            } else {
                // A revoked or expired grant: sign out. A network failure keeps the tokens.
                if status == 400 || status == 401 { ForkSpotifyKeychain.delete(); self.state = .disconnected }
                self.flushWaiters(nil)
            }
        }
    }

    /// The current access token stopped working before its time (revoked app).
    func invalidateAccessToken() {
        guard let token = ForkSpotifyKeychain.load() else { return }
        _ = ForkSpotifyKeychain.save(ForkSpotify.Token(access: token.access, refresh: token.refresh, expires: .distantPast))
    }

    private func flushWaiters(_ token: String?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0(token) }
    }
}

/// The tokens, as one generic password of the login keychain, this Mac only.
enum ForkSpotifyKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "agency.nexflow.hublot") + ".spotify-oauth" }
    private static let account = "tokens"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> ForkSpotify.Token? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ForkSpotify.Token.self, from: data)
    }

    @discardableResult
    static func save(_ token: ForkSpotify.Token) -> Bool {
        guard let data = try? JSONEncoder().encode(token) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
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

/// Bounded, ephemeral HTTPS requests to Spotify: no cookies, no cache, no
/// redirects. Completions run on the main queue with the status and the body.
final class ForkSpotifyHTTP: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var status: Int?
    private let maximumBytes: Int
    private let completion: (Int?, Data?) -> Void

    private init(maximumBytes: Int, completion: @escaping (Int?, Data?) -> Void) {
        self.maximumBytes = maximumBytes
        self.completion = completion
    }

    static func get(_ url: URL, bearer: String, maximumBytes: Int, completion: @escaping (Int?, Data?) -> Void) -> URLSession {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        return start(request, maximumBytes: maximumBytes, completion: completion)
    }

    @discardableResult
    static func post(_ endpoint: String, body: Data, maximumBytes: Int,
                     completion: @escaping (Int?, Data?) -> Void) -> URLSession? {
        guard let url = URL(string: endpoint) else { completion(nil, nil); return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return start(request, maximumBytes: maximumBytes, completion: completion)
    }

    static func download(_ url: URL, maximumBytes: Int, completion: @escaping (Int?, Data?) -> Void) -> URLSession {
        start(URLRequest(url: url), maximumBytes: maximumBytes, completion: completion)
    }

    private static func start(_ request: URLRequest, maximumBytes: Int,
                              completion: @escaping (Int?, Data?) -> Void) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        let delegate = ForkSpotifyHTTP(maximumBytes: maximumBytes, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: request).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode
        completionHandler(response.expectedContentLength <= maximumBytes ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= maximumBytes - data.count else { dataTask.cancel(); data.removeAll(); return }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = self.status
        let body = error == nil ? data : nil
        DispatchQueue.main.async { self.completion(status, body) }
    }
}
