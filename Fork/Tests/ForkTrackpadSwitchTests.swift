// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Three fingers on the trackpad for the window switcher.
enum ForkTrackpadSwitchTests {
    typealias Recognizer = ForkTrackpadSwitchRecognizer

    static func run(_ suite: TestSuite) {
        var recognizer = Recognizer()
        var outputs: [Recognizer.Output] = []
        func feed(_ fingers: Int, _ x: Float, _ y: Float = 0.5) { outputs += recognizer.feed(fingers: fingers, center: (x, y)) }

        feed(3, 0.50)
        feed(3, 0.53)
        suite.expect(outputs.isEmpty, "a small movement does not open the switcher")
        feed(3, 0.57)
        suite.expect(outputs == [.begin(reversed: false)], "three fingers swiped to the right open it")
        feed(3, 0.65)
        feed(3, 0.80)
        suite.expect(outputs == [.begin(reversed: false), .step(1), .step(1), .step(1)],
               "going on moves one window per step of travel")
        feed(2, 0.80)
        suite.expect(outputs.last == .step(1), "fingers leaving one by one do not pick yet")
        feed(0, 0)
        suite.expect(outputs.last == .commit, "the pad empty, the window is picked")

        recognizer = Recognizer(); outputs = []
        feed(3, 0.5); feed(3, 0.43); feed(3, 0.35)
        suite.expect(outputs == [.begin(reversed: true), .step(-1)], "to the left it opens from the far end and goes back")

        recognizer = Recognizer(); outputs = []
        feed(3, 0.5, 0.5); feed(3, 0.51, 0.6); feed(3, 0.6, 0.6); feed(0, 0)
        suite.expect(outputs.isEmpty, "a vertical swipe is left to macOS")

        recognizer = Recognizer(); outputs = []
        feed(3, 0.5); feed(3, 0.6); feed(4, 0.6); feed(0, 0)
        suite.expect(outputs == [.begin(reversed: false), .cancel], "a fourth finger cancels")

        recognizer = Recognizer(); outputs = []
        feed(2, 0.5); feed(2, 0.7); feed(0, 0)
        suite.expect(outputs.isEmpty, "two fingers scroll: nothing opens")

        recognizer = Recognizer(); outputs = []
        outputs += recognizer.feed(fingers: 3, center: nil)
        outputs += recognizer.feed(fingers: 3, center: (0.9, 0.5))
        suite.expect(outputs.isEmpty, "touches that cannot be read start nothing")

        suite.expect(Recognizer.systemUsesThreeFingerSwipe([2, nil]) && Recognizer.systemUsesThreeFingerSwipe([0, 1])
            && !Recognizer.systemUsesThreeFingerSwipe([0, 0]) && !Recognizer.systemUsesThreeFingerSwipe([nil, nil]),
               "while macOS uses three fingers to move between full-screen apps, the gesture is left to it")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkSwitcherTrackpadGesture] as? Bool == false,
               "the trackpad switcher is off until chosen")
    }
}
