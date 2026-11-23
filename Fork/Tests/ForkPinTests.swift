// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// A pinned capture: which buttons it has room for, and how it grows and shrinks.
enum ForkPinTests {
    typealias Layout = ForkPinLayout

    static func run(_ suite: TestSuite) {
        controls(suite)
        zoom(suite)
    }

    private static func controls(_ suite: TestSuite) {
        let all = Layout.Control.allCases
        suite.expect(all == [.close, .restore, .edit, .save, .drag, .shrink, .enlarge],
               "the bar lists its seven controls in order")
        let full = Layout.barWidth(for: all) + 2 * Layout.margin
        suite.expect(Layout.controls(forPinWidth: full) == all, "a pin just wide enough shows the whole bar")
        suite.expect(Layout.controls(forPinWidth: 600) == all, "a wide pin shows the whole bar")
        suite.expect(Layout.controls(forPinWidth: full - 1) == [.close, .enlarge],
               "a pin one point too narrow keeps closing and enlarging")
        suite.expect(Layout.controls(forPinWidth: 90) == [.close, .enlarge],
               "upstream's smallest pin still has room for those two")
        suite.expect(Layout.controls(forPinWidth: 40).isEmpty, "a pin narrower than any bar shows none")
        suite.expect(Layout.barWidth(for: []) == 2 * Layout.barPadding, "an empty bar is only its padding")
    }

    private static func zoom(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 900)
        let minimum = CGSize(width: 90, height: 60)
        let pin = CGRect(x: 600, y: 350, width: 300, height: 200)

        let larger = Layout.resized(pin, by: Layout.zoomStep, minimum: minimum, within: screen)
        suite.expect(larger.size == CGSize(width: 375, height: 250), "one step enlarges by a quarter, both ways")
        // Frames land on whole points, so the center may move by half a point.
        suite.expect(abs(larger.midX - pin.midX) <= 0.5 && abs(larger.midY - pin.midY) <= 0.5,
               "the pin grows around its center")

        let smaller = Layout.resized(pin, by: 1 / Layout.zoomStep, minimum: minimum, within: screen)
        suite.expect(smaller.size == CGSize(width: 240, height: 160), "one step back shrinks by a fifth")
        suite.expect(abs(smaller.width / smaller.height - pin.width / pin.height) < 0.01, "the proportions are kept")

        let tiny = CGRect(x: 700, y: 400, width: 99, height: 66)
        let floor = Layout.resized(tiny, by: 0.5, minimum: minimum, within: screen)
        suite.expect(floor.width >= minimum.width && floor.height >= minimum.height,
               "shrinking stops at the smallest pin")

        let big = CGRect(x: 100, y: 50, width: 1350, height: 810)
        let ceiling = Layout.resized(big, by: Layout.zoomStep, minimum: minimum, within: screen)
        suite.expect(ceiling.width <= screen.width && ceiling.height <= screen.height,
               "enlarging stops at what the display can show")
        suite.expect(screen.contains(ceiling), "a pin at its largest sits inside the display")

        let corner = CGRect(x: 1300, y: 760, width: 180, height: 120)
        let moved = Layout.resized(corner, by: Layout.zoomStep, minimum: minimum, within: screen)
        suite.expect(screen.contains(moved), "a pin enlarged near a corner is moved back inside the display")

        suite.expect(Layout.resized(pin, by: 0, minimum: minimum, within: screen) == pin
            && Layout.resized(.zero, by: 2, minimum: minimum, within: screen) == .zero,
               "a meaningless request changes nothing")
    }
}
