// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Gestures on a window's title bar.
enum ForkTitleBarGestureTests {
    typealias Logic = ForkTitleBarGestureLogic

    static func run(_ suite: TestSuite) {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        suite.expect(Logic.isOnTitleBar(CGPoint(x: 400, y: 210), windowFrame: window)
            && Logic.isOnTitleBar(CGPoint(x: 400, y: 252), windowFrame: window),
               "the title bar, and a toolbar merged with it, take the gesture")
        suite.expect(!Logic.isOnTitleBar(CGPoint(x: 400, y: 300), windowFrame: window)
            && !Logic.isOnTitleBar(CGPoint(x: 50, y: 210), windowFrame: window)
            && !Logic.isOnTitleBar(CGPoint(x: 400, y: 190), windowFrame: window),
               "the window's content, and anything outside the window, do not")

        let natural = Logic.fingerMovement(scrollDeltaX: 10, scrollDeltaY: 6, naturalScrolling: true)
        let classic = Logic.fingerMovement(scrollDeltaX: -10, scrollDeltaY: -6, naturalScrolling: false)
        suite.expect(natural == CGVector(dx: 10, dy: -6) && classic == natural,
               "the fingers' movement is the same whichever scrolling direction is set")

        suite.expect(Logic.direction(of: CGVector(dx: 120, dy: 5)) == .right && Logic.direction(of: CGVector(dx: -120, dy: 0)) == .left
            && Logic.direction(of: CGVector(dx: 0, dy: 90)) == .up && Logic.direction(of: CGVector(dx: 3, dy: -90)) == .down,
               "a swipe goes in one of four straight directions")
        suite.expect(Logic.direction(of: CGVector(dx: 80, dy: 80)) == .upRight && Logic.direction(of: CGVector(dx: -70, dy: -75)) == .downLeft,
               "or diagonally, toward a corner")
        suite.expect(Logic.direction(of: CGVector(dx: 30, dy: 20)) == nil, "a short movement is no swipe")

        suite.expect(Logic.gesture(for: .left, role: .none) == .layout(.leftHalf) && Logic.gesture(for: .right, role: .none) == .layout(.rightHalf),
               "left and right lay the window out on that half")
        suite.expect(Logic.gesture(for: .up, role: .none) == .layout(.maximize) && Logic.gesture(for: .down, role: .none) == .minimize,
               "up maximizes, down minimizes")
        suite.expect(Logic.gesture(for: .upLeft, role: .none) == .layout(.topLeft)
            && Logic.gesture(for: .downRight, role: .none) == .layout(.bottomRight),
               "a diagonal lays it out in that corner's quarter")
        suite.expect(Logic.gesture(for: .right, role: .screen) == .display(.right)
            && Logic.gesture(for: .up, role: .screen) == .display(.up)
            && Logic.gesture(for: .upLeft, role: .screen) == nil,
               "with the screen modifier, a straight swipe sends the window to the display that way")
        suite.expect(Logic.gesture(for: .down, role: .general) == .close && Logic.gesture(for: .up, role: .general) == .layout(.marginMaximize)
            && Logic.gesture(for: .left, role: .general) == nil,
               "with the general modifier, down closes and up almost fills the screen")
        suite.expect(Logic.gesture(for: .upLeft, role: .secondary) == .layout(.topLeftSixth)
            && Logic.gesture(for: .downRight, role: .secondary) == .layout(.bottomRightSixth)
            && Logic.gesture(for: .up, role: .secondary) == .layout(.topHalf)
            && Logic.gesture(for: .down, role: .secondary) == .layout(.bottomHalf)
            && Logic.gesture(for: .left, role: .secondary) == .layout(.leftThird),
               "with the secondary modifier: the 3×2 corners, the top and bottom halves, the side thirds")
        suite.expect(Logic.gesture(for: .upLeft, role: .tertiary) == .ninth(column: 0, row: 0)
            && Logic.gesture(for: .down, role: .tertiary) == .ninth(column: 1, row: 2)
            && Logic.gesture(for: .right, role: .tertiary) == .ninth(column: 2, row: 1),
               "with the tertiary modifier: the 3×3 grid's outer cells")
        suite.expect(Set(Logic.Direction.allCases.compactMap { Logic.gesture(for: $0, role: .tertiary) }.map { "\($0)" }).count == 8,
               "each of the eight directions reaches its own cell")

        var twice = Logic.Twice()
        suite.expect(twice.close(window: 7, at: 1) == .closeLater && twice.begin(window: 7, at: 1.2) && twice.holding
            && twice.close(window: 7, at: 1.7) == .quit && !twice.holding,
               "a second close starting on the same window right after the first quits its app")
        suite.expect(twice.close(window: 7, at: 5) == .closeLater && !twice.begin(window: 7, at: 6)
            && !twice.begin(window: 8, at: 5.1) && twice.close(window: 8, at: 6.1) == .closeLater,
               "too slow, or another window, and each one just closes")
        suite.expect(twice.close(window: 9, at: 10) == .closeLater && twice.begin(window: 9, at: 10.1)
            && twice.release() && !twice.release() && !twice.begin(window: 9, at: 10.2),
               "a held close happens once the second gesture turns out to be something else")

        let area = CGRect(x: 0, y: 25, width: 1512, height: 957)
        let cells = (0..<9).map { ForkSwishDisplays.ninth(column: $0 % 3, row: $0 / 3, in: area) }
        suite.expect(cells[0].minX == 0 && cells[0].minY == 25 && cells[8].maxX == 1512 && cells[8].maxY == 982
            && cells[0].maxX == cells[1].minX && cells[3].minY == cells[0].maxY,
               "the 3×3 cells cover the visible area edge to edge")

        suite.expect(Logic.gesture(forPinch: -0.5) == .close && Logic.gesture(forPinch: 0.5) == .layout(.fullScreen)
            && Logic.gesture(forPinch: 0.1) == nil && Logic.gesture(forPinch: .nan) == nil,
               "pinched closed the window closes, spread open it goes full screen, a small pinch does nothing")

        suite.expect(Logic.Phase(raw: 1) == .began && Logic.Phase(raw: 128) == .began && Logic.Phase(raw: 2) == .changed
            && Logic.Phase(raw: 4) == .ended && Logic.Phase(raw: 8) == .cancelled && Logic.Phase(raw: 0) == .other,
               "the trackpad's phases are read")
        var tracker = Logic.Tracker()
        tracker.add(CGVector(dx: 30, dy: 2))
        tracker.add(CGVector(dx: 40, dy: -1))
        tracker.add(magnification: 0.2)
        tracker.add(magnification: .nan)
        suite.expect(tracker.travel == CGVector(dx: 70, dy: 1) && tracker.magnification == 0.2,
               "a gesture adds up its movements")

        for key in [DefaultsKey.forkTitleBarSwipe, DefaultsKey.forkTitleBarPinch] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) is on by default and travels in backups")
        }
    }
}
