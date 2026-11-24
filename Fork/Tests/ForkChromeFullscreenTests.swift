// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Three fingers down in Chrome, out of a video's full screen and back.
enum ForkChromeFullscreenTests {
    typealias Logic = ForkChromeFullscreenLogic

    static func run(_ suite: TestSuite) {
        var swipe = Logic.DownSwipe()
        var fired = 0
        for step in 0...10 { if swipe.feed(fingers: 3, center: (0.5, 0.7 - Float(step) * 0.02)) { fired += 1 } }
        _ = swipe.feed(fingers: 0, center: nil)
        suite.expect(fired == 1, "three fingers going down fire once, on the way, not at every frame")

        var up = Logic.DownSwipe()
        var upFired = false
        for step in 0...10 { upFired = up.feed(fingers: 3, center: (0.5, 0.3 + Float(step) * 0.03)) || upFired }
        suite.expect(!upFired, "going up, Mission Control's swipe, fires nothing")

        var sideways = Logic.DownSwipe()
        var sideFired = false
        for step in 0...10 { sideFired = sideways.feed(fingers: 3, center: (0.3 + Float(step) * 0.04, 0.7 - Float(step) * 0.01)) || sideFired }
        suite.expect(!sideFired, "going sideways, macOS's switch between full-screen apps, fires nothing")

        var four = Logic.DownSwipe()
        var fourFired = false
        for step in 0...10 { fourFired = four.feed(fingers: 4, center: (0.5, 0.7 - Float(step) * 0.03)) || fourFired }
        suite.expect(!fourFired, "four fingers are another gesture")

        var lifted = Logic.DownSwipe()
        _ = lifted.feed(fingers: 3, center: (0.5, 0.7))
        _ = lifted.feed(fingers: 2, center: (0.5, 0.6))
        let afterLift = lifted.feed(fingers: 3, center: (0.5, 0.4))
        suite.expect(!afterLift, "a finger lifted calls it off until the pad is empty")

        suite.expect(Logic.systemUsesThreeFingersDown(verticalSwipe: 2, appExposeGesture: true)
            && !Logic.systemUsesThreeFingersDown(verticalSwipe: 2, appExposeGesture: nil)
            && !Logic.systemUsesThreeFingersDown(verticalSwipe: 0, appExposeGesture: true),
                     "the swipe is left to macOS only while App Exposé takes three fingers down")

        suite.expect(Logic.videoTab(fromReply: "1234,5678") == Logic.VideoTab(windowID: 1_234, tabID: 5_678)
            && Logic.videoTab(fromReply: "") == nil && Logic.videoTab(fromReply: "a,b") == nil
            && Logic.videoTab(fromReply: "12") == nil,
                     "Chrome's reply gives the window and the tab, or nothing")
        let script = Logic.showTabScript(Logic.VideoTab(windowID: 1_234, tabID: 5_678))
        suite.expect(script.contains("is 1234 then") && script.contains("is 5678 then") && script.contains(Logic.chromeBundleID),
                     "the script that brings the tab back holds only its numbers")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkChromeFullscreenSwipe] as? Bool == true,
                     "the Chrome swipe is on by default")
    }
}
