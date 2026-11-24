// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The scrolling capture's auto-scroll, steered by the pointer.
enum ForkCursorScrollTests {
    typealias Scroll = ForkCursorScroll

    static func run(_ suite: TestSuite) {
        let start = CGPoint(x: 400, y: 600)
        suite.expect(Scroll.distance(from: start, to: CGPoint(x: 400, y: 500), horizontal: false) == 100
            && Scroll.distance(from: start, to: CGPoint(x: 400, y: 650), horizontal: false) == -50,
            "going down counts up, going back up counts below zero (y upward)")
        suite.expect(Scroll.distance(from: start, to: CGPoint(x: 480, y: 100), horizontal: true) == 80,
            "a sideways capture counts what the pointer moved right, whatever its height")

        let top = Scroll.maxSpeed(areaLength: 800)
        suite.expect(top == 1_200 && Scroll.maxSpeed(areaLength: 20) == 120 && Scroll.maxSpeed(areaLength: 0) == 0,
            "the top speed is one and a half areas a second, with a floor for a tiny area")
        suite.expect(Scroll.speed(distance: -40, maxSpeed: top) == 0
            && Scroll.speed(distance: Scroll.deadZone, maxSpeed: top) == 0,
            "above the start line, or barely past it, nothing scrolls")
        let near = Scroll.speed(distance: 30, maxSpeed: top)
        let farther = Scroll.speed(distance: 90, maxSpeed: top)
        suite.expect(near > 0 && farther > near * 2,
            "further down is faster, and more than in proportion")
        suite.expect(Scroll.speed(distance: 2_000, maxSpeed: top) == top
            && Scroll.speed(distance: .infinity, maxSpeed: top) == 0,
            "never faster than the assembly follows, and a broken distance stops")

        var smoother = Scroll.Smoother()
        var eased: CGFloat = 0
        for _ in 0..<6 { eased = smoother.next(target: 600, interval: 1.0 / 60) }
        suite.expect(eased > 0 && eased < 600, "a sudden speed is reached gradually, not at once")
        for _ in 0..<30 { eased = smoother.next(target: 600, interval: 1.0 / 60) }
        suite.expect(abs(eased - 600) < 30, "and within half a second")
        for _ in 0..<60 { eased = smoother.next(target: 0, interval: 1.0 / 60) }
        suite.expect(eased == 0, "back at the start line the page stops, without creeping on")

        var accumulator = Scroll.Accumulator()
        var moved: Int32 = 0
        for _ in 0..<60 { moved += accumulator.step(speed: 30, interval: 1.0 / 60) }
        suite.expect(moved >= 29 && moved <= 30, "half a point per tick still moves 30 points a second")
        _ = accumulator.step(speed: 0, interval: 1.0 / 60)
        suite.expect(accumulator.carried == 0, "a stop drops what was carried over")
        suite.expect(accumulator.step(speed: 1e9, interval: 1) == 2_000,
            "one tick never scrolls a page away")

        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = CGSize(width: 300, height: 40)
        let middle = Scroll.controlsFrame(size: size, area: CGRect(x: 400, y: 200, width: 500, height: 400), screen: screen)
        suite.expect(middle.minY == 612 && middle.midX == 650, "the controls sit centred just above the area")
        let tall = Scroll.controlsFrame(size: size, area: CGRect(x: 400, y: 200, width: 500, height: 680), screen: screen)
        suite.expect(tall.maxY == 868, "with no room above, they go inside its top edge, never under it")
        let whole = Scroll.controlsFrame(size: size, area: screen, screen: screen)
        suite.expect(whole.maxY == 888 && whole.minY >= 0, "the same for an area as large as the display")
        let edge = Scroll.controlsFrame(size: size, area: CGRect(x: 1_300, y: 200, width: 140, height: 300), screen: screen)
        suite.expect(edge.maxX <= screen.maxX - 8, "and never off the side of the display")
    }
}
