// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Background sound: the mixes, favourites, Pomodoro, the automatic pause,
/// the panel, the island and the synthesis itself.
enum ForkAmbientTests {
    static func run(_ suite: TestSuite) {
        mixes(suite)
        timers(suite)
        placesAndIsland(suite)
        noises(suite)
        tones(suite)
    }

    private static func mixes(_ suite: TestSuite) {
        typealias Logic = ForkAmbientLogic

        suite.expect(Logic.Sound.allCases.count == 16
            && Logic.Family.allCases.allSatisfy { family in Logic.Sound.allCases.contains { $0.family == family } },
                     "sixteen sounds in four families: noises, nature, binaural, music")
        suite.expect(Logic.Sound.allCases.filter(\.needsHeadphones) == [.alpha, .beta] && !Logic.Sound.gamma.needsHeadphones,
                     "the binaural beats need headphones, the 40 Hz pulse does not")
        let mix: Logic.Mix = [.rain: 0.3, .brown: 0.6, .wind: 0]
        suite.expect(Logic.encode(mix) == "brown=0.60,rain=0.30"
            && Logic.decode("brown=0.60,rain=0.30") == [.brown: 0.6, .rain: 0.3]
            && Logic.decode("thunderstorm=1,rain=2,ocean=x,wind") == [.rain: 1],
                     "a mix is stored in the sounds' order; unknown or broken parts are dropped")

        suite.expect(Logic.preset(for: [.brown: 0.6, .rain: 0.3]) == .focus
            && Logic.preset(for: [.forest: 0.55, .stream: 0.45]) == .nature
            && Logic.preset(for: [.brown: 0.6]) == nil,
                     "a mix is recognised as a ready-made ambience, or is the user's own")
        suite.expect(Logic.Preset.allCases.count == 6 && Logic.Preset.allCases.allSatisfy { !$0.mix.isEmpty },
                     "six ready-made ambiences, each with sounds")

        let first = Logic.Favorite(id: UUID(), name: "Matin", mix: "brown=0.50")
        let stored = Logic.stored([first, Logic.Favorite(id: UUID(), name: "Vide", mix: "")])
        suite.expect(Logic.favorites(stored: stored) == [first] && Logic.favorites(stored: "nonsense").isEmpty
            && Logic.favorites(stored: nil).isEmpty,
                     "favourites are kept by name; an empty one or a broken list is dropped")
        suite.expect(Logic.uniqueName("Matin", among: [first]) == "Matin 2"
            && Logic.uniqueName("Soir", among: [first]) == "Soir",
                     "two favourites never share a name")
    }

    private static func timers(_ suite: TestSuite) {
        typealias Logic = ForkAmbientLogic

        suite.expect(Logic.fadeFactor(remaining: nil) == 1 && Logic.fadeFactor(remaining: 600) == 1
            && Logic.fadeFactor(remaining: 5) == 0.5 && Logic.fadeFactor(remaining: -3) == 0
            && Logic.clock(1445) == "24:05",
                     "full until the last ten seconds, then down to silence; the time left reads minutes and seconds")

        suite.expect(Logic.duration(of: .work, workMinutes: 25) == 1500
            && Logic.duration(of: .shortBreak, workMinutes: 25) == 300
            && Logic.duration(of: .longBreak, workMinutes: 25) == 900
            && Logic.duration(of: .shortBreak, workMinutes: 50) == 600
            && Logic.duration(of: .work, workMinutes: 7) == 1500,
                     "Pomodoro: 25 or 50 minutes of work, a fifth of it as a break, a long break of 15 or 20")
        var phase = Logic.Phase.work
        var done = 0
        var phases: [Logic.Phase] = []
        for _ in 0..<8 {
            let next = Logic.next(after: phase, completedWork: done)
            phase = next.phase
            done = next.completedWork
            phases.append(phase)
        }
        suite.expect(phases == [.shortBreak, .work, .shortBreak, .work, .shortBreak, .work, .longBreak, .work] && done == 4,
                     "a long break after every fourth work session")
        suite.expect(Logic.soundsDuring(.work) && Logic.soundsDuring(nil) && !Logic.soundsDuring(.shortBreak),
                     "the sound plays during work and is quiet during breaks")

        suite.expect(Logic.holds(microphoneInUse: true, musicPlaying: false, pauseForCalls: true, pauseForMusic: true)
            && Logic.holds(microphoneInUse: false, musicPlaying: true, pauseForCalls: true, pauseForMusic: true)
            && !Logic.holds(microphoneInUse: true, musicPlaying: true, pauseForCalls: false, pauseForMusic: false)
            && !Logic.holds(microphoneInUse: false, musicPlaying: false, pauseForCalls: true, pauseForMusic: true),
                     "the sound holds during a call or while music plays, each when wanted")
    }

