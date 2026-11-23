// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The capture menu's framed area: moved, resized, shaped, remembered.
enum ForkCaptureAreaTests {
    typealias Geometry = ForkCaptureAreaGeometry

    static func run(_ suite: TestSuite) {
        let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let area = CGRect(x: 400, y: 300, width: 600, height: 400)

        suite.expect(Geometry.formats.first == .free && Geometry.formats.count == 7
            && Geometry.nextFormat(after: Geometry.formats.last!) == .free,
               "the format item walks free, 1:1, 4:3, 16:9, 9:16, 1280×720, 1920×1080, then free again")
        suite.expect(Geometry.Format.ratio(width: 16, height: 9).label == "16:9"
            && Geometry.Format.pixels(width: 1920, height: 1080).label == "1920×1080" && Geometry.Format.free.label == nil,
               "the bar names each format")

        suite.expect(Geometry.handle(at: CGPoint(x: 700, y: 500), in: area) == nil, "a press inside moves the area")
        suite.expect(Geometry.handle(at: CGPoint(x: 402, y: 500), in: area) == .init(horizontal: -1, vertical: 0)
            && Geometry.handle(at: CGPoint(x: 1004, y: 698), in: area) == .init(horizontal: 1, vertical: 1),
               "a press on an edge or a corner takes hold of it")
        suite.expect(Geometry.handle(at: CGPoint(x: 100, y: 100), in: area) == nil, "a press far outside is not a handle")

        suite.expect(Geometry.moved(area, by: CGSize(width: 50, height: -20), within: bounds) == CGRect(x: 450, y: 280, width: 600, height: 400),
               "dragging moves the area")
        suite.expect(Geometry.moved(area, by: CGSize(width: 2_000, height: 2_000), within: bounds).maxX == bounds.maxX,
               "but never off the display")

        let wider = Geometry.resized(area, handle: .init(horizontal: 1, vertical: 0), to: CGPoint(x: 1100, y: 500),
                                     within: bounds, aspect: nil, square: false)
        suite.expect(wider == CGRect(x: 400, y: 300, width: 700, height: 400), "dragging the right edge widens, the left stays")
        let tiny = Geometry.resized(area, handle: .init(horizontal: -1, vertical: -1), to: CGPoint(x: 2_000, y: 2_000),
                                    within: bounds, aspect: nil, square: false)
        suite.expect(tiny.width == Geometry.minimumSide && tiny.height == Geometry.minimumSide, "an area never folds below its smallest side")
        let held = Geometry.resized(area, handle: .init(horizontal: 1, vertical: 1), to: CGPoint(x: 1200, y: 650),
                                    within: bounds, aspect: 16.0 / 9.0, square: false)
        suite.expect(abs(held.width / held.height - 16.0 / 9.0) < 0.02 && held.minX == 400 && held.minY == 300,
               "with a ratio, a corner resize keeps the shape and the opposite corner")
        let squared = Geometry.resized(area, handle: .init(horizontal: 1, vertical: 0), to: CGPoint(x: 900, y: 500),
                                       within: bounds, aspect: nil, square: true)
        suite.expect(squared.width == squared.height, "Shift makes it a square")

        let sixteenNine = Geometry.applying(.ratio(width: 16, height: 9), to: area, within: bounds, scale: 2)
        suite.expect(abs(sixteenNine.width / sixteenNine.height - 16.0 / 9.0) < 0.02
            && abs(sixteenNine.midX - area.midX) <= 1 && abs(sixteenNine.midY - area.midY) <= 1,
               "a ratio reshapes the area around its center")
        suite.expect(abs(sixteenNine.width * sixteenNine.height - area.width * area.height) / (area.width * area.height) < 0.02,
               "keeping about the same surface")
        let hd = Geometry.applying(.pixels(width: 1280, height: 720), to: area, within: bounds, scale: 2)
        suite.expect(hd.size == CGSize(width: 640, height: 360), "a pixel size is the display's pixels: 1280×720 is 640×360 points on Retina")
        let full = Geometry.applying(.pixels(width: 1920, height: 1080), to: area, within: bounds, scale: 1)
        suite.expect(bounds.contains(full) && abs(full.width / full.height - 16.0 / 9.0) < 0.02,
               "a size larger than the display is brought down to it, keeping its ratio")
        suite.expect(Geometry.applying(.free, to: area, within: bounds, scale: 2) == area, "free leaves the area as it is")

        suite.expect(Geometry.sizeLabel(for: area, scale: 2) == "1200 × 800", "the frame shows the size in pixels")

        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let region = Geometry.region(anchor: CGRect(x: 100.25, y: 200, width: 301, height: 150), screenFrame: screen,
                                     displayID: 7, scale: 2)
        suite.expect(region.displayID == 7 && region.windowID == nil && region.scale == 2,
               "the region names its display and no window")
        suite.expect(region.pixelRect.width.truncatingRemainder(dividingBy: 2) == 0
            && region.pixelRect.minY == (982 - 350) * 2,
               "in whole, even pixels, counted from the display's top")
        suite.expect(abs(region.anchorRect.width - region.pixelRect.width / 2) < 0.001
            && abs(region.anchorRect.maxY - 350) < 1,
               "and its points recomputed from those pixels")
        let second = Geometry.region(anchor: CGRect(x: 1600, y: 100, width: 200, height: 100),
                                     screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), displayID: 9, scale: 1)
        suite.expect(second.pixelRect.minX == 88 && second.pixelRect.minY == 880, "on a second display, counted from that display's corner")

        suite.expect(Geometry.decoded(Geometry.encoded(area)) == area, "a remembered area is read back")
        suite.expect(Geometry.decoded("1,2,3") == nil && Geometry.decoded("0,0,10,10") == nil && Geometry.decoded(nil) == nil,
               "a damaged or too small one is ignored")

        let key = DefaultsKey.forkCaptureMenuLastArea
        suite.expect(Defaults.registeredDefaults[key] == nil && !SettingsBackupSupport.exportKeys().contains(key),
               "the remembered area belongs to this Mac's displays: it stays out of backups")
        let framed = CGRect(x: 100, y: 100, width: 400, height: 300)
        suite.expect(ForkCaptureAreaGeometry.cursor(at: CGPoint(x: 50, y: 50), in: framed) == .arrow
            && ForkCaptureAreaGeometry.cursor(at: CGPoint(x: 300, y: 250), in: framed) == .arrow
            && ForkCaptureAreaGeometry.cursor(at: CGPoint(x: 100, y: 100), in: framed) == .arrow,
               "a framed area shows the ordinary arrow outside, inside and on its corners: the crosshair is for drawing")
        suite.expect(ForkCaptureAreaGeometry.cursor(at: CGPoint(x: 102, y: 250), in: framed) == .resizeLeftRight
            && ForkCaptureAreaGeometry.cursor(at: CGPoint(x: 300, y: 399), in: framed) == .resizeUpDown,
               "an edge shows the way it resizes")
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        suite.expect(ForkCaptureAreaGeometry.isNearlyWholeDisplay(display, screen: display)
            && ForkCaptureAreaGeometry.isNearlyWholeDisplay(CGRect(x: 0, y: 25, width: 1512, height: 957), screen: display)
            && !ForkCaptureAreaGeometry.isNearlyWholeDisplay(CGRect(x: 100, y: 100, width: 800, height: 500), screen: display),
               "an area covering nearly the whole display is told apart from a zone")
    }
}
