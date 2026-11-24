// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The Care window's animated backgrounds (ForkCareMotionLogic).
enum ForkCareHubMotionTests {
    typealias Logic = ForkCareMotionLogic

    static func run(_ suite: TestSuite) {
        let tall = Logic.fillRect(in: CGSize(width: 840, height: 700))
        suite.expect(abs(tall.height - 700) < 0.001 && abs(tall.width - 700 * 16 / 9) < 0.001 && tall.midX == 420,
               "a narrow window keeps the picture's height and crops its sides around the centre")
        let wide = Logic.fillRect(in: CGSize(width: 1600, height: 600))
        suite.expect(abs(wide.width - 1600) < 0.001 && abs(wide.midY - 300) < 0.001,
               "a wide one keeps its width and crops top and bottom")
        suite.expect(Logic.fillRect(in: .zero) == .zero, "no size, no picture")
        let centre = Logic.point(CGPoint(x: 0.5, y: 0.5), in: tall)
        suite.expect(abs(centre.x - 420) < 0.001 && abs(centre.y - 350) < 0.001,
               "the picture's centre is the window's")

        suite.expect(Logic.targetEnergy(working: true) == 1 && Logic.targetEnergy(working: false) < 0.5,
               "the motion is calm at rest and livelier while working")
        let halfway = Logic.eased(0.32, towards: 1, elapsed: 0.6)
        suite.expect(halfway > 0.32 && halfway < 1 && Logic.eased(0.5, towards: 1, elapsed: 0) == 0.5,
               "the energy eases towards its target rather than jumping")

        var clock = Logic.Clock()
        clock.advance(to: 10, working: false)
        let start = clock.phase
        clock.advance(to: 10.1, working: false)
        let calm = clock.phase - start
        for step in 1...30 { clock.advance(to: 10.1 + Double(step) * 0.1, working: true) }
        let before = clock.phase
        clock.advance(to: 13.2, working: true)
        suite.expect(start == 0 && calm > 0 && clock.phase - before > calm * 2,
               "working makes the motion run faster")
        let resumed = clock.phase
        clock.advance(to: 500, working: true)
        suite.expect(clock.phase - resumed < 1,
               "after the window was hidden a long time, the motion picks up where it was")

        suite.expect(Logic.sweep(phase: 1, period: 10, crossing: 4) == 0.25
            && Logic.sweep(phase: 6, period: 10, crossing: 4) == nil
            && Logic.sweep(phase: 12, period: 10, crossing: 4) == 0.5,
               "the cleaning sweep crosses, rests, then crosses again")
        suite.expect((0..<200).map(Logic.noise).allSatisfy { $0 >= 0 && $0 < 1 }
            && Logic.noise(7) == Logic.noise(7) && Logic.noise(7) != Logic.noise(8),
               "particles get stable positions of their own")
    }
}