    private static func placesAndIsland(_ suite: TestSuite) {
        typealias Logic = ForkAmbientLogic
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let middle = Logic.panelFrame(size: CGSize(width: 340, height: 420), clickX: 800, visibleFrame: screen)
        let edge = Logic.panelFrame(size: CGSize(width: 340, height: 420), clickX: 1500, visibleFrame: screen)
        suite.expect(middle == CGRect(x: 630, y: 518, width: 340, height: 420) && edge.maxX == 1504 && edge.maxY == 938,
                     "the panel hangs just under the menu bar, centred on the click and kept on screen")

        suite.expect(Logic.hiddenControls("timer,panel", showing: false) == "timer,panel,ambient"
            && Logic.hiddenControls("timer,ambient,panel", showing: true) == "timer,panel"
            && Logic.isShownInIsland("timer,panel") && !Logic.isShownInIsland("ambient"),
                     "showing or hiding the island control edits only its own place in the hidden list")
        let name = "ForkAmbientTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("timer,ambient", forKey: DefaultsKey.notchHiddenControls)
        Logic.showIslandControlOnce(in: defaults)
        let first = defaults.string(forKey: DefaultsKey.notchHiddenControls)
        defaults.set("timer,ambient", forKey: DefaultsKey.notchHiddenControls)
        Logic.showIslandControlOnce(in: defaults)
        suite.expect(first == "timer" && defaults.string(forKey: DefaultsKey.notchHiddenControls) == "timer,ambient",
                     "the island control is shown once by default; hiding it afterwards stays the user's choice")
        suite.expect(Logic.showsIslandActivity(playing: true, wanted: true, featureOn: true)
            && !Logic.showsIslandActivity(playing: false, wanted: true, featureOn: true)
            && !Logic.showsIslandActivity(playing: true, wanted: false, featureOn: true),
                     "the closed island shows the wave only while the sound plays, if wanted")
        suite.expect(Logic.waveWidth(bars: 4, height: 12) == 13 && Logic.waveWidth(bars: 4, height: 20) == 21
            && Logic.waveWidth(bars: 0, height: 20) == 0,
                     "the island's wave is four bars and their gaps wide")
        let island = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                   safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 100)
        let open = island.compactTimerGeometry(showsDownloads: false, wing: Logic.stripWing(reading: nil, in: island))
        let timed = island.compactTimerGeometry(showsDownloads: false, wing: Logic.stripWing(reading: "25min", in: island))
        suite.expect(open.compactActivitySize.width == 180 + 2 * NotchTimerSupport.stripWingRange.lowerBound
            && open.compactActivitySize.width < timed.compactActivitySize.width
            && Logic.islandStripWing(island) == Logic.stripWing(reading: nil, in: island),
                     "without a time limit the island narrows to the wave; a time left widens it to fit")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkAmbientShortcutEnabled] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkAmbientIslandActivity] as? Bool == true
            && Logic.decode(Defaults.registeredDefaults[DefaultsKey.forkAmbientMix] as? String) == Logic.defaultMix,
                     "the shortcut and the island wave are on by default, the first mix is « focus »")
    }

    private static let rate = 22_050.0

    private static func render(_ sound: ForkAmbientLogic.Sound, seconds: Double) -> (left: [Float], right: [Float]) {
        var synth = ForkAmbientSynth(sampleRate: rate)
        synth.setLevel(1, for: sound)
        synth.setMaster(1)
        for _ in 0..<Int(rate * 0.5) { _ = synth.next() }  // the glide settles
        var left: [Float] = [], right: [Float] = []
        for _ in 0..<Int(rate * seconds) {
            let value = synth.next()
            left.append(value.0)
            right.append(value.1)
        }
        return (left, right)
    }

    private static func crossings(_ samples: [Float]) -> Int {
        zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    private static func rms(_ samples: ArraySlice<Float>) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
    }

    private static func noises(_ suite: TestSuite) {
        var silent = ForkAmbientSynth(sampleRate: rate)
        silent.setLevel(1, for: .rain)
        var loudest: Float = 0
        for _ in 0..<2_000 { loudest = max(loudest, abs(silent.next().0)) }
        suite.expect(loudest == 0, "nothing is heard with the master volume at zero")

        let white = render(.white, seconds: 1).left, pink = render(.pink, seconds: 1).left
        let brown = render(.brown, seconds: 1).left
        suite.expect(crossings(white) > crossings(pink) && crossings(pink) > crossings(brown),
                     "white noise is the brightest, brown the deepest, pink between")

        let rain = render(.rain, seconds: 1).left, fire = render(.fire, seconds: 2).left
        let crest: ([Float]) -> Float = { ($0.map(abs).max() ?? 0) / max(rms($0[...]), 0.0001) }
        suite.expect(crest(rain) > 3 && crest(fire) > 3, "rain has droplets and fire crackles: peaks well above their bed")

        let ocean = render(.ocean, seconds: 14).left
        let window = Int(rate / 2)
        let levels = stride(from: 0, to: ocean.count - window, by: window).map { rms(ocean[$0..<($0 + window)]) }
        suite.expect((levels.max() ?? 0) > 2 * max(levels.min() ?? 1, 0.0001), "the ocean swells and ebbs in waves")
    }

    private static func tones(_ suite: TestSuite) {
        var withinRange = true
        var heard = true
        for sound in ForkAmbientLogic.Sound.allCases {
            let samples = render(sound, seconds: 1.5)
            if (samples.left + samples.right).contains(where: { abs($0) >= 1 || $0.isNaN }) { withinRange = false }
            if rms(samples.left[...]) + rms(samples.right[...]) < 0.002 { heard = false }
        }
        suite.expect(withinRange && heard, "every sound is heard and stays within the speaker's range")

        let alpha = render(.alpha, seconds: 1)
        let beats = crossings(alpha.right) - crossings(alpha.left)
        suite.expect((15...25).contains(beats), "alpha: the right ear is 10 Hz above the left, which the brain hears as a beat")

        let gamma = render(.gamma, seconds: 0.5).left
        let slice = Int(rate / 160)
        let pulses = stride(from: 0, to: gamma.count - slice, by: slice).map { rms(gamma[$0..<($0 + slice)]) }
        suite.expect((pulses.max() ?? 0) > 4 * max(pulses.min() ?? 1, 0.0001) && gamma == render(.gamma, seconds: 0.5).right,
                     "the 40 Hz tone pulses, the same in both ears")

        var bell = ForkAmbientSynth(sampleRate: rate)
        bell.ringChime()
        var chime: Float = 0
        for _ in 0..<Int(rate / 4) { chime = max(chime, abs(bell.next().0)) }
        suite.expect(chime > 0.02, "the Pomodoro chime is heard even with the mix silent")

        let forest = render(.forest, seconds: 3)
        suite.expect(forest.left != forest.right && rms(forest.left[...]) > 0.002,
                     "birds sing from one side or the other over the rustling leaves")
    }
}
