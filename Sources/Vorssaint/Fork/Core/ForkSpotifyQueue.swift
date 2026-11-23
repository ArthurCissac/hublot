// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CryptoKit
import Foundation
import Security

/// Spotify's queue, read through its Web API for the island's queue page.
///
/// Spotify publishes only its playing song to macOS: the adapter's playback
/// queue request answers `queueAvailable: false`, and its AppleScript
/// dictionary has no queue either. The Web API's `GET /me/player/queue` is the
/// one official source. It needs the user's own app on developer.spotify.com
/// (Development Mode: the owner has Premium, five users at most), signed in
/// with PKCE: a public client, no secret anywhere.
///
/// This file holds the pure parts: sign-in URLs and replies, the queue reply,
/// and its translation into the adapter's queue reply, which upstream's
/// `NotchQueueSupport.decode` validates like any other. The network, the
/// loopback listener and the Keychain live in `Fork/ForkSpotifyAuth.swift`.
enum ForkSpotify {
    static let bundleIdentifier = "com.spotify.client"
    /// The port and path registered as the redirect URI in the user's Spotify app.
    static let redirectPort: UInt16 = 43821
    static let redirectPath = "/callback"
    static let redirectURI = "http://127.0.0.1:43821/callback"
    /// Reading the queue needs these two scopes and nothing else.
    static let scopes = "user-read-currently-playing user-read-playback-state"
    static let authorizeEndpoint = "https://accounts.spotify.com/authorize"
    static let tokenEndpoint = "https://accounts.spotify.com/api/token"
    static let queueEndpoint = "https://api.spotify.com/v1/me/player/queue"
    static let maximumReplyBytes = 1_024 * 1_024
    static let maximumTokenBytes = 16 * 1_024
    static let maximumCoverBytes = NotchQueueSupport.maximumArtworkBytes
    /// Spotify's album art comes in 640, 300 and 64 pixel sizes.
    static let coverPixels = 64

    // MARK: Preferences

    static func clientID(in defaults: UserDefaults = .standard) -> String? {
        let value = (defaults.string(forKey: DefaultsKey.forkSpotifyClientID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidClientID(value) ? value : nil
    }

    /// A Spotify client ID is 32 hexadecimal characters.
    static func isValidClientID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    /// The queue page reads Spotify's queue: upstream's queue is on, the
    /// fork's setting too, and a client ID is set. Being signed in is checked
    /// apart, against the Keychain.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchQueueSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.forkSpotifyQueue)
            && clientID(in: defaults) != nil
    }

    static func isSpotify(_ playback: NotchPlayback?) -> Bool {
        playback?.track.appBundleIdentifier == bundleIdentifier
    }

    /// The adapter answered `request` for Spotify without a queue: the fork may read it.
    static func needsQueue(_ reply: [String: Any], request: UUID, playback: NotchPlayback?) -> Bool {
        reply["queueRequest"] as? String == request.uuidString && reply["queueAvailable"] as? Bool == false
            && isSpotify(playback) && playback?.itemIdentifier != nil && playback?.track.appPID != nil
    }

    // MARK: Sign-in (PKCE, RFC 7636)

    static func randomURLSafe(bytes count: Int) -> String? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return base64URL(Data(bytes))
    }

    /// 64 characters from the unreserved set, within PKCE's 43 to 128.
    static func makeVerifier() -> String? { randomURLSafe(bytes: 48) }
    static func makeState() -> String? { randomURLSafe(bytes: 16) }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(clientID: String, challenge: String, state: String) -> URL? {
        guard isValidClientID(clientID) else { return nil }
        var url = URLComponents(string: authorizeEndpoint)!
        url.queryItems = [URLQueryItem(name: "client_id", value: clientID),
                          URLQueryItem(name: "response_type", value: "code"),
                          URLQueryItem(name: "redirect_uri", value: redirectURI),
                          URLQueryItem(name: "code_challenge_method", value: "S256"),
                          URLQueryItem(name: "code_challenge", value: challenge),
                          URLQueryItem(name: "state", value: state),
                          URLQueryItem(name: "scope", value: scopes)]
        return url.url
    }

    enum Callback: Equatable {
        /// Spotify's authorization code, for the expected state.
        case code(String)
        /// The user refused, or Spotify reported an error, for the expected state.
        case denied
        /// Another path, another state, or an unreadable request: ignore it.
        case ignored
    }

    /// The first line of the browser's request to the loopback listener,
    /// "GET /callback?code=…&state=… HTTP/1.1".
    static func callback(requestLine: String, state expected: String) -> Callback {
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/1."), requestLine.utf8.count <= 4_096,
              let url = URLComponents(string: "http://127.0.0.1" + parts[1]), url.path == redirectPath else { return .ignored }
        let items = url.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard !expected.isEmpty, value("state") == expected else { return .ignored }
        if value("error") != nil { return .denied }
        guard let code = value("code"), !code.isEmpty, code.utf8.count <= 2_048 else { return .denied }
        return .code(code)
    }

