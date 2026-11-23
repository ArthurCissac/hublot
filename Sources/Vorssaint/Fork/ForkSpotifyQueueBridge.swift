// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Reads Spotify's queue for the island's queue page, through the Web API.
///
/// Called by one line of `NotchMusicService.receiveQueue`, only when the
/// adapter answered that Spotify shares no queue, so only while the queue page
/// is open: on opening it, on a change of song, and on "Refresh". No timer, no
/// request while the page is closed. The reply it builds goes through
/// upstream's `NotchQueueSupport.decode` like the adapter's own.
final class ForkSpotifyQueueBridge {
    static let shared = ForkSpotifyQueueBridge()

    private var generation = UUID()
    private var sessions: [URLSession] = []
    /// Downloaded covers, kept across refreshes of the same queue.
    private var covers: [URL: Data] = [:]

    private init() {}

    /// The setting is on and the user is signed in.
    var isReady: Bool { ForkSpotify.isEnabled() && ForkSpotifyAuth.shared.isConnected }

    func cancel() {
        generation = UUID()
        sessions.forEach { $0.invalidateAndCancel() }
        sessions.removeAll()
    }

    /// Reads the queue for `request`, anchored on `playback`. `completion` runs
    /// on the main queue: nil when nothing could be read, then a reply, then
    /// the same reply with its covers once they have arrived.
    func load(request: UUID, playback: NotchPlayback, completion: @escaping ([String: Any]?) -> Void) {
        cancel()
        let requested = generation
        ForkSpotifyAuth.shared.accessToken { [weak self] token in
            guard let self, self.generation == requested else { return }
            guard let token else { completion(nil); return }
            self.read(token: token, request: request, playback: playback, attempts: 3, retried: false,
                      generation: requested, completion: completion)
        }
    }

    private func read(token: String, request: UUID, playback: NotchPlayback, attempts: Int, retried: Bool,
                      generation requested: UUID, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: ForkSpotify.queueEndpoint) else { completion(nil); return }
        let session = ForkSpotifyHTTP.get(url, bearer: token, maximumBytes: ForkSpotify.maximumReplyBytes) { [weak self] status, data in
            guard let self, self.generation == requested else { return }
            if status == 401, !retried {
                // Revoked before its time: refresh once, then give up.
                ForkSpotifyAuth.shared.invalidateAccessToken()
                ForkSpotifyAuth.shared.accessToken { [weak self] fresh in
                    guard let self, self.generation == requested else { return }
                    guard let fresh else { completion(nil); return }
                    self.read(token: fresh, request: request, playback: playback, attempts: attempts, retried: true,
                              generation: requested, completion: completion)
                }
                return
            }
            guard status == 200, let data, let queue = ForkSpotify.decodeQueue(data) else { completion(nil); return }
            guard ForkSpotify.matches(queue.current, playback: playback) else {
                // The service can lag a second behind the app after a change of song.
                guard attempts > 1 else { completion(nil); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self, self.generation == requested else { return }
                    self.read(token: token, request: request, playback: playback, attempts: attempts - 1,
                              retried: retried, generation: requested, completion: completion)
                }
                return
            }
            let known = self.covers.filter { url, _ in queue.upcoming.contains { $0.cover == url } }
            self.covers = known
            completion(ForkSpotify.reply(queue, request: request, playback: playback, covers: known))
            self.loadCovers(queue, request: request, playback: playback, generation: requested, completion: completion)
        }
        sessions.append(session)
    }

    private func loadCovers(_ queue: ForkSpotify.Queue, request: UUID, playback: NotchPlayback,
                            generation requested: UUID, completion: @escaping ([String: Any]?) -> Void) {
        let missing = ForkSpotify.missingCovers(queue, have: covers)
        guard !missing.isEmpty else { return }
        var remaining = missing.count
        for url in missing {
            let session = ForkSpotifyHTTP.download(url, maximumBytes: ForkSpotify.maximumCoverBytes) { [weak self] status, data in
                guard let self, self.generation == requested else { return }
                if status == 200, let data, !data.isEmpty { self.covers[url] = data }
                remaining -= 1
                guard remaining == 0 else { return }
                completion(ForkSpotify.reply(queue, request: request, playback: playback, covers: self.covers))
            }
            sessions.append(session)
        }
    }
}
