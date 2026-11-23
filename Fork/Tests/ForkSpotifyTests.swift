// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Spotify's queue through its Web API (ForkSpotify).
enum ForkSpotifyTests {
    typealias Spotify = ForkSpotify

    static func run(_ suite: TestSuite) {
        preferences(suite)
        signIn(suite)
        tokens(suite)
        queue(suite)
        adapterReply(suite)
    }

    private static let clientID = "0123456789abcdef0123456789ABCDEF"

    private static func playback(_ title: String = "MW2", _ artist: String = "Freeze corleone",
                                 bundle: String? = "com.spotify.client", item: String? = "618AEE09-7A38",
                                 pid: Int32? = 2149) -> NotchPlayback {
        var playback = NotchPlayback(
            track: RadialNowPlayingSnapshot(title: title, artist: artist, album: "ADC", artworkData: nil,
                                           appBundleIdentifier: bundle, appPID: pid),
            isPlaying: true, elapsed: 10, duration: 282.948, rate: 1, sampledAt: .now, canSeek: true)
        playback.itemIdentifier = item
        playback.canSendCommandsDirectly = true
        return playback
    }

    private static func preferences(_ suite: TestSuite) {
        for key in [DefaultsKey.forkSpotifyQueue, DefaultsKey.forkSpotifyClientID] {
            suite.expect(key.hasPrefix("fork") && Defaults.registeredDefaults[key] != nil
                && SettingsBackupSupport.exportKeys().contains(key), "\(key) has its default and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkSpotifyQueue] as? Bool == false,
               "Spotify's queue stays off until set up: it needs the user's own Spotify app")
        suite.expect(Spotify.isValidClientID(clientID) && !Spotify.isValidClientID("0123")
            && !Spotify.isValidClientID(String(repeating: "g", count: 32)),
               "a client ID is 32 hexadecimal characters")
        let name = "fork-spotify-tests"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: DefaultsKey.forkSpotifyQueue)
        defaults.set("  \(clientID)\n", forKey: DefaultsKey.forkSpotifyClientID)
        suite.expect(Spotify.clientID(in: defaults) == clientID, "a pasted client ID loses its surrounding spaces")
        defaults.set("not an id", forKey: DefaultsKey.forkSpotifyClientID)
        suite.expect(Spotify.clientID(in: defaults) == nil && !Spotify.isEnabled(in: defaults),
               "without a valid client ID, the queue is not read")
    }

    private static func signIn(_ suite: TestSuite) {
        // RFC 7636, appendix B.
        suite.expect(Spotify.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
               "the code challenge is the base64url SHA-256 of the verifier")
        let verifier = Spotify.makeVerifier() ?? ""
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        suite.expect((43...128).contains(verifier.count) && verifier.unicodeScalars.allSatisfy(unreserved.contains),
               "a verifier is 43 to 128 unreserved characters")
        suite.expect(Spotify.makeVerifier() != verifier && Spotify.makeState() != Spotify.makeState(),
               "each sign-in draws a fresh verifier and state")

        let url = Spotify.authorizeURL(clientID: clientID, challenge: "abc", state: "xyz")
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        suite.expect(url?.host == "accounts.spotify.com" && item("response_type") == "code"
            && item("code_challenge_method") == "S256" && item("redirect_uri") == "http://127.0.0.1:43821/callback"
            && item("scope") == "user-read-currently-playing user-read-playback-state" && item("state") == "xyz",
               "the sign-in page asks for a PKCE code, read-only playback scopes and the loopback redirect")
        suite.expect(Spotify.authorizeURL(clientID: "bad", challenge: "abc", state: "xyz") == nil,
               "no sign-in without a client ID")

        suite.expect(Spotify.callback(requestLine: "GET /callback?code=AQB-x_9&state=xyz HTTP/1.1", state: "xyz")
                == .code("AQB-x_9"), "the browser's return carries the code")
        suite.expect(Spotify.callback(requestLine: "GET /callback?code=AQB&state=other HTTP/1.1", state: "xyz") == .ignored,
               "a return with another state is ignored")
        suite.expect(Spotify.callback(requestLine: "GET /callback?error=access_denied&state=xyz HTTP/1.1", state: "xyz")
                == .denied, "a refusal is reported")
        suite.expect(Spotify.callback(requestLine: "GET /favicon.ico HTTP/1.1", state: "xyz") == .ignored
            && Spotify.callback(requestLine: "POST /callback?code=a&state=xyz HTTP/1.1", state: "xyz") == .ignored
            && Spotify.callback(requestLine: "garbage", state: "xyz") == .ignored
            && Spotify.callback(requestLine: "GET /callback?code=a&state= HTTP/1.1", state: "") == .ignored,
               "any other request is ignored")
        suite.expect(Spotify.callback(requestLine: "GET /callback?state=xyz HTTP/1.1", state: "xyz") == .denied,
               "a return without a code fails")

        let body = String(data: Spotify.codeExchangeBody(code: "a+b c", verifier: "v", clientID: clientID), encoding: .utf8)
        suite.expect(body == "grant_type=authorization_code&code=a%2Bb%20c&redirect_uri=http%3A%2F%2F127.0.0.1%3A43821%2Fcallback"
                + "&client_id=\(clientID)&code_verifier=v",
               "the code exchange is form-encoded, without any client secret")
        let refresh = String(data: Spotify.refreshBody(refreshToken: "r/1", clientID: clientID), encoding: .utf8)
        suite.expect(refresh == "grant_type=refresh_token&refresh_token=r%2F1&client_id=\(clientID)",
               "a refresh sends the refresh token and the client ID only")
    }

