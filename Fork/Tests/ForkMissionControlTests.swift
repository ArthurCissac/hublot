// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Mission Control's × and shortcuts on the window under the pointer.
enum ForkMissionControlTests {
    typealias Logic = ForkMissionControlLogic

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.bundleID(fromIdentifier: "com.google.Chrome.space.5") == "com.google.Chrome"
            && Logic.bundleID(fromIdentifier: "com.anthropic.claudefordesktop.space.1032") == "com.anthropic.claudefordesktop",
                     "a thumbnail's identifier names its app")
        suite.expect(Logic.bundleID(fromIdentifier: "mc.spaces.add") == nil
            && Logic.bundleID(fromIdentifier: "mc.spaces.list") == nil
            && Logic.bundleID(fromIdentifier: ".space.3") == nil
            && Logic.bundleID(fromIdentifier: "com.app.space.x") == nil,
                     "the Spaces bar and odd identifiers are no window")

        // As the probe saw them: Chrome on the left, Claude on the right, and a window on the display above.
        let chrome = Logic.Thumbnail(windowID: 41, bundleID: "com.google.Chrome", title: "a",
                                     frame: CGRect(x: 18, y: 111, width: 731, height: 459))
        let claude = Logic.Thumbnail(windowID: 52, bundleID: "com.anthropic.claudefordesktop", title: "b",
                                     frame: CGRect(x: 762, y: 429, width: 731, height: 459))
        let above = Logic.Thumbnail(windowID: nil, bundleID: "com.google.Chrome", title: "c",
                                    frame: CGRect(x: -30, y: -946, width: 1_551, height: 872))
        let all = [chrome, claude, above]
        suite.expect(Logic.thumbnail(at: CGPoint(x: 100, y: 200), in: all) == chrome
            && Logic.thumbnail(at: CGPoint(x: 1_000, y: 600), in: all) == claude
            && Logic.thumbnail(at: CGPoint(x: 400, y: -500), in: all) == above,
                     "the pointer picks the thumbnail under it, on either display")
        suite.expect(Logic.thumbnail(at: CGPoint(x: 755, y: 300), in: all) == nil,
                     "between thumbnails, none")
        let small = Logic.Thumbnail(windowID: 7, bundleID: "x", title: "d", frame: CGRect(x: 100, y: 150, width: 50, height: 50))
        suite.expect(Logic.thumbnail(at: CGPoint(x: 120, y: 170), in: [chrome, small]) == small,
                     "where two overlap while rearranging, the smaller, drawn on top")

        let button = Logic.closeButtonFrame(for: chrome.frame)
        suite.expect(button == CGRect(x: 24, y: 117, width: 22, height: 22) && chrome.frame.contains(button),
                     "the × sits in the thumbnail's top left corner, inside it, so hovering it keeps the thumbnail")

        suite.expect(Logic.action(keyCode: 13, command: true, otherModifiers: false) == .close
            && Logic.action(keyCode: 4, command: true, otherModifiers: false) == .hide
            && Logic.action(keyCode: 12, command: true, otherModifiers: false) == .quit,
                     "⌘W closes, ⌘H hides, ⌘Q quits")
        suite.expect(Logic.action(keyCode: 13, command: false, otherModifiers: false) == nil
            && Logic.action(keyCode: 12, command: true, otherModifiers: true) == nil
            && Logic.action(keyCode: 0, command: true, otherModifiers: false) == nil,
                     "other keys and other modifiers are left to macOS")

        let displays = [CGRect(x: 0, y: 0, width: 1_512, height: 982), CGRect(x: -215, y: -1_080, width: 1_920, height: 1_080)]
        let closed = [Logic.WindowInfo(owner: "WindowManager", layer: -2_147_483_624, bounds: displays[0]),
                      Logic.WindowInfo(owner: "Google Chrome", layer: 0, bounds: displays[0])]
        let open = closed + [Logic.WindowInfo(owner: "WindowManager", layer: 19, bounds: displays[0]),
                             Logic.WindowInfo(owner: "WindowManager", layer: 14, bounds: CGRect(x: 0, y: 0, width: 1_512, height: 128))]
        suite.expect(!Logic.overviewIsOpen(windows: closed, displays: displays)
            && Logic.overviewIsOpen(windows: open, displays: displays),
                     "Mission Control is open while WindowManager covers a display at layer 19")
        suite.expect(!Logic.overviewIsOpen(windows: [Logic.WindowInfo(owner: "WindowManager", layer: 19,
                                                                      bounds: CGRect(x: 0, y: 0, width: 200, height: 80))],
                                           displays: displays),
                     "a small layer 19 window, Stage Manager's strip say, is not Mission Control")

        suite.expect(Logic.appKitRect(button, primaryHeight: 982) == CGRect(x: 24, y: 843, width: 22, height: 22)
            && Logic.accessibilityPoint(CGPoint(x: 10, y: 900), primaryHeight: 982) == CGPoint(x: 10, y: 82),
                     "accessibility and AppKit coordinates turn into each other on the primary display")
        suite.expect(!Logic.pinchQuits(magnification: -0.2) && Logic.pinchQuits(magnification: -0.4)
            && !Logic.pinchQuits(magnification: 0.6) && !Logic.pinchQuits(magnification: .nan),
                     "a pinch quits the app once closed as far as a title bar pinch; spreading does nothing")
        suite.expect(Logic.pinchLeans(magnification: -0.05) && !Logic.pinchLeans(magnification: 0.05),
                     "the × lights up as soon as the pinch leans toward quitting")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkMissionControlPlus] as? Bool == true,
                     "the × in Mission Control is on by default")
    }
}
