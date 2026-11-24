// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Background sound to work with: noises, nature, binaural tones and soft
/// music made live by the app (see `ForkAmbientSynth`), no file, no network.
/// Pure: the sounds, their mixes, the ambiences and favourites, the timer and
/// Pomodoro, the automatic pause, the panel's place and the island control.
enum ForkAmbientLogic {
    enum Family: String, CaseIterable, Identifiable {
        case noise, nature, binaural, music
        var id: String { rawValue }
    }

    enum Sound: String, CaseIterable, Identifiable {
        case white, pink, brown, rain, ocean, wind, fire, forest, stream, thunder, alpha, beta, gamma, chords, drone, bowls

        var id: String { rawValue }

        var family: Family {
            switch self {
            case .white, .pink, .brown: return .noise
            case .rain, .ocean, .wind, .fire, .forest, .stream, .thunder: return .nature
            case .alpha, .beta, .gamma: return .binaural
            case .chords, .drone, .bowls: return .music
            }
        }

        /// Made of tones and events rather than filtered noise alone.
        var isTonal: Bool {
            family == .binaural || family == .music || self == .forest || self == .stream || self == .thunder
        }

        /// The two ears get different tones: only heard as a beat in headphones.
        var needsHeadphones: Bool { self == .alpha || self == .beta }

        var symbol: String {
            switch self {
            case .white: return "waveform"
            case .pink: return "waveform.path"
            case .brown: return "waveform.path.ecg"
            case .rain: return "cloud.rain"
            case .ocean: return "water.waves"
            case .wind: return "wind"
            case .fire: return "flame"
            case .forest: return "leaf"
            case .stream: return "drop"
            case .thunder: return "cloud.bolt.rain"
            case .alpha: return "headphones"
            case .beta: return "brain.head.profile"
            case .gamma: return "dot.radiowaves.left.and.right"
            case .chords: return "music.note"
            case .drone: return "tuningfork"
            case .bowls: return "bell"
            }
        }
    }

    /// Each sound's level, from 0 to 1; a sound absent is silent.
    typealias Mix = [Sound: Double]

    /// "brown=0.60,rain=0.30", in the sounds' order; silent sounds left out.
    static func encode(_ mix: Mix) -> String {
        Sound.allCases.compactMap { sound in
            guard let level = mix[sound], level > 0 else { return nil }
            return "\(sound.rawValue)=\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), min(1, level)))"
        }
        .joined(separator: ",")
    }

    /// Unknown sounds and broken parts are dropped; levels kept within 0…1.
    static func decode(_ text: String?) -> Mix {
        var mix: Mix = [:]
        for part in (text ?? "").split(separator: ",") {
            let pieces = part.split(separator: "=")
            guard pieces.count == 2, let sound = Sound(rawValue: String(pieces[0])),
                  let level = Double(pieces[1]), level > 0 else { continue }
            mix[sound] = min(1, level)
        }
        return mix
    }

    static func sameMix(_ first: Mix, _ second: Mix) -> Bool {
        Set(first.keys) == Set(second.keys) && first.allSatisfy { abs($0.value - (second[$0.key] ?? 0)) < 0.01 }
    }

    /// Ready-made ambiences.
    enum Preset: String, CaseIterable, Identifiable {
        case focus, deepFocus, calm, nature, storm, lofi

        var id: String { rawValue }

        var mix: Mix {
            switch self {
            case .focus: return [.brown: 0.6, .rain: 0.3]
            case .deepFocus: return [.brown: 0.35, .beta: 0.4]
            case .calm: return [.ocean: 0.65, .wind: 0.3]
            case .nature: return [.forest: 0.55, .stream: 0.45]
            case .storm: return [.rain: 0.75, .thunder: 0.6, .wind: 0.35]
            case .lofi: return [.chords: 0.5, .rain: 0.25]
            }
        }

        var symbol: String {
            switch self {
            case .focus: return "scope"
            case .deepFocus: return "brain.head.profile"
            case .calm: return "water.waves"
            case .nature: return "leaf"
            case .storm: return "cloud.bolt.rain"
            case .lofi: return "music.note"
            }
        }
    }

    /// Played the first time, before anything is chosen.
    static let defaultMix: Mix = Preset.focus.mix

    /// The ready-made ambience a mix is, if any.
    static func preset(for mix: Mix) -> Preset? {
        Preset.allCases.first { sameMix($0.mix, mix) }
    }

    // MARK: - Favourites

    /// A mix kept under a name.
    struct Favorite: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var mix: String

