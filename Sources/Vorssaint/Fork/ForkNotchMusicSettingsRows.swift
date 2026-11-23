// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The fork's lyrics setting, placed by one line in upstream's island settings,
/// under "Look up lyrics online" and indented like it.
struct ForkLyricsSettingsRow: View {
    @AppStorage(DefaultsKey.forkLyricsNearbyDuration) private var nearbyDuration = true

    var body: some View {
        let text = ForkMusicStrings.current
        ForkOptionRow(symbol: "timer", title: text.nearbyDurationToggle, caption: text.nearbyDurationCaption) {
            Toggle(text.nearbyDurationToggle, isOn: $nearbyDuration).labelsHidden().toggleStyle(.switch)
        }
        .padding(.leading, settingsRowTextInset)
    }
}

/// Spotify's queue: the switch, the client ID of the user's own Spotify app,
/// and signing in. Placed by one line under upstream's queue switch.
struct ForkSpotifyQueueSettingsRows: View {
    @AppStorage(DefaultsKey.forkSpotifyQueue) private var enabled = false
    @AppStorage(DefaultsKey.forkSpotifyClientID) private var clientID = ""
    @ObservedObject private var auth = ForkSpotifyAuth.shared

    var body: some View {
        let text = ForkMusicStrings.current
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = ForkSpotify.isValidClientID(trimmed)
        VStack(alignment: .leading, spacing: 8) {
            ForkOptionRow(symbol: "music.note.list", title: text.spotifyToggle,
                        caption: text.spotifyCaption(AppInfo.name, ForkSpotify.redirectURI)) {
                Toggle(text.spotifyToggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                ForkOptionRow(symbol: "key", title: text.clientID,
                            caption: trimmed.isEmpty || valid ? text.clientIDHint : text.clientIDInvalid) {
                    TextField(text.clientID, text: $clientID, prompt: Text(text.clientIDPrompt))
                        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 260)
                        .font(.system(.body, design: .monospaced))
                }
                ForkOptionRow(symbol: "person.crop.circle", title: text.account, caption: status(text)) {
                    if auth.state == .connected {
                        Button(text.disconnect) { auth.disconnect() }
                    } else {
                        Button(text.connect) { auth.connect() }.disabled(!valid || auth.state == .waiting)
                    }
                }
            }
        }
        .padding(.leading, settingsRowTextInset)
    }

    private func status(_ text: ForkMusicStrings) -> String {
        switch auth.state {
        case .connected: return text.connected
        case .waiting: return text.waiting
        case .failed: return text.failed
        case .disconnected: return text.notConnected
        }
    }
}

/// On the island's empty queue page, while Spotify plays and its queue is
/// set up but not signed in: the button that signs in.
struct ForkSpotifyConnectButton: View {
    let playback: NotchPlayback
    @AppStorage(DefaultsKey.forkSpotifyQueue) private var enabled = false
    @AppStorage(DefaultsKey.forkSpotifyClientID) private var clientID = ""
    @ObservedObject private var auth = ForkSpotifyAuth.shared

    var body: some View {
        let text = ForkMusicStrings.current
        if enabled, ForkSpotify.isSpotify(playback), ForkSpotify.isEnabled(), auth.state != .connected {
            NotchPillButton(title: auth.state == .waiting ? text.waiting : text.connect, prominent: true) {
                auth.connect()
            }
            .disabled(auth.state == .waiting)
            .onChange(of: auth.state) { _, state in
                if state == .connected { NotchMusicService.shared.refreshQueue() }
            }
        }
    }
}
