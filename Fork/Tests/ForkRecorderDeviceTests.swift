// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The microphone a recording uses, and where its camera bubble goes.
enum ForkRecorderDeviceTests {
    typealias Microphone = ForkRecorderMicrophone

    static func run(_ suite: TestSuite) {
        microphone(suite)
        cameraBubble(suite)
    }

    private static func microphone(_ suite: TestSuite) {
        let mac = Microphone.Device(id: "mac", name: "Micro MacBook Pro", isBuiltIn: true)
        let headset = Microphone.Device(id: "pods", name: "AirPods", isBuiltIn: false)
        let usb = Microphone.Device(id: "usb", name: "Yeti", isBuiltIn: false)
        let all = [usb, headset, mac]

        suite.expect(Microphone.ordered(all) == [mac, headset, usb],
               "the Mac's own microphone comes first, the others follow by name")
        suite.expect(Microphone.selected(storedID: "", among: all) == mac,
               "with nothing chosen, the Mac's microphone is used")
        suite.expect(Microphone.selected(storedID: "usb", among: all) == usb, "a chosen microphone is used")
        suite.expect(Microphone.selected(storedID: "usb", among: [headset, mac]) == mac,
               "a chosen microphone that is unplugged falls back to the Mac's")
        suite.expect(Microphone.selected(storedID: "", among: [usb, headset]) == headset,
               "a Mac without a microphone of its own uses the first there is")
        suite.expect(Microphone.selected(storedID: "mac", among: []) == nil, "no microphone, nothing to use")

        // One click at a time: off, the Mac's, each other one, off again.
        var state = Microphone.Choice(enabled: false, id: "")
        var walk: [String] = []
        for _ in 0..<5 {
            state = Microphone.next(enabled: state.enabled, storedID: state.id, among: all)
            walk.append(state.enabled ? state.id : "off")
        }
        suite.expect(walk == ["mac", "pods", "usb", "off", "mac"],
               "clicking walks from off through every microphone and back to off")
        suite.expect(Microphone.next(enabled: false, storedID: "usb", among: all) == .init(enabled: true, id: "mac"),
               "switching the microphone back on starts with the Mac's")
        suite.expect(Microphone.next(enabled: true, storedID: "usb", among: all) == .init(enabled: false, id: "usb"),
               "past the last microphone it turns off, and remembers which one it was")
        suite.expect(Microphone.next(enabled: true, storedID: "x", among: []) == .init(enabled: false, id: "x")
            && Microphone.next(enabled: false, storedID: "x", among: []) == .init(enabled: true, id: "x"),
               "with no microphone listed it is a plain switch")

        let key = DefaultsKey.forkRecorderMicrophoneID
        suite.expect(key.hasPrefix("fork"), "the microphone preference carries the fork prefix")
        suite.expect(Defaults.registeredDefaults[key] == nil && !SettingsBackupSupport.exportKeys().contains(key),
               "a microphone belongs to one Mac: its choice is not registered, so it stays out of backups")
        let camera = DefaultsKey.forkRecorderCamera
        suite.expect(Defaults.registeredDefaults[camera] as? Bool == false && SettingsBackupSupport.exportKeys().contains(camera),
               "the camera bubble is off by default, and its preference travels in backups")
    }