        var sounds: Mix { ForkAmbientLogic.decode(mix) }
    }

    static func favorites(stored: String?) -> [Favorite] {
        guard let data = stored?.data(using: .utf8),
              let list = try? JSONDecoder().decode([Favorite].self, from: data) else { return [] }
        return list.filter { !$0.sounds.isEmpty }
    }

    static func stored(_ favorites: [Favorite]) -> String {
        guard let data = try? JSONEncoder().encode(favorites) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// "My mix", then "My mix 2", "My mix 3"… so no two favourites share a name.
    static func uniqueName(_ base: String, among favorites: [Favorite]) -> String {
        let names = Set(favorites.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: - Timer and Pomodoro

    /// Plays until stopped or for a time, or in Pomodoro cycles.
    enum Mode: String, CaseIterable { case timer, pomodoro }

    /// The timer's choices, in minutes; 0 never stops.
    static let timerChoices = [0, 25, 50, 90]

    /// The sound fades out over its last seconds.
    static let fadeOut: TimeInterval = 10

    /// How loud the sound is with `remaining` seconds left: whole until the
    /// fade, then down to silence at the end. No end, no fade.
    static func fadeFactor(remaining: TimeInterval?) -> Double {
        guard let remaining else { return 1 }
        return min(1, max(0, remaining / fadeOut))
    }

    /// "24:05" for the panel and the island.
    static func clock(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    enum Phase: String { case work, shortBreak, longBreak }

    /// Work lasts 25 or 50 minutes; a break a fifth of it, a long break
    /// after every fourth work session.
    static let pomodoroChoices = [25, 50]
    static let roundsBeforeLongBreak = 4

    static func duration(of phase: Phase, workMinutes: Int) -> TimeInterval {
        let work = Double(pomodoroChoices.contains(workMinutes) ? workMinutes : 25)
        switch phase {
        case .work: return work * 60
        case .shortBreak: return work / 5 * 60
        case .longBreak: return (work == 50 ? 20 : 15) * 60
        }
    }

    /// The phase after this one, and how many work sessions are behind.
    static func next(after phase: Phase, completedWork: Int) -> (phase: Phase, completedWork: Int) {
        switch phase {
        case .work:
            let done = completedWork + 1
            return (done % roundsBeforeLongBreak == 0 ? .longBreak : .shortBreak, done)
        case .shortBreak, .longBreak:
            return (.work, completedWork)
        }
    }

    /// Sound plays during work only; breaks are quiet.
    static func soundsDuring(_ phase: Phase?) -> Bool { phase == nil || phase == .work }

    // MARK: - Automatic pause

    /// The sound holds during a call (the microphone in use) or while music
    /// plays, each when wanted.
    static func holds(microphoneInUse: Bool, musicPlaying: Bool, pauseForCalls: Bool, pauseForMusic: Bool) -> Bool {
        (pauseForCalls && microphoneInUse) || (pauseForMusic && musicPlaying)
    }

    // MARK: - The panel

    /// The panel hangs just under the menu bar, centred on where it was
    /// clicked and kept on screen. The status item's own frame is not used:
    /// on recent macOS it can lie, which once dropped the panel far below.
    static func panelFrame(size: CGSize, clickX: CGFloat, visibleFrame: CGRect, gap: CGFloat = 6,
                           margin: CGFloat = 8) -> CGRect {
        let lowest = visibleFrame.minX + margin
        let highest = max(lowest, visibleFrame.maxX - margin - size.width)
        let x = min(max(clickX - size.width / 2, lowest), highest)
        return CGRect(x: x, y: visibleFrame.maxY - gap - size.height, width: size.width, height: size.height)
    }

    // MARK: - The island

    /// The feature's name where upstream's island lists it (its controls,
    /// its activities); the same as ForkAmbientStrings.title, kept here for
    /// the island code that the tests compile.
    static func title(french: Bool) -> String { french ? "Bruit de fond" : "Background sound" }

    /// The island control's identifier among upstream's controls.
    static let islandControlID = "ambient"
    static let islandSymbol = "waveform"

    /// Play and pause from anywhere: Control-Option-B.
    static let defaultShortcut = GlobalShortcut(keyCode: 11, modifiers: [.control, .option])

    /// The control exists while the feature is on.
    static func islandControlAvailable(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkAmbientEnabled)
    }

    /// Its own page among the island's, while the feature is on.
    static let pageSymbol = islandSymbol

    static func pageAvailable(in defaults: UserDefaults) -> Bool { islandControlAvailable(in: defaults) }

    /// What the page shows, for the island's content settings.
    static func pageSummary(french: Bool) -> String {
        french ? "Le bruit de fond en cours : lecture, volume, ambiances et volume de chaque son."
            : "The background sound playing: play, volume, ambiences and each sound's level."
    }

    /// The island's hidden controls with this one shown or hidden.
    static func hiddenControls(_ saved: String, showing: Bool) -> String {
        var hidden = saved.split(separator: ",").map(String.init).filter { $0 != islandControlID }
        if !showing { hidden.append(islandControlID) }
        return hidden.joined(separator: ",")
    }

    /// The control is shown by default; once, it is taken off a saved list
    /// of hidden controls (an earlier version hid it as it arrived).
    static func showIslandControlOnce(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.forkAmbientIslandShown) else { return }
        defaults.set(true, forKey: DefaultsKey.forkAmbientIslandShown)
        guard let saved = defaults.string(forKey: DefaultsKey.notchHiddenControls) else { return }
        defaults.set(hiddenControls(saved, showing: true), forKey: DefaultsKey.notchHiddenControls)
    }

    static func isShownInIsland(_ hidden: String) -> Bool {
        !hidden.split(separator: ",").contains(Substring(islandControlID))
    }

    /// Set by the player at launch, read by upstream's island code (which the
    /// tests compile without the player): whether the closed island shows the
    /// wave now, and what it reads on the right. Upstream does the same for
    /// its keyboard light (`NotchControlItem.keyboardLightIsSupported`).
    static var islandActivityShown: () -> Bool = { false }
    static var islandReading: (AppLanguage) -> String? = { _ in nil }

    /// The closed island shows the wave while a session runs, if wanted.
    static func showsIslandActivity(playing: Bool, wanted: Bool, featureOn: Bool) -> Bool {
        playing && wanted && featureOn
    }
}
