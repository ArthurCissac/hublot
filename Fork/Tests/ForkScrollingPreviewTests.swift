// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The scrolling capture's live preview column.
enum ForkScrollingPreviewTests {
    typealias Layout = ForkScrollingPreviewLayout

    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let area = CGRect(x: 300, y: 100, width: 600, height: 700)
        let right = Layout.slot(area: area, screen: screen)
        suite.expect(right.minX == 912 && right.width == Layout.width && right.minY == 100 && right.height == 700,
                     "the column sits right of the area, as tall as it")
        let wideRight = Layout.slot(area: CGRect(x: 300, y: 100, width: 1_100, height: 700), screen: screen)
        suite.expect(wideRight.maxX == 288, "with no room on the right, it goes left")
        let whole = Layout.slot(area: screen, screen: screen)
        suite.expect(whole.maxX == screen.maxX - Layout.gap && whole.minY == 8 && whole.maxY == 892,
                     "with room on neither side, against the area's right edge, inside the display")

        let empty = Layout.frames(content: .zero, slot: right)
        suite.expect(empty.column.height == Layout.emptyHeight && empty.column.minY == right.minY && empty.image == .zero,
                     "before any picture, a short column at the bottom of the area")
        let short = Layout.frames(content: CGSize(width: 1_200, height: 800), slot: right)
        suite.expect(abs(short.image.width - 128) < 0.001 && abs(short.column.height - (short.image.height + 12)) < 0.001
            && short.column.minY == right.minY,
                     "a short picture takes the column's width and the column grows upward to hold it")
        let tall = Layout.frames(content: CGSize(width: 1_443, height: 20_000), slot: right)
        suite.expect(tall.column.height == right.height && abs(tall.image.height - 688) < 0.001
            && tall.image.width < 128 && abs(tall.image.midX - right.width / 2) < 0.001,
                     "a long picture shrinks to fit the column, centred")
        suite.expect(abs(tall.image.minY - Layout.inset) < 0.001, "and fills it from top to bottom")

        let heights = Layout.stripHeights([100, 300], filling: 80)
        suite.expect(heights == [20, 60] && Layout.stripHeights([], filling: 80).isEmpty,
                     "each strip keeps its share of the picture's height")

        var received = 0
        ForkScrollingPreviewFeed.send([])
        ForkScrollingPreviewFeed.setReceiver { received += $0.count + 1 }
        ForkScrollingPreviewFeed.send([])
        ForkScrollingPreviewFeed.setReceiver(nil)
        ForkScrollingPreviewFeed.send([])
        suite.expect(received == 1, "the capture's pictures reach the preview only while it listens")
    }
}
