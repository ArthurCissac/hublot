// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9h: the cleaning tools' colours stay readable, their motion short where it matters.
enum ForkCareMotionTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkCareLogic
        typealias Motion = ForkCareMotion

        var buttons = true
        for tool in Logic.Tool.allCases {
            let fill = Logic.buttonGradient(tool)
            let minimum = Logic.buttonTitleMinimumContrast
            if Logic.contrast(.white, fill.top) < minimum || Logic.contrast(.white, fill.bottom) < minimum { buttons = false }
            // Brighter than the background it sits on, so it stands out.
            if Logic.luminance(fill.top) <= Logic.luminance(Logic.gradient(tool).top) { buttons = false }
        }
        suite.expect(buttons && Logic.buttonTitleMinimumContrast >= 3,
                     "the round button stands out from its background and its large white title reads at 3:1 or more")

        var cards = true
        var figures = true
        for tool in Logic.Tool.allCases {
            let stops = Logic.gradient(tool)
            for background in [stops.top, stops.bottom] {
                let card = Logic.cardBackground(over: background)
                let secondary = Logic.blend(.white, over: card, opacity: Logic.secondaryOpacity)
                if Logic.contrast(secondary, card) < 4.5 { cards = false }
                for category in Logic.Category.allCases where Logic.contrast(Logic.accent(category), card) < 3 {
                    figures = false
                }
            }
        }
        suite.expect(cards, "secondary text on the cards reads at 4.5:1")
        suite.expect(figures, "the cards' large coloured figures read at 3:1, as large text must")

        suite.expect(Motion.appear <= 0.5 && Motion.check <= 0.5 && Motion.stagger >= 0.03 && Motion.stagger <= 0.08
            && Motion.countUp <= 1,
                     "what changes moves briefly: arrivals and the tick under half a second, cards 30 to 80 ms apart")
        suite.expect(Motion.breathe >= 2 && Motion.float >= 2 && Motion.drift >= 10,
                     "what waits moves slowly")
        suite.expect(Motion.delay(index: 0) == 0 && abs(Motion.delay(index: 2) - 2 * Motion.stagger) < 1e-9
            && Motion.delay(index: -1) == 0,
                     "cards arrive one after the other, the first at once")
    }
}
