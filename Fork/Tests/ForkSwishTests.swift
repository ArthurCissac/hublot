// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Swish's settings carried over: modifiers, arrow keys, displays, import.
enum ForkSwishTests {
    typealias Modifiers = ForkSwishModifiers

    static func run(_ suite: TestSuite) {
        modifiers(suite)
        taps(suite)
        arrowKeys(suite)
        displays(suite)
        dock(suite)
        motion(suite)
        dragGuard(suite)
        importing(suite)
    }

    private static func dragGuard(_ suite: TestSuite) {
        typealias Guard = ForkDragTopGuardLogic
        // This Mac: the laptop, and a 1920 by 1080 display stacked above it
        // (window-list coordinates, y down).
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let above = CGRect(x: -215, y: -1080, width: 1920, height: 1080)
        let edges = Guard.edges(displays: [laptop, above])
        suite.expect(edges == [Guard.Edge(y: 0, minX: 0, maxX: 1512, kind: .cross),
                               Guard.Edge(y: -1080, minX: -215, maxX: 1705, kind: .hold)],
               "the laptop's top, under the display above, carries drags across; the top display's own edge holds them")
        suite.expect(Guard.carried(CGPoint(x: 1250, y: 0), deltaY: -4, edges: edges) == CGPoint(x: 1250, y: -3)
            && Guard.carried(CGPoint(x: 756, y: 0.5), deltaY: -1, edges: edges) == CGPoint(x: 756, y: -3),
               "a drag moving up to the laptop's top lands straight on the display above, notch included")
        suite.expect(Guard.carried(CGPoint(x: 756, y: 0), deltaY: 3, edges: edges) == nil
            && Guard.carried(CGPoint(x: 756, y: 10), deltaY: -3, edges: edges) == nil
            && Guard.carried(CGPoint(x: 756, y: -20), deltaY: -3, edges: edges) == nil,
               "coming down, still lower, or already above, it is left alone")
        suite.expect(Guard.kept(CGPoint(x: 756, y: 0), edges: edges) == nil,
               "nothing holds a drag under an edge with a display above")
        suite.expect(Guard.kept(CGPoint(x: 900, y: -1080), edges: edges) == CGPoint(x: 900, y: -1079),
               "the top display's own edge keeps the drag one point under it")
        let held = CGPoint(x: 900, y: -1079)
        let pushed = Guard.heldStep(from: held, delta: CGVector(dx: 10, dy: -8), edgeY: -1080, edges: edges)
        suite.expect(pushed.point == CGPoint(x: 910, y: -1079) && pushed.held,
               "pushed up against it, the held cursor slides along the edge and stays held")
        let down = Guard.heldStep(from: held, delta: CGVector(dx: 0, dy: 12), edgeY: -1080, edges: edges)
        suite.expect(down.point == CGPoint(x: 900, y: -1067) && !down.held, "coming back down lets it go")
        suite.expect(Guard.isNearTop(CGPoint(x: 756, y: 20), edges: edges)
            && !Guard.isNearTop(CGPoint(x: 756, y: 200), edges: edges),
               "the drag is checked only near a top edge")
        let partly = Guard.edges(displays: [laptop, CGRect(x: 1000, y: -1080, width: 1920, height: 1080)])
        suite.expect(partly.prefix(2) == [Guard.Edge(y: 0, minX: 0, maxX: 1000, kind: .hold),
                                          Guard.Edge(y: 0, minX: 1000, maxX: 1512, kind: .cross)],
               "a display above only part of the laptop carries drags only there")
        suite.expect(Guard.edges(displays: [laptop]) == [Guard.Edge(y: 0, minX: 0, maxX: 1512, kind: .hold)],
               "a lone display holds drags across its top")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkDragTopGuard] as? Bool == true
            && SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkDragTopGuard),
               "the drag guard is on by default and travels in backups")
    }

    private static func motion(_ suite: TestSuite) {
        let start = CGRect(x: 100, y: 100, width: 800, height: 600)
        let end = CGRect(x: 0, y: 25, width: 756, height: 957)
        let frames = ForkSwishMotion.glide(from: start, to: end)
        suite.expect(frames.count == ForkSwishMotion.glideSteps && frames.last == end,
               "a glide takes its steps and lands exactly on the destination")
        let firstHalf = frames[0].minX - start.minX, secondHalf = frames[frames.count / 2].minX - frames[frames.count / 2 - 1].minX
        suite.expect(abs(firstHalf) > abs(secondHalf),
               "it eases out: big steps first, small ones as it settles")
        suite.expect(ForkSwishMotion.glide(from: end, to: end) == [end], "no glide to where the window already is")

        suite.expect(ForkSwishMotion.pinchProgress(-0.175) == 0.5 && ForkSwishMotion.pinchProgress(0.9) == 1
            && ForkSwishMotion.pinchProgress(.nan) == 0,
               "a pinch's progress runs from 0 to 1 at the threshold")

        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        suite.expect(ForkSwishMotion.region(of: CGRect(x: 0, y: 400, width: 500, height: 400), in: area)
            == CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
               "the top left quarter sits at the top left of the bubble's screen")
        suite.expect(ForkSwishMotion.region(of: CGRect(x: 500, y: 0, width: 500, height: 800), in: area)
            == CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
               "the right half fills the right of it")

        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let size = CGSize(width: 380, height: 64)
        suite.expect(ForkSwishMotion.bubbleOrigin(pointer: CGPoint(x: 300, y: 500), size: size, screen: screen)
            == CGPoint(x: 318, y: 518),
               "the bubble sits up and to the right of the pointer")
        let flipped = ForkSwishMotion.bubbleOrigin(pointer: CGPoint(x: 1400, y: 960), size: size, screen: screen)
        suite.expect(flipped.x == 1400 - 18 - 380 && flipped.y == 960 - 18 - 64,
               "near the top right corner it moves to the other side of the pointer")
    }

    private static func dock(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        suite.expect(ForkSwishDock.isInBand(CGPoint(x: 700, y: 40), screen: screen, orientation: "bottom")
            && ForkSwishDock.isInBand(CGPoint(x: 700, y: 40), screen: screen, orientation: nil)
            && !ForkSwishDock.isInBand(CGPoint(x: 700, y: 400), screen: screen, orientation: "bottom"),
               "a point near the bottom edge is along a Dock at the bottom, one higher up is not")
        suite.expect(ForkSwishDock.isInBand(CGPoint(x: 30, y: 500), screen: screen, orientation: "left")
            && ForkSwishDock.isInBand(CGPoint(x: 1490, y: 500), screen: screen, orientation: "right")
            && !ForkSwishDock.isInBand(CGPoint(x: 700, y: 40), screen: screen, orientation: "left")
            && !ForkSwishDock.isInBand(CGPoint(x: 2000, y: 40), screen: screen, orientation: "bottom"),
               "a Dock on a side has its band on that side, and a point off the display is in no band")
        suite.expect(ForkSwishDock.gesture(for: .right, role: .none) == .cycle(forward: true)
            && ForkSwishDock.gesture(for: .left, role: .none) == .cycle(forward: false)
            && ForkSwishDock.gesture(for: .down, role: .none) == .minimize(all: false)
            && ForkSwishDock.gesture(for: .up, role: .none) == .unminimize(all: false),
               "over an icon: sideways goes through the app's windows, down minimizes, up brings back")
        suite.expect(ForkSwishDock.gesture(for: .down, role: .secondary) == .minimize(all: true)
            && ForkSwishDock.gesture(for: .up, role: .secondary) == .unminimize(all: true)
            && ForkSwishDock.gesture(for: .down, role: .general) == .quit
            && ForkSwishDock.gesture(for: .upLeft, role: .none) == nil,
               "the secondary modifier acts on every window, the general one quits")
        suite.expect(ForkSwishDock.gesture(forPinch: -0.5) == .quit && ForkSwishDock.gesture(forPinch: 0.5) == nil,
               "a pinch closed over an icon quits the app")
        suite.expect(ForkSwishDock.cycleTarget([10, 11, 12], forward: true) == 11
            && ForkSwishDock.cycleTarget([10, 11, 12], forward: false) == 12
            && ForkSwishDock.cycleTarget([10], forward: true) == nil,
               "going through windows brings the next one forward, or the backmost going back")
        typealias App = ForkSwishDock.AppState
        let lone = App(open: 1, minimized: 0, onScreen: 1, active: true)
        suite.expect(!ForkSwishDock.acts(.cycle(forward: true), on: lone)
            && ForkSwishDock.acts(.cycle(forward: false), on: App(open: 1, minimized: 0, onScreen: 1, active: false))
            && ForkSwishDock.acts(.cycle(forward: true), on: App(open: 2, minimized: 0, onScreen: 2, active: true))
            && !ForkSwishDock.acts(.cycle(forward: true), on: App(open: 0, minimized: 2, onScreen: 0, active: false)),
               "going through windows shows only when a window would come forward: two for the app in front, one otherwise")
        suite.expect(ForkSwishDock.acts(.minimize(all: false), on: lone) && !ForkSwishDock.acts(.unminimize(all: false), on: lone)
            && ForkSwishDock.acts(.unminimize(all: true), on: App(open: 0, minimized: 1, onScreen: 0, active: false))
            && !ForkSwishDock.acts(.minimize(all: true), on: App())
            && ForkSwishDock.acts(.quit, on: App()),
               "minimizing needs an open window, bringing back a minimized one; quitting always acts")
        func window(pid: Int32, layer: Int, _ frame: CGRect) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
             kCGWindowBounds as String: frame.dictionaryRepresentation]
        }
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bottom = CGPoint(x: 700, y: 870)
        let app = window(pid: 500, layer: 0, CGRect(x: 0, y: 33, width: 1512, height: 949))
        suite.expect(ForkSwishDock.isShowing(at: bottom, in: [app, window(pid: 90, layer: 20, display)], dockPID: 90)
            && !ForkSwishDock.isShowing(at: bottom, in: [app], dockPID: 90),
               "the Dock counts only while one of its windows is on screen: hidden, the bottom of a window is the window's")
        suite.expect(!ForkSwishDock.isShowing(at: bottom, in: [window(pid: 90, layer: 0, display)], dockPID: 90)
            && !ForkSwishDock.isShowing(at: bottom, in: [window(pid: 7, layer: 20, display)], dockPID: 90)
            && !ForkSwishDock.isShowing(at: CGPoint(x: 2000, y: 870), in: [window(pid: 90, layer: 20, display)], dockPID: 90),
               "another level, another app's window or another display does not make the Dock show there")
    }

    private static func modifiers(_ suite: TestSuite) {
        let set = Modifiers.Set()
        suite.expect(Modifiers.defaultGeneral == 8_388_608 && Modifiers.defaultScreen == 131_072
            && Modifiers.defaultSecondary == 9_175_040 && Modifiers.defaultTertiary == 8_912_896
            && Modifiers.defaultSuper == 1_048_576,
               "the defaults are the values Swish stored on this Mac")
        func role(_ flags: Int) -> Modifiers.Role? { Modifiers.role(flags: flags, in: set)?.role }
        suite.expect(role(0) == Modifiers.Role.none && role(Modifiers.fn) == .general && role(Modifiers.shift) == .screen
            && role(Modifiers.fn | Modifiers.control | Modifiers.option) == .secondary
            && role(Modifiers.fn | Modifiers.option) == .tertiary,
               "each set of keys held picks its role, fn alone apart from fn ⌥")
        suite.expect(role(Modifiers.control) == nil && role(Modifiers.option) == nil,
               "keys that match no role give no gesture")
        let withSuper = Modifiers.role(flags: Modifiers.command | Modifiers.shift, in: set)
        suite.expect(withSuper?.role == .screen && withSuper?.superHeld == true
            && Modifiers.role(flags: Modifiers.command, in: set)?.superHeld == true
            && Modifiers.role(flags: 0, in: set)?.superHeld == false,
               "the super modifier combines with the others")
        suite.expect(role(Modifiers.fn | 0x100) == .general, "bits outside the five keys are ignored")
        suite.expect(Modifiers.symbols(Modifiers.defaultSecondary) == "fn ⌃ ⌥" && Modifiers.symbols(0) == "—",
               "a modifier prints in the keyboard's order")
    }

    private static func taps(_ suite: TestSuite) {
        typealias Logic = ForkTitleBarGestureLogic
        /// Feeds one tap: two fingers down at `start` for `length` seconds, sliding by `slide`.
        func tap(_ recognizer: inout ForkSwishTapRecognizer, at start: TimeInterval, length: TimeInterval = 0.1,
                 fingers: Int = 2, slide: Float = 0) -> Bool {
            _ = recognizer.feed(fingers: fingers, center: (0.5, 0.5), at: start)
            _ = recognizer.feed(fingers: fingers, center: (0.5 + slide, 0.5), at: start + length / 2)
            return recognizer.feed(fingers: 0, center: nil, at: start + length)
        }
        var recognizer = ForkSwishTapRecognizer()
        suite.expect(!tap(&recognizer, at: 1) && tap(&recognizer, at: 1.3),
               "two quick two-finger taps make a double tap")
        suite.expect(!tap(&recognizer, at: 2) && !tap(&recognizer, at: 2.8),
               "taps too far apart do not")
        recognizer = ForkSwishTapRecognizer()
        suite.expect(!tap(&recognizer, at: 3) && !tap(&recognizer, at: 3.2, length: 0.5),
               "fingers held down too long make no tap")
        recognizer = ForkSwishTapRecognizer()
        suite.expect(!tap(&recognizer, at: 4) && !tap(&recognizer, at: 4.2, slide: 0.1),
               "fingers that slide make no tap")
        recognizer = ForkSwishTapRecognizer()
        suite.expect(!tap(&recognizer, at: 5, fingers: 3) && !tap(&recognizer, at: 5.2, fingers: 3),
               "three fingers make no double tap")

        suite.expect(Logic.swipeThreshold(sensitivity: 1) == 70 && Logic.swipeThreshold(sensitivity: 5) == 32
            && Logic.swipeThreshold(sensitivity: 0) == 70 && Logic.swipeThreshold(sensitivity: 9) == 32,
               "the calmer the sensitivity, the farther a swipe travels")
        suite.expect(Logic.direction(of: CGVector(dx: 60, dy: 0), threshold: 70) == nil
            && Logic.direction(of: CGVector(dx: 60, dy: 0), threshold: 50) == .right,
               "the swipe threshold follows the sensitivity")
        suite.expect(Logic.rested(lastMoved: 1, now: 2, timeout: 0.8) && !Logic.rested(lastMoved: 1, now: 1.5, timeout: 0.8)
            && !Logic.rested(lastMoved: 1, now: 9, timeout: 0),
               "fingers resting past the timeout call the gesture off; a timeout of 0 never does")
    }

    private static func arrowKeys(_ suite: TestSuite) {
        var chain = ForkSwishArrowKeys.Chain()
        suite.expect(chain.press(.left, screen: false, at: 10) == .layout(.leftHalf)
            && chain.press(.up, screen: false, at: 10.3) == .layout(.topLeft),
               "left then up in quick succession reach the top left quarter")
        suite.expect(chain.press(.up, screen: false, at: 10.5) == .layout(.maximize),
               "a corner ends the chain")
        suite.expect(chain.press(.right, screen: false, at: 20) == .layout(.rightHalf)
            && chain.press(.down, screen: false, at: 21) == .minimize,
               "too slow, the second arrow acts alone: down minimizes")
        suite.expect(chain.press(.down, screen: false, at: 30) == .minimize
            && chain.press(.left, screen: false, at: 30.2) == .layout(.leftHalf),
               "down never starts a corner")
        suite.expect(chain.press(.right, screen: true, at: 40) == .display(.right)
            && chain.press(.up, screen: false, at: 40.1) == .layout(.maximize),
               "with the screen modifier an arrow picks a display and starts no corner")
        suite.expect(ForkSwishArrowKeys.Arrow.left.keyCode == 123 && ForkSwishArrowKeys.Arrow.up.keyCode == 126,
               "the arrows' key codes")
    }

    private static func displays(_ suite: TestSuite) {
        // A laptop with a display to its right, and one above that.
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let right = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let above = CGRect(x: 1600, y: 1240, width: 1920, height: 1080)
        let all = [laptop, right, above]
        suite.expect(ForkSwishDisplays.neighbor(of: laptop, toward: .right, among: all) == 1
            && ForkSwishDisplays.neighbor(of: right, toward: .left, among: all) == 0
            && ForkSwishDisplays.neighbor(of: right, toward: .up, among: all) == 2
            && ForkSwishDisplays.neighbor(of: above, toward: .down, among: all) == 1,
               "the display that way is the one where the Displays settings put it")
        suite.expect(ForkSwishDisplays.neighbor(of: laptop, toward: .left, among: all) == nil
            && ForkSwishDisplays.neighbor(of: laptop, toward: .upRight, among: all) == nil,
               "no display that way, or a diagonal, gives none")
        suite.expect(ForkSwishDisplays.accessibilityRect(CGRect(x: 10, y: 100, width: 200, height: 50), primaryHeight: 1000)
            == CGRect(x: 10, y: 850, width: 200, height: 50),
               "AppKit frames turn into Accessibility frames")
        let moved = ForkSwishDisplays.frame(CGRect(x: 0, y: 0, width: 756, height: 982),
                                            from: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                            to: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
        suite.expect(moved == CGRect(x: 1512, y: 0, width: 756, height: 982),
               "a window keeps its size and its place against the edges on the other display")
        let shrunk = ForkSwishDisplays.frame(CGRect(x: 100, y: 0, width: 2000, height: 1200),
                                             from: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                             to: CGRect(x: 0, y: 0, width: 1512, height: 982))
        suite.expect(shrunk.width == 1512 && shrunk.height == 982, "and shrinks only to fit")
    }

    private static func importing(_ suite: TestSuite) {
        // Swish's preferences on this Mac, licence data left out.
        let swish: [String: Any] = [
            "generalModifier": NSNumber(value: 8_388_608), "screenModifier": NSNumber(value: 131_072),
            "secondaryModifier": NSNumber(value: 9_175_040), "tertiaryModifier": NSNumber(value: 8_912_896),
            "superModifier": NSNumber(value: 1_048_576), "hotkeys": NSNumber(value: 1),
            "hotkeyArrow": "\"arrows\"", "hotkeyUndo": "\"letterO\"",
            "screensMoveCursor": NSNumber(value: 1), "snappingMoveCursor": NSNumber(value: 1),
            "requireSuperMod": NSNumber(value: 0), "scrollingSensitivity": NSNumber(value: 1),
            "tooltipLive": NSNumber(value: 1),
        ]
        let values = ForkSwishImport.values(fromSwish: swish)
        suite.expect(values[DefaultsKey.forkSwishSecondaryModifier] as? Int == 9_175_040
            && values[DefaultsKey.forkSwishSuperModifier] as? Int == 1_048_576
            && values[DefaultsKey.forkSwishArrowKeys] as? Bool == true
            && values[DefaultsKey.forkSwishMoveCursor] as? Bool == true
            && values[DefaultsKey.forkSwishRequireSuper] as? Bool == false
            && values[DefaultsKey.forkSwishSensitivity] as? Int == 1
            && values[DefaultsKey.forkSwishPreview] as? Bool == true
            && values[DefaultsKey.forkSwishBubble] as? Bool == true,
               "Swish's modifiers, arrow keys, pointer and super settings carry over")
        suite.expect(ForkSwishImport.values(fromSwish: ["hotkeys": NSNumber(value: 1), "hotkeyArrow": "\"wasd\""])[DefaultsKey.forkSwishArrowKeys] as? Bool == false,
               "WASD hotkeys do not turn the arrow keys on")
        suite.expect(ForkSwishImport.values(fromSwish: [:]).isEmpty
            && ForkSwishImport.values(fromSwish: ["screenModifier": NSNumber(value: 0)]).isEmpty,
               "what Swish does not store, or stores empty, leaves Hublot's setting alone")

        let keys = [DefaultsKey.forkSwishGeneralModifier, DefaultsKey.forkSwishScreenModifier,
                    DefaultsKey.forkSwishSecondaryModifier, DefaultsKey.forkSwishTertiaryModifier,
                    DefaultsKey.forkSwishSuperModifier, DefaultsKey.forkSwishArrowKeys, DefaultsKey.forkSwishMoveCursor,
                    DefaultsKey.forkSwishRequireSuper, DefaultsKey.forkSwishActiveListener, DefaultsKey.forkSwishDoubleTap,
                    DefaultsKey.forkSwishHaptics, DefaultsKey.forkSwishSensitivity, DefaultsKey.forkSwishCancelTimeout,
                    DefaultsKey.forkSwishPreview, DefaultsKey.forkSwishDockGestures, DefaultsKey.forkSwishBubble,
                    DefaultsKey.forkSwishLiveMove]
        for key in keys {
            suite.expect(Defaults.registeredDefaults[key] != nil && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) has a default and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkSwishArrowKeys] as? Bool == true,
               "the arrow keys are on, as they were in Swish")
    }
}
