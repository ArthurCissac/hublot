// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The editor's simpler crop: grips sized on screen, ratios, thirds.
enum ForkCropTests {
    typealias Geometry = ForkCropGeometry

    static func run(_ suite: TestSuite) {
        grips(suite)
        ratios(suite)
        drawing(suite)
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkEditorCrop] as? Bool == true,
                     "the simpler crop is on by default")
    }

    private static func grips(_ suite: TestSuite) {
        // A tall scrolling capture shown at 42 %: upstream's grips were 7 points wide there.
        let tall = CGRect(x: 0, y: 0, width: 1_443, height: 5_971)
        suite.expect(Geometry.grip(at: CGPoint(x: 5, y: 3_000), in: tall, zoom: 0.42) == .left,
                     "anywhere along an edge takes it, not only its middle")
        suite.expect(Geometry.grip(at: CGPoint(x: 1_440, y: 2), in: tall, zoom: 0.42) == .topRight,
                     "a corner wins over the two edges that meet there")
        suite.expect(Geometry.grip(at: CGPoint(x: 700, y: 3_000), in: tall, zoom: 0.42) == nil,
                     "the middle takes no grip")
        suite.expect(Geometry.grip(at: CGPoint(x: 700, y: 5_981), in: tall, zoom: 0.42) == .bottom,
                     "a press just outside an edge still takes it")

        let rect = CGRect(x: 0, y: 0, width: 400, height: 400)
        suite.expect(Geometry.grip(at: CGPoint(x: 6, y: 200), in: rect, zoom: 2) == nil
            && Geometry.grip(at: CGPoint(x: 6, y: 200), in: rect, zoom: 0.5) == .left,
                     "the zone is the same on screen whatever the zoom: 12 points away is too far, 3 is close")

        let small = CGRect(x: 100, y: 100, width: 20, height: 20)
        suite.expect(Geometry.grip(at: CGPoint(x: 110, y: 110), in: small, zoom: 1) == nil
            && Geometry.grip(at: CGPoint(x: 101, y: 110), in: small, zoom: 1) == .left,
                     "inside a small crop the middle still moves it, its edges still resize it")
    }

    private static func ratios(_ suite: TestSuite) {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        let square = CGRect(x: 0, y: 0, width: 100, height: 100)
        suite.expect(Geometry.resized(square, dragging: .bottomRight, to: CGPoint(x: 300, y: 150),
                                      ratio: nil, within: bounds)
            == ScreenshotSupport.resizedRect(square, dragging: .bottomRight, to: CGPoint(x: 300, y: 150)),
                     "without a ratio an edge follows the pointer as upstream's does")
        suite.expect(Geometry.resized(square, dragging: .bottomRight, to: CGPoint(x: 300, y: 150),
                                      ratio: 1, within: bounds) == CGRect(x: 0, y: 0, width: 300, height: 300),
                     "a corner keeps the ratio from the opposite corner, following the larger move")
        suite.expect(Geometry.resized(square, dragging: .bottomRight, to: CGPoint(x: 300, y: 150),
                                      ratio: 1, within: CGRect(x: 0, y: 0, width: 200, height: 1_000))
            == CGRect(x: 0, y: 0, width: 200, height: 200),
                     "and stops at the picture's edge without losing it")
        let wide = CGRect(x: 100, y: 100, width: 160, height: 90)
        suite.expect(Geometry.resized(wide, dragging: .right, to: CGPoint(x: 420, y: 0), ratio: 16.0 / 9, within: bounds)
            == CGRect(x: 100, y: 55, width: 320, height: 180),
                     "an edge sets its size, the other follows the ratio around the middle")

        suite.expect(Geometry.Ratio.free.value(imageSize: CGSize(width: 10, height: 10)) == nil
            && abs((Geometry.Ratio.original.value(imageSize: CGSize(width: 1_443, height: 5_971)) ?? 0) - 1_443.0 / 5_971) < 1e-9
            && Geometry.Ratio.nineSixteen.label == "9:16",
                     "free has no ratio, original is the picture's own, the others are named")
        suite.expect(Geometry.fitted(ratio: 1, in: CGRect(x: 0, y: 0, width: 200, height: 100))
            == CGRect(x: 50, y: 0, width: 100, height: 100)
            && Geometry.fitted(ratio: nil, in: wide) == wide,
                     "a ratio picked fits the largest crop of it in the middle of the current one")
        suite.expect(Geometry.drawn(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 400, y: 450), ratio: 2, within: bounds)
            == CGRect(x: 400, y: 450, width: 100, height: 50),
                     "a crop drawn up and left keeps the ratio too")
    }

    private static func drawing(_ suite: TestSuite) {
        let thirds = Geometry.thirds(of: CGRect(x: 0, y: 0, width: 300, height: 90))
        suite.expect(thirds.vertical == [100, 200] && thirds.horizontal == [30, 60], "the thirds cut the crop in nine")

        let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let rects = Geometry.gripRects(in: frame)
        suite.expect(rects.count == 12 && rects.allSatisfy { frame.contains($0) },
                     "two bars per corner and one per edge, all inside the frame")
        let tiny = CGRect(x: 0, y: 0, width: 30, height: 30)
        suite.expect(Geometry.gripRects(in: tiny).allSatisfy { tiny.contains($0) },
                     "on a small frame the grips shrink instead of spilling out")
        suite.expect(Geometry.sizeLabel(CGRect(x: 0, y: 0, width: 1_443.4, height: 2_000)) == "1443 × 2000",
                     "the size reads in whole pixels")

        var taps = Geometry.TapTracker()
        let point = CGPoint(x: 50, y: 50)
        suite.expect(!taps.isDouble(at: point, time: 0, interval: 0.4, slop: 4)
            && taps.isDouble(at: CGPoint(x: 52, y: 51), time: 0.2, interval: 0.4, slop: 4),
                     "two clicks close in time and place make a double click")
        suite.expect(!taps.isDouble(at: point, time: 0.3, interval: 0.4, slop: 4),
                     "a third click starts afresh")
        suite.expect(!taps.isDouble(at: CGPoint(x: 90, y: 50), time: 0.5, interval: 0.4, slop: 4),
                     "a click far from the last one is not a double click")
    }
}
