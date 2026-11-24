// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// A second, looser pass over an LRCLIB search reply, for a recording whose
/// length differs a little from the catalog's.
///
/// Upstream accepts a catalog record only within two seconds of the playing
/// song. Spotify often reports a length a few seconds away from Apple Music's,
/// which most LRCLIB records come from: "MW2" by Freeze Corleone plays for
/// 282.9 s on Spotify while all five of its records say 288 s, so the island
/// found nothing although every record carried synchronized lyrics.
///
/// The pass runs only when the strict one found nothing in the same reply, and
/// it never relaxes anything but the length: title, credits, recording kind
/// (live, remix…) are checked by upstream's own matcher, and the album must be
/// the one the player names. A player that names no album gets no second pass.
/// Its candidates rank below any strict one, so a record found strictly in a
/// later reply still wins. Synchronized lines that run past the song are
/// dropped by upstream's matcher, which then keeps the plain text.
enum ForkLyricsNearbyDuration {
    /// The largest difference accepted, in seconds. Upstream's offset buttons
    /// shift lyrics by up to ten seconds if the difference sits at the start.
    static let tolerance: Double = 8
    /// Taken off each candidate's score, far more than any score upstream gives.
    static let penalty = 1_000

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkLyricsNearbyDuration)
    }

    /// Candidates of `data`, a reply of `/api/search`, a few seconds off the
    /// song. Empty when the pass is off, when the strict pass found something
    /// (`strictFound`), or when nothing matches.
    static func candidates(_ data: Data?, strictFound: Bool, for track: NotchMusicIdentity,
                           verifiedArtistAliases: [String] = [],
                           defaults: UserDefaults = .standard) -> [NotchLyricsSupport.Candidate] {
        guard !strictFound, let data, isEnabled(in: defaults),
              let sameAlbum = recordsOnAlbum(data, of: track) else { return [] }
        // A record a few seconds longer often runs on past the song's end:
        // its lines past the end go, so the rest stays in time.
        let near = NotchLyricsSupport.searchCandidates(trimmed(sameAlbum, to: track.duration), for: track,
                                                       durationTolerance: tolerance,
                                                       verifiedArtistAliases: verifiedArtistAliases)
        if !near.isEmpty { return near.map { lowered($0, by: penalty) } }
        // Nothing within eight seconds: the nearest record of the album gives
        // its words, without timings that belong to another length.
        guard let plain = nearestPlain(sameAlbum, of: track) else { return [] }
        return NotchLyricsSupport.searchCandidates(plain, for: track, durationTolerance: tolerance,
                                                   verifiedArtistAliases: verifiedArtistAliases)
            .map { lowered($0, by: 2 * penalty) }
    }

    private static func lowered(_ candidate: NotchLyricsSupport.Candidate, by amount: Int) -> NotchLyricsSupport.Candidate {
        NotchLyricsSupport.Candidate(lyrics: candidate.lyrics, score: candidate.score - amount, distance: candidate.distance,
                                     recordID: candidate.recordID, stableKey: candidate.stableKey)
    }

    /// The records with their timed lines past `duration` left out; tags and
    /// untimed lines stay. Upstream refuses every timed line of a record whose
    /// last one runs past the song, which left a record six seconds longer
    /// as plain text although the rest of its lines were in time.
    static func trimmed(_ data: Data, to duration: Double) -> Data {
        guard duration > 0, let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return data }
        let kept = records.map { record -> [String: Any] in
            guard let synced = record["syncedLyrics"] as? String, !synced.isEmpty else { return record }
            var copy = record
            copy["syncedLyrics"] = synced.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in lineTime(line).map { $0 <= duration } ?? true }
                .joined(separator: "\n")
            return copy
        }
        return (try? JSONSerialization.data(withJSONObject: kept)) ?? data
    }

    /// The time of a line such as « [01:29.01] Yeah », in seconds; nil for a
    /// tag such as « [ar:Josman] » or a line without a time.
    static func lineTime<Line: StringProtocol>(_ line: Line) -> Double? {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
        guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]),
              minutes >= 0, seconds >= 0 else { return nil }
        return minutes * 60 + seconds
    }

    /// Beyond this many seconds off, a record is taken for another recording.
    static let plainReach: Double = 60

    /// The album's record nearest in length that has plain words, its
    /// synchronized lines dropped and its length set to the song's, so
    /// upstream's matcher shows it as plain text. Nil when none is near.
    static func nearestPlain(_ data: Data, of track: NotchMusicIdentity) -> Data? {
        guard let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        func gap(_ record: [String: Any]) -> Double? {
            (record["duration"] as? Double).map { abs($0 - track.duration) }
        }
        let usable = records.filter { record in
            let words = (record["plainLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !words.isEmpty && (gap(record).map { $0 <= plainReach } ?? false)
        }
        guard var nearest = usable.min(by: { (gap($0) ?? .infinity) < (gap($1) ?? .infinity) }) else { return nil }
        nearest["syncedLyrics"] = ""
        nearest["duration"] = track.duration
        return try? JSONSerialization.data(withJSONObject: [nearest])
    }

    /// The reply's records on the player's album, re-encoded for upstream's
    /// matcher, which applies its own size and count limits again.
    static func recordsOnAlbum(_ data: Data, of track: NotchMusicIdentity) -> Data? {
        let expected = albumKey(track.album)
        guard !expected.isEmpty, data.count <= NotchLyricsSupport.maximumSearchBytes,
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let kept = records.filter { ($0["albumName"] as? String).map(albumKey) == expected }
        guard !kept.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: kept)
    }

    /// An album name without its "- Single" or "- EP" suffix, case, accents,
    /// spaces and punctuation, as upstream compares albums.
    static func albumKey(_ album: String) -> String {
        NotchLyricsSupport.catalogAlbum(album)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}
