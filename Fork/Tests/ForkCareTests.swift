// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9e: the cleaning tools' shared look, its contrast and its steps.
enum ForkCareTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkCareLogic

        suite.expect(abs(Logic.contrast(.white, Logic.RGB(0, 0, 0)) - 21) < 0.01
            && abs(Logic.contrast(.white, .white) - 1) < 0.001,
                     "contrast runs from 1 (same colour) to 21 (white on black)")
        suite.expect(Logic.RGB(hex: 0x1E3A8A) == Logic.RGB(30.0 / 255, 58.0 / 255, 138.0 / 255),
                     "hex colours are read channel by channel")

        var readable = true
        for tool in Logic.Tool.allCases {
            let stops = Logic.gradient(tool)
            for background in [stops.top, stops.bottom] {
                let secondary = Logic.blend(.white, over: background, opacity: Logic.secondaryOpacity)
                if Logic.contrast(.white, background) < 7 || Logic.contrast(secondary, background) < 4.5 {
                    readable = false
                }
            }
        }
        suite.expect(readable, "white text reads at 7:1 and secondary text at 4.5:1 on every background")
        var lightReadable = true
        var lightAccents = true
        for tool in Logic.Tool.allCases {
            let stops = Logic.lightGradient(tool)
            for background in [stops.top, stops.bottom] {
                let card = Logic.lightCardBackground(over: background)
                for surface in [background, card] {
                    if Logic.contrast(Logic.lightPrimary, surface) < 7 || Logic.contrast(Logic.lightSecondary, surface) < 4.5 {
                        lightReadable = false
                    }
                    let figures = Logic.Category.allCases.map(Logic.lightAccent) + [Logic.tint(tool, dark: false)]
                    if figures.contains(where: { Logic.contrast($0, surface) < 3 }) { lightAccents = false }
                }
            }
        }
        suite.expect(lightReadable, "in light mode, text reads at 7:1 and secondary text at 4.5:1 on every background and card")
        suite.expect(lightAccents, "in light mode, the results' colours and each tool's hue keep 3:1 for figures and symbols")
        suite.expect(Logic.tint(.antivirus, dark: true) == Logic.glow(.antivirus)
            && Logic.tint(.antivirus, dark: false) == Logic.buttonGradient(.antivirus).bottom,
                     "a tool's hue is its light on dark, its deepest shade on light")
        let tops = Logic.Tool.allCases.map { Logic.gradient($0).top }
        suite.expect(Set(tops.map { "\($0.red)-\($0.green)-\($0.blue)" }).count == Logic.Tool.allCases.count,
                     "each tool has a hue of its own")

        suite.expect(Logic.stage(working: false, summaryReady: false) == .welcome
            && Logic.stage(working: true, summaryReady: true) == .working
            && Logic.stage(working: false, summaryReady: true) == .summary,
                     "welcome, the work under way, then the summary")

        suite.expect(Logic.progress(done: 1, total: 4) == 0.25 && Logic.progress(done: 9, total: 4) == 1
            && Logic.progress(done: 0, total: 0) == nil,
                     "the ring fills with the work done, spins when its length is unknown")

        suite.expect(Logic.maintenanceOutcome([true, true, true]) == .allDone(3)
            && Logic.maintenanceOutcome([true, false, true]) == .partly(done: 2, failed: 1)
            && Logic.maintenanceOutcome([]) == .nothingRan,
                     "the summary counts the jobs done and failed")

        suite.expect(!Logic.isPlural(0, french: true) && !Logic.isPlural(1, french: true)
            && Logic.isPlural(2, french: true),
                     "French: « 0 terminée », « 1 terminée », « 2 terminées »")
        suite.expect(Logic.isPlural(0, french: false) && !Logic.isPlural(1, french: false)
            && Logic.isPlural(2, french: false),
                     "English: “0 jobs”, “1 job”, “2 jobs”")
    }
}
