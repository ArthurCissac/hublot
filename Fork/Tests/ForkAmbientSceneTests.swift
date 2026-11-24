// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

enum ForkAmbientSceneTests {
    typealias Logic = ForkAmbientLogic

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.sceneSound(for: Logic.Preset.nature.mix) == .forest
            && Logic.sceneSound(for: Logic.Preset.storm.mix) == .thunder
            && Logic.sceneSound(for: Logic.Preset.focus.mix) == .rain
            && Logic.sceneSound(for: Logic.Preset.deepFocus.mix) == .beta
            && Logic.sceneSound(for: Logic.Preset.calm.mix) == .ocean
            && Logic.sceneSound(for: Logic.Preset.lofi.mix) == .chords,
                     "a ready-made ambience shows its emblem")
        suite.expect(Logic.sceneSound(for: [.fire: 0.7, .rain: 0.3]) == .fire
            && Logic.sceneSound(for: [.wind: 0.2, .bowls: 0.9, .white: 0.5]) == .bowls,
                     "any other mix shows its loudest sound")
        suite.expect(Logic.sceneSound(for: [.stream: 0.5, .fire: 0.5]) == .fire,
                     "a tie goes to the sound listed first")
        suite.expect(Logic.sceneSound(for: [:]) == nil && Logic.sceneSound(for: [.fire: 0]) == nil,
                     "nothing playing, no scene")
        suite.expect(Set(Logic.Preset.allCases.map(Logic.emblem(of:))).count == Logic.Preset.allCases.count,
                     "each ambience has its own emblem")

        suite.expect(Logic.sceneWidth(height: 20) == 26 && Logic.sceneWidth(height: 10) == 13
            && Logic.sceneWidth(height: -4) == 0,
                     "a scene is 1.3 times as wide as tall")
        suite.expect(Logic.sceneCanvas.width / Logic.sceneCanvas.height == Logic.sceneAspect,
                     "the drawings' units keep the box's shape")

        let cycles = stride(from: -7.0, through: 40, by: 0.37).map { Logic.cycle($0, period: 3.2, offset: 0.4) }
        suite.expect(cycles.allSatisfy { $0 >= 0 && $0 < 1 }, "a cycle stays from 0 up to 1, before zero too")
        suite.expect(abs(Logic.cycle(1.6, period: 3.2) - 0.5) < 1e-9 && Logic.cycle(5, period: 0) == 0
            && Logic.cycle(.infinity, period: 2) == 0,
                     "a cycle is the share of the period gone")

        let flashes = stride(from: 0.0, to: 3.4, by: 0.01).map(Logic.lightning)
        suite.expect(flashes.allSatisfy { $0 >= 0 && $0 <= 1 }, "lightning stays from 0 to 1")
        suite.expect(Logic.lightning(0.01) == 1 && Logic.lightning(2) == 0
            && Double(flashes.filter { $0 == 0 }.count) / Double(flashes.count) > 0.7,
                     "lightning flashes briefly, dark most of the time")
        suite.expect(Logic.birdSings(0.2) && !Logic.birdSings(3.0) && Logic.birdSings(3.4),
                     "the bird sings, rests, sings again")

        let grains = (0..<7).flatMap { column in (0..<5).map { Logic.grain(column: column, row: $0, frame: 12) } }
        suite.expect(grains.allSatisfy { $0 >= 0 && $0 <= 1 } && Set(grains.map { ($0 * 10).rounded() }).count > 4,
                     "the snow's dots vary from 0 to 1")
        suite.expect(Logic.grain(column: 3, row: 2, frame: 9) == Logic.grain(column: 3, row: 2, frame: 9)
            && (0..<20).contains { Logic.grain(column: 3, row: 2, frame: $0) != Logic.grain(column: 3, row: 2, frame: 0) },
                     "a dot holds within a frame and changes between frames")

        suite.expect(Logic.trip(0) == 0 && abs(Logic.trip(0.5) - 1) < 1e-9 && Logic.trip(1) < 1e-9
            && Logic.trip(-1) == 0 && Logic.trip(2) < 1e-9,
                     "a moving piece fades in, then out")

        let island = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                   safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 100)
        let wave = Logic.stripWing(reading: nil, in: island)
        let scene = Logic.stripWing(reading: nil, scenes: true, in: island)
        let height = island.compactTimerGeometry(showsDownloads: false, wing: NotchTimerSupport.stripWingRange.lowerBound)
            .compactActivityContentHeight
        suite.expect(scene >= wave && scene >= Logic.sceneWidth(height: NotchTimerSupport.stripIconSize(height: height)),
                     "the wings fit the scene, wider than the wave")
        suite.expect(Logic.stripWing(reading: "25min", scenes: true, in: island) >= scene,
                     "a time left still widens the island")
        suite.expect(Logic.markRadius(height: 20, scenes: false) == 10 && Logic.markRadius(height: 20, scenes: true) == 5,
                     "a scene's box is less round than the wave's bars")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkAmbientScenes] as? Bool == true,
                     "the scenes show by default")
    }
}