    private static func cameraBubble(_ suite: TestSuite) {
        typealias Layout = ForkCameraBubbleLayout
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let full = Layout.defaultSize

        let area = CGRect(x: 200, y: 200, width: 900, height: 600)
        let bubble = Layout.frame(shape: .circle, size: full, in: area, screen: screen)
        suite.expect(bubble.size == CGSize(width: full, height: full), "a roomy area gets the bubble at its remembered size")
        suite.expect(bubble.maxX == area.maxX - Layout.margin && bubble.minY == area.minY + Layout.margin,
               "the bubble sits in the area's bottom right corner")
        suite.expect(area.contains(bubble), "inside the area, so it is in the video")

        let small = CGRect(x: 300, y: 300, width: 220, height: 140)
        let reduced = Layout.frame(shape: .circle, size: full, in: small, screen: screen)
        suite.expect(reduced.width < full && reduced.width >= Layout.smallestSize && small.contains(reduced),
               "a small area gets a smaller bubble that still fits in it")

        let tiny = CGRect(x: 300, y: 300, width: 50, height: 40)
        suite.expect(Layout.frame(shape: .circle, size: full, in: tiny, screen: screen).width == Layout.smallestSize,
               "the bubble never shrinks below its smallest size")

        let edge = CGRect(x: 1400, y: -40, width: 400, height: 300)
        suite.expect(screen.contains(Layout.frame(shape: .circle, size: full, in: edge, screen: screen)),
               "an area running off the display still gets a bubble on the display")
        suite.expect(Layout.frame(shape: .circle, size: full, in: screen, screen: screen).maxX == screen.maxX - Layout.margin,
               "a full-screen recording puts the bubble in the display's bottom right corner")

        // Shapes.
        suite.expect(Layout.Shape.allCases == [.circle, .square, .rectangle]
            && Layout.Shape.circle.next == .square && Layout.Shape.square.next == .rectangle
            && Layout.Shape.rectangle.next == .circle,
               "a click on the shape item walks round, square, rectangle, and round again")
        suite.expect(Layout.shape(stored: "rectangle") == .rectangle && Layout.shape(stored: "star") == .circle
            && Layout.shape(stored: nil) == .circle,
               "the remembered shape is read back; anything else is round")
        let wide = Layout.frame(shape: .rectangle, size: full, in: area, screen: screen)
        suite.expect(wide.height == full && wide.width == (full * 16 / 9).rounded() && area.contains(wide)
            && wide.maxX == area.maxX - Layout.margin,
               "the rectangle is a landscape 16:9 of the same height, in the same corner")
        suite.expect(Layout.frame(shape: .square, size: full, in: area, screen: screen).size == bubble.size,
               "the square is as large as the round bubble")
        let narrow = CGRect(x: 300, y: 300, width: 240, height: 500)
        let fitted = Layout.frame(shape: .rectangle, size: full, in: narrow, screen: screen)
        suite.expect(narrow.contains(fitted) && abs(fitted.width / fitted.height - 16.0 / 9.0) < 0.02,
               "in a narrow area the rectangle shrinks to fit, keeping its proportions")
        suite.expect(Layout.cornerRadius(shape: .circle, height: 160) == 80
            && Layout.cornerRadius(shape: .square, height: 160) == Layout.cornerRadius
            && Layout.cornerRadius(shape: .rectangle, height: 40) == 10,
               "round is half the height; the others have rounded corners, gentler on a small bubble")

        // Sizes.
        suite.expect(Layout.size(stored: 0) == full && Layout.size(stored: .nan) == full
            && Layout.size(stored: 20) == Layout.smallestSize && Layout.size(stored: 5_000) == Layout.largestSize
            && Layout.size(stored: 240) == 240,
               "the remembered size stays between the smallest and the largest; no size means the default")
        let centered = CGRect(x: 600, y: 400, width: 160, height: 160)
        let grown = Layout.scaled(centered, shape: .circle, by: 1.5, within: screen)
        suite.expect(grown.size == CGSize(width: 240, height: 240) && grown.midX == centered.midX
            && grown.midY == centered.midY,
               "resizing grows the bubble around its center")
        suite.expect(Layout.scaled(centered, shape: .circle, by: 0.01, within: screen).height == Layout.smallestSize
            && Layout.scaled(centered, shape: .circle, by: 50, within: screen).height == Layout.largestSize,
               "a resize stops at the smallest and at the largest size")
        let lowScreen = CGRect(x: 0, y: 0, width: 1280, height: 300)
        suite.expect(Layout.scaled(CGRect(x: 100, y: 50, width: 160, height: 160), shape: .circle, by: 50,
                                   within: lowScreen).height == 300,
               "nor does it grow past what the display can show")
        let corner = CGRect(x: 1400, y: 10, width: 100, height: 100)
        suite.expect(screen.contains(Layout.scaled(corner, shape: .circle, by: 3, within: screen)),
               "a bubble grown near the display's edge is moved back inside it")
        let wideGrown = Layout.scaled(CGRect(x: 500, y: 400, width: 284, height: 160), shape: .rectangle, by: 2,
                                      within: screen)
        suite.expect(wideGrown.height == 320 && wideGrown.width == (320 * 16.0 / 9.0).rounded(),
               "the rectangle keeps its proportions when resized")
        let reshaped = Layout.reshaped(centered, to: .rectangle, within: screen)
        suite.expect(reshaped.height == 160 && reshaped.width == 284 && reshaped.midX == centered.midX
            && reshaped.midY == centered.midY,
               "a change of shape keeps the height and the center")
        suite.expect(screen.contains(Layout.reshaped(CGRect(x: 1340, y: 400, width: 160, height: 160), to: .rectangle,
                                                     within: screen)),
               "a bubble turned into a rectangle near the display's edge stays on the display")

        // Where a press resizes and where it moves.
        let round = CGSize(width: 160, height: 160)
        suite.expect(!Layout.isOnEdge(CGPoint(x: 80, y: 80), in: round, shape: .circle)
            && Layout.isOnEdge(CGPoint(x: 155, y: 80), in: round, shape: .circle)
            && Layout.isOnEdge(CGPoint(x: 4, y: 4), in: round, shape: .circle),
               "the round bubble moves from its middle, resizes from its border and from its empty corners")
        let panel = CGSize(width: 284, height: 160)
        suite.expect(!Layout.isOnEdge(CGPoint(x: 142, y: 80), in: panel, shape: .rectangle)
            && Layout.isOnEdge(CGPoint(x: 142, y: 5), in: panel, shape: .rectangle)
            && Layout.isOnEdge(CGPoint(x: 280, y: 80), in: panel, shape: .rectangle),
               "the rectangle moves from its middle and resizes from any side")
        suite.expect(!Layout.isOnEdge(CGPoint(x: 30, y: 30), in: CGSize(width: 60, height: 60), shape: .square),
               "the smallest bubble still has a middle to move it by")
        let middle = CGPoint(x: 100, y: 100)
        suite.expect(abs(Layout.resizeFactor(from: CGPoint(x: 180, y: 100), to: CGPoint(x: 220, y: 100), center: middle) - 1.5) < 0.001
            && Layout.resizeFactor(from: middle, to: CGPoint(x: 300, y: 100), center: middle) == 1,
               "dragging the border away from the center grows the bubble by as much; a drag from the center does nothing")

        for (key, value) in [(DefaultsKey.forkRecorderCameraShape, "circle" as AnyHashable),
                             (DefaultsKey.forkRecorderCameraSize, Double(full) as AnyHashable)] {
            suite.expect(Defaults.registeredDefaults[key] as? AnyHashable == value
                && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) has its default and travels in backups")
        }

        // A clicked window is recorded from its own buffer, where the bubble is not.
        let window = RecorderSupport.Region(displayID: 1, windowID: 42,
                                            pixelRect: CGRect(x: 100, y: 80, width: 800, height: 600),
                                            anchorRect: CGRect(x: 50, y: 300, width: 400, height: 300), scale: 2)
        let filmed = ForkRecorderOptions.recordedRegion(window, withCamera: true)
        suite.expect(filmed.windowID == nil && filmed.pixelRect == window.pixelRect
            && filmed.anchorRect == window.anchorRect && filmed.displayID == 1 && filmed.scale == 2,
               "with the camera on, a clicked window is recorded as its area, so the bubble is in the video")
        suite.expect(ForkRecorderOptions.recordedRegion(window, withCamera: false) == window,
               "without the camera a clicked window keeps its own buffer")
        let drawn = ForkRecorderOptions.recordedRegion(filmed, withCamera: true)
        suite.expect(drawn == filmed, "a drawn area is recorded as it is")
    }
}
