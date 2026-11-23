// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The card-style capture preview: where the cards go and what a click on a
/// card means.
enum ForkPreviewCardTests {
    typealias Layout = ForkPreviewCardLayout

    static func run(_ suite: TestSuite) {
        placement(suite)
        displayChoice(suite)
        controls(suite)
        preferences(suite)
    }

    private static func placement(_ suite: TestSuite) {
        // An external display above and left of the main one, as measured.
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: -215, y: 982, width: 1920, height: 1080)

        suite.expect(Layout.cardFrame(index: 0, in: main) == CGRect(x: 40, y: 100, width: 210, height: 150),
               "the first card sits 40 points from the left edge and 100 from the bottom")
        suite.expect(Layout.cardFrame(index: 0, in: external) == CGRect(x: -175, y: 1082, width: 210, height: 150),
               "the margins are taken from the display's own origin, not from the main display's")
        suite.expect(Layout.cardFrame(index: 1, in: main).minY == 260
            && Layout.cardFrame(index: 2, in: main).minY == 420,
               "each newer card sits above the previous one, 10 points apart")
        suite.expect(Layout.cardFrame(index: 1, in: main).minX == Layout.cardFrame(index: 0, in: main).minX,
               "stacked cards share one column")
        suite.expect(Layout.cardFrame(index: -3, in: main) == Layout.cardFrame(index: 0, in: main),
               "a negative position is the bottom of the stack")

        suite.expect(Layout.capacity(in: external) == 6, "a 1080-point display stacks six cards")
        let highest = Layout.cardFrame(index: Layout.capacity(in: external) - 1, in: external)
        suite.expect(highest.maxY <= external.maxY - Layout.topReserve,
               "the highest card of a full stack stays below the reserved top")
        let oneTooMany = Layout.cardFrame(index: Layout.capacity(in: external), in: external)
        suite.expect(oneTooMany.maxY > external.maxY - Layout.topReserve,
               "one more card would not fit: the capacity is exact")
        suite.expect(Layout.capacity(in: CGRect(x: 0, y: 0, width: 800, height: 120)) == 1,
               "even a display too short for the margins shows one card")

        // A full stack makes room for a newcomer by letting its oldest card go.
        suite.expect(Layout.overflow(count: 3, capacity: 6) == 0, "a stack with room lets nothing go")
        suite.expect(Layout.overflow(count: 6, capacity: 6) == 0, "a stack exactly full still fits")
        suite.expect(Layout.overflow(count: 7, capacity: 6) == 1, "one card too many: the oldest leaves")
        suite.expect(Layout.overflow(count: 6, capacity: 5) == 1 && Layout.overflow(count: 6, capacity: 2) == 4,
               "moving to a smaller display lets go as many as no longer fit")
        suite.expect(Layout.overflow(count: 2, capacity: 0) == 1, "a display always keeps at least one card")