    /// An `application/x-www-form-urlencoded` body.
    static func formBody(_ fields: [(String, String)]) -> Data {
        // ASCII only: CharacterSet.alphanumerics would let accented letters through unencoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = fields.map { name, value in
            (name.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "="
                + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    static func codeExchangeBody(code: String, verifier: String, clientID: String) -> Data {
        formBody([("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
                  ("client_id", clientID), ("code_verifier", verifier)])
    }

    static func refreshBody(refreshToken: String, clientID: String) -> Data {
        formBody([("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)])
    }

    struct Token: Codable, Equatable {
        let access: String
        let refresh: String
        let expires: Date

        func isFresh(at now: Date) -> Bool { expires.timeIntervalSince(now) > 30 }
    }

    /// A token reply. A refresh may omit the refresh token, which then stays
    /// the previous one; a first sign-in without one is refused.
    static func decodeToken(_ data: Data, previousRefresh: String? = nil, now: Date = Date()) -> Token? {
        guard data.count <= maximumTokenBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty, access.utf8.count <= 4_096,
              (object["token_type"] as? String)?.lowercased() == "bearer",
              let lifetime = object["expires_in"] as? Int, (60...86_400).contains(lifetime) else { return nil }
        let refresh = (object["refresh_token"] as? String).flatMap { $0.isEmpty || $0.utf8.count > 4_096 ? nil : $0 }
            ?? previousRefresh
        guard let refresh, !refresh.isEmpty else { return nil }
        return Token(access: access, refresh: refresh, expires: now.addingTimeInterval(TimeInterval(lifetime)))
    }

    // MARK: The queue

    struct Song: Equatable {
        let uri: String
        let title: String
        let artist: String
        let duration: Double
        let cover: URL?
    }

    struct Queue: Equatable {
        let current: Song?
        let upcoming: [Song]
    }

    /// `GET /me/player/queue`: `currently_playing` and up to twenty `queue`
    /// entries, songs or podcast episodes. Unreadable entries are left out.
    static func decodeQueue(_ data: Data) -> Queue? {
        guard data.count <= maximumReplyBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let entries = (object["queue"] as? [[String: Any]] ?? []).prefix(100)
        return Queue(current: (object["currently_playing"] as? [String: Any]).flatMap(song),
                     upcoming: Array(entries.compactMap(song).prefix(NotchQueueSupport.maximumItems)))
    }

    private static func song(_ item: [String: Any]) -> Song? {
        guard let title = item["name"] as? String, !title.isEmpty, title.utf8.count <= 4_096,
              let uri = item["uri"] as? String, uri.hasPrefix("spotify:"), uri.utf8.count <= 256,
              !uri.contains("\0") else { return nil }
        let names = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            ?? ((item["show"] as? [String: Any])?["name"] as? String).map { [$0] } ?? []
        let milliseconds = (item["duration_ms"] as? NSNumber)?.doubleValue ?? 0
        let images = (item["album"] as? [String: Any])?["images"] as? [[String: Any]]
            ?? item["images"] as? [[String: Any]]
            ?? (item["show"] as? [String: Any])?["images"] as? [[String: Any]] ?? []
        return Song(uri: uri, title: String(title.prefix(1_024)),
                    artist: String(names.joined(separator: ", ").prefix(1_024)),
                    duration: milliseconds.isFinite && milliseconds > 0 ? min(milliseconds / 1_000, 604_800) : 0,
                    cover: cover(images))
    }

    /// The smallest image at least `coverPixels` wide, else the largest; only
    /// from Spotify's image hosts, over HTTPS.
    static func cover(_ images: [[String: Any]]) -> URL? {
        let candidates: [(url: URL, width: Int)] = images.compactMap { image in
            guard let text = image["url"] as? String, text.utf8.count <= 512, let url = URL(string: text),
                  url.scheme == "https", let host = url.host?.lowercased(),
                  host == "scdn.co" || host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") else { return nil }
            return (url, (image["width"] as? Int) ?? 0)
        }
        let sorted = candidates.sorted { $0.width < $1.width }
        return (sorted.first { $0.width >= coverPixels } ?? sorted.last)?.url
    }

    /// The song Spotify's service names is the one the island shows. Right
    /// after a change of song, the service can still name the previous one.
    static func matches(_ song: Song?, playback: NotchPlayback) -> Bool {
        guard let song, let title = playback.track.title, folded(song.title) == folded(title) else { return false }
        let artist = folded(playback.track.artist ?? "")
        guard !artist.isEmpty else { return true }
        let first = folded(song.artist.components(separatedBy: ", ").first ?? song.artist)
        return folded(song.artist) == artist || (!first.isEmpty && artist.contains(first))
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// The queue as an adapter reply for `request`, anchored on the island's
    /// song, read-only: Spotify's Web API cannot jump to a queued song.
    /// `covers` holds downloaded art by cover URL.
    static func reply(_ queue: Queue, request: UUID, playback: NotchPlayback,
                      covers: [URL: Data] = [:]) -> [String: Any]? {
        guard let current = playback.itemIdentifier, let pid = playback.track.appPID else { return nil }
        let rows: [[String: Any]] = queue.upcoming.prefix(NotchQueueSupport.maximumItems).enumerated().map { index, song in
            var row: [String: Any] = [
                // A song queued twice keeps two rows: the id carries its place.
                "id": "spotify-queue:\(index + 1):\(song.uri)", "offset": index + 1,
                "title": song.title, "artist": song.artist, "duration": song.duration,
            ]
            if let url = song.cover, let data = covers[url], data.count <= maximumCoverBytes {
                row["artworkBase64"] = data.base64EncodedString()
            }
            return row
        }
        return ["queueRequest": request.uuidString, "currentIdentifier": current, "pid": NSNumber(value: pid),
                "queueAvailable": true, "queueItems": rows, "queueCanPlay": false]
    }

    /// The covers still to download, at most one per song.
    static func missingCovers(_ queue: Queue, have covers: [URL: Data]) -> [URL] {
        var seen = Set<URL>()
        return queue.upcoming.compactMap(\.cover).filter { covers[$0] == nil && seen.insert($0).inserted }
    }
}
