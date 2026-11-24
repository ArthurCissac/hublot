// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lyrics a few seconds off the song's length (ForkLyricsNearbyDuration).
enum ForkLyricsTests {
    typealias Nearby = ForkLyricsNearbyDuration

    static func run(_ suite: TestSuite) {
        preference(suite)
        spotifyLength(suite)
        limits(suite)
        albums(suite)
    }

    private static func identity(_ title: String, _ artist: String, _ album: String, _ duration: Double) -> NotchMusicIdentity {
        NotchMusicIdentity(NotchPlayback(
            track: RadialNowPlayingSnapshot(title: title, artist: artist, album: album, artworkData: nil,
                                           appBundleIdentifier: "com.spotify.client", appPID: nil),
            isPlaying: true, elapsed: 0, duration: duration, rate: 1, sampledAt: .now, canSeek: false))
    }

    /// A record as LRCLIB's search returns it. Metadata comes from the real
    /// catalog; the verses are synthetic.
    private static func record(_ id: Int, _ title: String, _ artist: String, _ album: String, _ duration: Double,
                               lastLine: String = "04:43.40") -> [String: Any] {
        ["id": id, "trackName": title, "artistName": artist, "albumName": album, "duration": duration,
         "syncedLyrics": "[00:00.10]First verse\n[02:10.00]Middle verse\n[04:41.06]Last verse\n[\(lastLine)]",
         "plainLyrics": "First verse\nMiddle verse\nLast verse", "instrumental": false]
    }