    private static func tokens(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        let first = Spotify.decodeToken(data(["access_token": "A", "token_type": "Bearer", "expires_in": 3600,
                                              "refresh_token": "R", "scope": Spotify.scopes]), now: now)
        suite.expect(first == Spotify.Token(access: "A", refresh: "R", expires: now.addingTimeInterval(3600)),
               "a sign-in gives an access token, a refresh token and an expiry")
        suite.expect(first?.isFresh(at: now.addingTimeInterval(3500)) == true
            && first?.isFresh(at: now.addingTimeInterval(3580)) == false,
               "a token is refreshed in its last thirty seconds")
        let renewed = Spotify.decodeToken(data(["access_token": "B", "token_type": "bearer", "expires_in": 3600]),
                                          previousRefresh: "R", now: now)
        suite.expect(renewed?.access == "B" && renewed?.refresh == "R", "a refresh without a new refresh token keeps the old one")
        suite.expect(Spotify.decodeToken(data(["access_token": "B", "token_type": "Bearer", "expires_in": 3600]), now: now) == nil,
               "a first sign-in without a refresh token is refused")
        suite.expect(Spotify.decodeToken(data(["access_token": "A", "token_type": "MAC", "expires_in": 3600, "refresh_token": "R"])) == nil
            && Spotify.decodeToken(data(["access_token": "", "token_type": "Bearer", "expires_in": 3600, "refresh_token": "R"])) == nil
            && Spotify.decodeToken(data(["access_token": "A", "token_type": "Bearer", "expires_in": 0, "refresh_token": "R"])) == nil
            && Spotify.decodeToken(Data("{".utf8)) == nil,
               "an unexpected token reply is refused")
    }

    private static func track(_ name: String, _ artists: [String], uri: String, ms: Int = 200_000,
                              images: [[String: Any]] = []) -> [String: Any] {
        ["type": "track", "name": name, "uri": uri, "duration_ms": ms,
         "artists": artists.map { ["name": $0] }, "album": ["images": images]]
    }

    private static let images: [[String: Any]] = [
        ["url": "https://i.scdn.co/image/large", "width": 640, "height": 640],
        ["url": "https://i.scdn.co/image/small", "width": 64, "height": 64],
        ["url": "https://i.scdn.co/image/medium", "width": 300, "height": 300],
    ]