        let frame = Layout.cardFrame(index: 0, in: main)
        let resting = Layout.restingOffsetFrame(for: frame)
        suite.expect(resting.size == frame.size && resting.minY == frame.minY && resting.minX < frame.minX
            && resting.minX >= main.minX,
               "a card slides in from the edge side without leaving its display")
    }

    private static func displayChoice(_ suite: TestSuite) {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: -215, y: 982, width: 1920, height: 1080)
        let screens = [main, external]

        suite.expect(Layout.screenFrame(pointer: CGPoint(x: 700, y: 400), screenFrames: screens) == main,
               "the previews go to the display under the pointer")
        suite.expect(Layout.screenFrame(pointer: CGPoint(x: 600, y: 1500), screenFrames: screens) == external,
               "the pointer on the second display sends them there")
        suite.expect(Layout.screenFrame(pointer: CGPoint(x: 1600, y: 500), screenFrames: screens) == main,
               "a pointer beside a display, on none, gets the nearest one")
        suite.expect(Layout.screenFrame(pointer: CGPoint(x: -4000, y: 5000), screenFrames: screens) == external,
               "far from every display, still the nearest one")
        suite.expect(Layout.screenFrame(pointer: .zero, screenFrames: []) == nil,
               "no display, no place for a preview")
    }

    private static func controls(_ suite: TestSuite) {
        let card = CGRect(origin: .zero, size: Layout.cardSize)
        let frames = Layout.Control.allCases.map(Layout.controlFrame)

        suite.expect(frames.allSatisfy { card.contains($0) }, "every control lies inside the card")
        var overlaps = false
        for (index, frame) in frames.enumerated() {
            for other in frames.dropFirst(index + 1) where frame.insetBy(dx: -3, dy: -3).intersects(other.insetBy(dx: -3, dy: -3)) {
                overlaps = true
            }
        }
        suite.expect(!overlaps, "no two controls overlap, slack included: a click means one thing")

        for control in Layout.Control.allCases {
            let frame = Layout.controlFrame(control)
            suite.expect(Layout.control(at: CGPoint(x: frame.midX, y: frame.midY)) == control,
                   "the center of \(control) hits \(control)")
        }
        let close = Layout.controlFrame(.close)
        suite.expect(Layout.control(at: CGPoint(x: close.minX - 2, y: close.midY)) == .close,
               "a click a hair outside a small control still counts")
        suite.expect(Layout.control(at: CGPoint(x: close.maxX + 12, y: close.maxY + 12)) == nil,
               "a click on the picture, between the controls, hits none")
        suite.expect(Layout.control(at: CGPoint(x: -20, y: -20)) == nil, "outside the card, nothing")

        suite.expect(Layout.controlFrame(.copy).midX == card.midX && Layout.controlFrame(.save).midX == card.midX,
               "Copy and Save are centered")
        suite.expect(Layout.controlFrame(.copy).maxY < Layout.controlFrame(.save).minY, "Copy sits above Save")
        suite.expect(Layout.controlFrame(.close).minX < Layout.controlFrame(.pin).minX
            && Layout.controlFrame(.close).minY == Layout.controlFrame(.pin).minY,
               "Close and Pin share the top row, Close on the left")
        suite.expect(Layout.controlFrame(.edit).minY == Layout.controlFrame(.discard).minY
            && Layout.controlFrame(.edit).minY > Layout.controlFrame(.close).maxY,
               "Edit and Discard share the bottom row")

        // A click means a control only while the controls are drawn; anywhere
        // else, and on a card that is not hovered, it means the picture.
        let pin = Layout.controlFrame(.pin)
        let onPin = CGPoint(x: pin.midX, y: pin.midY)
        suite.expect(Layout.clickTarget(at: onPin, controlsVisible: true) == .control(.pin),
               "a click on a drawn control is that control")
        suite.expect(Layout.clickTarget(at: onPin, controlsVisible: false) == .picture,
               "a click where a hidden control would be is a click on the picture")
        suite.expect(Layout.clickTarget(at: CGPoint(x: card.midX, y: 20), controlsVisible: true) == .picture,
               "a click between the controls is a click on the picture")

        // The picture fills the card, cropped evenly on the overflowing sides.
        let wide = Layout.fillRect(imageSize: CGSize(width: 900, height: 220), in: card)
        suite.expect(wide.height == card.height && wide.width > card.width && wide.midX == card.midX,
               "a wide capture keeps its height and is cropped left and right")
        let tall = Layout.fillRect(imageSize: CGSize(width: 300, height: 640), in: card)
        suite.expect(tall.width == card.width && tall.height > card.height && tall.midY == card.midY,
               "a tall capture keeps its width and is cropped top and bottom")
        suite.expect(Layout.fillRect(imageSize: CGSize(width: 420, height: 300), in: card) == card,
               "a capture of the card's shape fills it exactly")
        suite.expect(Layout.fillRect(imageSize: .zero, in: card) == card,
               "an empty picture does not divide by zero")

        let start = CGPoint(x: 100, y: 70)
        suite.expect(!Layout.isDrag(from: start, to: CGPoint(x: 102, y: 72)),
               "a press that barely moves is still a click")
        suite.expect(Layout.isDrag(from: start, to: CGPoint(x: 104, y: 70))
            && Layout.isDrag(from: start, to: CGPoint(x: 97, y: 67)),
               "past the threshold, in any direction, it is a drag of the capture")
    }

    private static func preferences(_ suite: TestSuite) {
        let key = DefaultsKey.forkScreenshotPreviewCard
        suite.expect(key.hasPrefix("fork"), "the card preference carries the fork prefix")
        suite.expect(Defaults.registeredDefaults[key] as? Bool == true,
               "the card is the capture preview by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(key),
               "the card preference travels in backups")
    }
}