    private static func reply(_ records: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: records)
    }

    private static func withDefaults(_ enabled: Bool?, _ body: (UserDefaults) -> Void) {
        let name = "fork-lyrics-nearby-tests"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        if let enabled { defaults.set(enabled, forKey: DefaultsKey.forkLyricsNearbyDuration) }
        body(defaults)
    }

    private static func preference(_ suite: TestSuite) {
        let key = DefaultsKey.forkLyricsNearbyDuration
        suite.expect(key.hasPrefix("fork") && Defaults.registeredDefaults[key] as? Bool == true,
               "lyrics a few seconds off are accepted out of the box")
        suite.expect(SettingsBackupSupport.exportKeys().contains(key), "the nearby-length preference travels in backups")
        withDefaults(nil) { defaults in
            suite.expect(!Nearby.isEnabled(in: defaults), "an unregistered domain reads the pass as off")
        }
    }

    /// Spotify plays "MW2" for 282.948 s; LRCLIB's five records all say about 288 s.
    private static func spotifyLength(_ suite: TestSuite) {
        let track = identity("MW2", "Freeze corleone", "ADC", 282.948)
        let catalog = reply([
            record(3440754, "MW2", "Freeze Corleone", "ADC", 288),
            record(16080090, "MW2", "Freeze Corleone", "4:48", 288, lastLine: "04:36.23"),
            record(9525934, "MW2", "Freeze Corleone", "Freeze Corleone", 288, lastLine: "04:36.23"),
            record(33997677, "MW2", "Freeze Corleone", "ADC (version CD)", 288),
            record(22268927, "MW2 (Paused)", "Freeze corleone", "ADC", 287.948, lastLine: "04:36.20"),
        ])
        suite.expect(NotchLyricsSupport.searchCandidates(catalog, for: track).isEmpty
            && NotchLyricsSupport.containsCatalogRecording(catalog, for: track),
               "upstream knows the recording yet refuses every record five seconds off: the bug the pass fixes")
        withDefaults(true) { defaults in
            let found = Nearby.candidates(catalog, strictFound: false, for: track, defaults: defaults)
            suite.expect(found.count == 1 && found.first?.recordID == 3440754,
                   "only the record on the player's album, with the same title, is kept")
            suite.expect(found.allSatisfy { $0.score < 0 && abs($0.distance - 5) < 0.01 },
                   "it ranks below any strict record, five seconds away")
            let lyrics = NotchLyricsSupport.bestLyrics(in: found)
            suite.expect(lyrics?.lines.count == 3 && (lyrics?.lines.last?.time ?? 999) <= track.duration,
                   "its synchronized verses are shown, the timed blank past the song's end left out")

            let strict = NotchLyricsSupport.searchCandidates(
                reply([record(1, "MW2", "Freeze Corleone", "Compilation", 283, lastLine: "04:40.00")]), for: track)
            suite.expect(strict.count == 1, "a record of the right length on another album passes upstream's own check")
            let best = NotchLyricsSupport.bestLyrics(in: found + strict)
            suite.expect(best == strict.first?.lyrics, "a strict record from any reply beats a nearby one")

            suite.expect(Nearby.candidates(catalog, strictFound: true, for: track, defaults: defaults).isEmpty,
                   "no second pass over a reply the strict pass already used")
            suite.expect(Nearby.candidates(nil, strictFound: false, for: track, defaults: defaults).isEmpty,
                   "a failed request gives nothing")
        }
        withDefaults(false) { defaults in
            suite.expect(Nearby.candidates(catalog, strictFound: false, for: track, defaults: defaults).isEmpty,
                   "the setting turned off leaves upstream's behavior")
        }
    }

    private static func limits(_ suite: TestSuite) {
        let track = identity("MW2", "Freeze corleone", "ADC", 283)
        withDefaults(true) { defaults in
            func kept(_ record: [String: Any]) -> [NotchLyricsSupport.Candidate] {
                Nearby.candidates(reply([record]), strictFound: false, for: track, defaults: defaults)
            }
            suite.expect(kept(record(1, "MW2", "Freeze Corleone", "ADC", 291)).count == 1,
                   "eight seconds off is still the same recording")
            let nine = kept(record(1, "MW2", "Freeze Corleone", "ADC", 292))
            suite.expect(nine.count == 1 && nine.first?.lyrics.lines.isEmpty == true && nine.first?.lyrics.plain.isEmpty == false
                && (nine.first?.score ?? 0) < (kept(record(1, "MW2", "Freeze Corleone", "ADC", 291)).first?.score ?? 0),
                   "nine seconds off, only the words show, unsynced, ranked below a near record")
            suite.expect(kept(record(1, "MW2", "Freeze Corleone", "ADC", 275)).first?.lyrics.lines.isEmpty == false
                && kept(record(1, "MW2", "Freeze Corleone", "ADC", 274)).first?.lyrics.lines.isEmpty == true,
                   "the same bound holds for a shorter catalog record")
            suite.expect(kept(record(1, "MW2", "Freeze Corleone", "ADC", 344)).isEmpty,
                   "more than a minute off is another recording: nothing")
            // Spotify plays « Réflexions basses » (XEU) for 201 s; LRCLIB has it at 170, 220, 227 and 237 s.
            let vald = identity("Réflexions basses", "Vald", "XEU", 201.27)
            let versions = reply([record(1, "Réflexions basses", "Vald", "XEU", 227), record(2, "Réflexions basses", "Vald", "XEU", 170),
                                  record(3, "Réflexions basses", "Vald", "XEU", 220), record(4, "Réflexions basses", "Vald", "XEU", 237)])
            let words = Nearby.candidates(versions, strictFound: false, for: vald, defaults: defaults)
            suite.expect(words.count == 1 && words.first?.recordID == 3 && words.first?.lyrics.lines.isEmpty == true
                && words.first?.lyrics.plain.isEmpty == false,
                   "no version near enough: the nearest one's words, without timings")
            suite.expect(kept(record(1, "MW2 (Remix)", "Freeze Corleone", "ADC", 288)).isEmpty,
                   "another version of the song stays refused")
            suite.expect(kept(record(1, "MW2", "Ninho", "ADC", 288)).isEmpty, "another artist stays refused")
            let long = kept(record(1, "MW2", "Freeze Corleone", "ADC", 290, lastLine: "04:50.00"))
            suite.expect(long.count == 1 && long.first?.lyrics.lines.count == 3
                && (long.first?.lyrics.lines.last?.time ?? 999) <= track.duration,
                   "lines timed past the song's end go; the others stay in time")
            // Spotify plays « Yacht & Champagne - Skit » for 84 s; LRCLIB's record is 90 s, its last line at 1:29.
            let skit = identity("Yacht & Champagne - Skit", "Josman", "J.000.$", 84)
            let skitRecord: [String: Any] = ["id": 5755750, "trackName": "Yacht & Champagne - Skit", "artistName": "Josman",
                                             "albumName": "J.000.$", "duration": 90.0, "instrumental": false,
                                             "syncedLyrics": "[00:01.31] Yeah\n[00:05.16] Ouais\n[01:20.00] Fin\n[01:29.01] ",
                                             "plainLyrics": "Yeah\nOuais\nFin"]
            let synced = Nearby.candidates(reply([skitRecord]), strictFound: false, for: skit, defaults: defaults).first?.lyrics
            suite.expect(synced?.lines.map(\.text) == ["Yeah", "Ouais", "Fin"] && synced?.lines.first?.time == 1.31,
                   "a record six seconds longer scrolls in time, its line past the end left out")
            suite.expect(Nearby.lineTime("[01:29.01] Yeah") == 89.01 && Nearby.lineTime("[ar:Josman]") == nil
                && Nearby.lineTime("Yeah") == nil,
                   "a line's time is read; tags and untimed lines have none")
            let noAlbum = identity("MW2", "Freeze corleone", "", 283)
            suite.expect(Nearby.candidates(reply([record(1, "MW2", "Freeze Corleone", "ADC", 288)]), strictFound: false,
                                           for: noAlbum, defaults: defaults).isEmpty,
                   "a player that names no album gets no second pass")
            suite.expect(Nearby.candidates(Data("not json".utf8), strictFound: false, for: track, defaults: defaults).isEmpty,
                   "an unreadable reply gives nothing")
        }
    }

    private static func albums(_ suite: TestSuite) {
        suite.expect(Nearby.albumKey("ADC - Single") == "adc" && Nearby.albumKey("Été 2020 - EP") == "ete2020",
               "albums compare without their single/EP suffix, case, accents or spaces")
        suite.expect(Nearby.albumKey("ADC (version CD)") != Nearby.albumKey("ADC"),
               "an edition named apart is another album")
        let track = identity("MW2", "Freeze corleone", "ADC - Single", 283)
        let data = reply([record(1, "MW2", "Freeze Corleone", "adc", 288), record(2, "MW2", "Freeze Corleone", "LMF", 288)])
        let kept = Nearby.recordsOnAlbum(data, of: track)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
        suite.expect(kept?.count == 1 && kept?.first?["id"] as? Int == 1, "only the records on the player's album go on")
    }
}