    private static func sample() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "currently_playing": track("MW2", ["Freeze Corleone"], uri: "spotify:track:64odXTmh3VS0zh9OYBIFRA", ms: 282_948),
            "queue": [
                track("Rap catéchisme", ["Freeze Corleone", "Alpha Wann"], uri: "spotify:track:1", images: images),
                ["type": "episode", "name": "An episode", "uri": "spotify:episode:2", "duration_ms": 1_800_000,
                 "images": [["url": "https://i.scdn.co/image/ep", "width": 64]], "show": ["name": "A show"]],
                ["type": "track", "name": "", "uri": "spotify:track:3"],
                ["type": "track", "name": "No URI"],
                track("Rap catéchisme", ["Freeze Corleone", "Alpha Wann"], uri: "spotify:track:1", images: images),
                track("Elsewhere", ["Someone"], uri: "spotify:track:4",
                      images: [["url": "http://i.scdn.co/image/plain", "width": 64], ["url": "https://evil.example/x", "width": 64]]),
            ],
        ])
    }

    private static func queue(_ suite: TestSuite) {
        let queue = Spotify.decodeQueue(sample())
        suite.expect(queue?.current?.title == "MW2" && queue?.current?.artist == "Freeze Corleone",
               "the playing song is read")
        suite.expect(queue?.upcoming.map(\.uri) == ["spotify:track:1", "spotify:episode:2", "spotify:track:1", "spotify:track:4"],
               "upcoming songs and episodes keep their order; unreadable entries are left out")
        suite.expect(queue?.upcoming.first?.artist == "Freeze Corleone, Alpha Wann" && queue?.upcoming.first?.duration == 200
            && queue?.upcoming[1].artist == "A show",
               "artists are joined, an episode is credited to its show, lengths are in seconds")
        suite.expect(queue?.upcoming.first?.cover?.absoluteString == "https://i.scdn.co/image/small"
            && queue?.upcoming[1].cover?.absoluteString == "https://i.scdn.co/image/ep",
               "the 64-pixel cover is chosen")
        suite.expect(queue?.upcoming.last?.cover == nil, "a cover from elsewhere than Spotify's image hosts, or over HTTP, is dropped")
        suite.expect(Spotify.decodeQueue(Data("[]".utf8)) == nil && Spotify.decodeQueue(Data("x".utf8)) == nil,
               "an unexpected reply gives no queue")
        suite.expect(Spotify.decodeQueue(try! JSONSerialization.data(withJSONObject: ["queue": []]))
                == Spotify.Queue(current: nil, upcoming: []),
               "nothing queued is an empty queue")
        let many = (1...30).map { track("Song \($0)", ["A"], uri: "spotify:track:\($0)") }
        suite.expect(Spotify.decodeQueue(try! JSONSerialization.data(withJSONObject: ["queue": many]))?.upcoming.count
                == NotchQueueSupport.maximumItems,
               "the island shows as many songs as upstream's queue holds")
        if let covers = queue.map({ Spotify.missingCovers($0, have: [:]) }) {
            suite.expect(covers.count == 2, "each cover is downloaded once, even for a song queued twice")
        }

        let current = queue?.current
        suite.expect(Spotify.matches(current, playback: playback()), "Spotify's playing song is the island's, whatever the case")
        suite.expect(Spotify.matches(current, playback: playback("MW2", "Freeze Corleone, Someone")),
               "the island may list more artists than the service")
        suite.expect(!Spotify.matches(current, playback: playback("Other", "Freeze corleone")) && !Spotify.matches(nil, playback: playback()),
               "another song, right after a change of song, is not the island's")
    }

    private static func adapterReply(_ suite: TestSuite) {
        let request = UUID()
        let shown = playback()
        let unavailable: [String: Any] = ["queueRequest": request.uuidString, "queueAvailable": false]
        suite.expect(Spotify.needsQueue(unavailable, request: request, playback: shown),
               "Spotify answering without a queue is when the fork reads it")
        suite.expect(!Spotify.needsQueue(unavailable, request: UUID(), playback: shown)
            && !Spotify.needsQueue(["queueRequest": request.uuidString, "queueAvailable": true], request: request, playback: shown)
            && !Spotify.needsQueue(unavailable, request: request, playback: playback(bundle: "com.apple.Music"))
            && !Spotify.needsQueue(unavailable, request: request, playback: playback(item: nil)),
               "never for another request, a player that shares its queue, another player, or a song without identifier")

        guard let queue = Spotify.decodeQueue(sample()) else { suite.expect(false, "the sample queue decodes"); return }
        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let reply = Spotify.reply(queue, request: request, playback: shown,
                                  covers: [URL(string: "https://i.scdn.co/image/small")!: cover])
        let snapshot = reply.flatMap { NotchQueueSupport.decode($0, requestID: request, playback: shown) }
        suite.expect(snapshot?.items.count == 4 && snapshot?.items.map(\.offset) == [1, 2, 3, 4],
               "upstream's own decoder accepts the reply, every song in its place")
        suite.expect(Set(snapshot?.items.map(\.id) ?? []).count == 4, "a song queued twice keeps two rows")
        suite.expect(snapshot?.canPlay == false, "read only: Spotify's Web API cannot jump to a queued song")
        suite.expect(snapshot?.items.first?.artwork == cover && snapshot?.items[1].artwork == nil,
               "downloaded covers travel with their songs")
        suite.expect(snapshot?.items.first?.title == "Rap catéchisme" && snapshot?.items.first?.duration == 200,
               "titles and lengths reach the island")
        var moved = shown
        moved.itemIdentifier = "another song"
        suite.expect(reply.flatMap { NotchQueueSupport.decode($0, requestID: request, playback: moved) } == nil,
               "a queue read for one song is not shown under the next")
        suite.expect(Spotify.reply(queue, request: request, playback: playback(pid: nil)) == nil,
               "no reply without the player's process")
        let empty = Spotify.reply(Spotify.Queue(current: nil, upcoming: []), request: request, playback: shown)
        suite.expect(empty.flatMap { NotchQueueSupport.decode($0, requestID: request, playback: shown) }?.items.isEmpty == true,
               "an empty Spotify queue reads as no upcoming songs, not as unavailable")
    }
}
