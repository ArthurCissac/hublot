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
        return NotchLyricsSupport.searchCandidates(sameAlbum, for: track, durationTolerance: tolerance,
                                                   verifiedArtistAliases: verifiedArtistAliases)
            .map { NotchLyricsSupport.Candidate(lyrics: $0.lyrics, score: $0.score - penalty, distance: $0.distance,
                                                recordID: $0.recordID, stableKey: $0.stableKey) }
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
