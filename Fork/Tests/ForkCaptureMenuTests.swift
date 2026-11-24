// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The capture menu: which items its two bars list, where they sit, what a click
/// picks, and where the bar goes once an area is drawn.
enum ForkCaptureMenuTests {
    typealias Layout = ForkCaptureMenuLayout

    static func run(_ suite: TestSuite) {
        modes(suite)
        geometry(suite)
        placement(suite)
        timer(suite)
        preferences(suite)
    }

    private static func modes(_ suite: TestSuite) {
        let all = Layout.modes(available: ScreenCaptureTool.allCases)
        suite.expect(all == [.area, .fullScreen, .window, .scrolling, .timer, .text, .recording],
               "with every tool available the main bar lists its seven items, in order")
        suite.expect(Layout.modes(available: []).isEmpty, "no tool, no mode")
        suite.expect(Layout.modes(available: [.screenshot]) == [.area, .fullScreen, .window, .timer],
               "screenshots alone bring the area, the full screen, the window and the timer")
        suite.expect(!Layout.Mode.scrolling.needsArea && !Layout.Mode.scrolling.isSetting
            && Layout.Mode.scrolling.tool == .scrolling,
               "the scrolling item has no bar of its own: it starts a selection, whatever is framed")
        suite.expect(Layout.modes(available: [.color]).isEmpty,
               "the color picker is not a kind of capture: it adds no mode")
        suite.expect(Layout.recordingModes
            == [.record, .scopeArea, .scopeWindow, .scopeScreen, .microphone, .systemAudio, .mono, .clicks, .keys,
                .camera, .cameraShape, .countdown, .back],
               "the recording bar: start, what is filmed, the sound sources, mono, clicks, the camera and its shape, the countdown, back")
        suite.expect(!ForkCaptureSelectionGuide.isHidden,
               "upstream's hint bar shows on every selection the capture menu did not start")
        suite.expect(Layout.Mode.allCases.filter(\.isSetting)
            == [.timer, .microphone, .systemAudio, .mono, .clicks, .keys, .camera, .cameraShape, .countdown,
                .scopeArea, .scopeWindow, .scopeScreen],
               "twelve items change a setting and leave the bar open")
        settings(suite)
        suite.expect(Layout.Mode.allCases.filter(\.needsArea) == [.area, .text, .recording, .record],
               "four items act on the area drawn; the others do not need one")
    }

    private static func geometry(_ suite: TestSuite) {
        let all = Layout.modes(available: ScreenCaptureTool.allCases)
        let size = Layout.barSize(modes: all)
        suite.expect(size == CGSize(width: 458, height: 55), "the main bar is 458 by 55 points, as measured")

        for modes in [all, Layout.recordingModes] {
            let bar = CGRect(origin: .zero, size: Layout.barSize(modes: modes))
            let frames = modes.compactMap { Layout.itemFrame($0, in: modes) }
            suite.expect(frames.count == modes.count && frames.allSatisfy { bar.contains($0) },
                   "every item has its place inside its bar")
            var ordered = true
            for (left, right) in zip(frames, frames.dropFirst()) where left.maxX > right.minX { ordered = false }
            suite.expect(ordered, "the items follow one another without overlapping")
            for mode in modes {
                if let frame = Layout.itemFrame(mode, in: modes) {
                    suite.expect(Layout.mode(at: CGPoint(x: frame.midX, y: frame.midY), in: modes) == mode,
                           "a click in the middle of \(mode) picks \(mode)")
                }
            }
        }

        let dividers = Layout.dividerOffsets(in: all)
        suite.expect(dividers.count == 2, "two rules set the text and video modes apart")
        if let text = Layout.itemFrame(.text, in: all), let timer = Layout.itemFrame(.timer, in: all), dividers.count == 2 {
            suite.expect(dividers[0] > timer.maxX && dividers[0] < text.minX,
                   "the first rule sits in the gap between the timer and the text mode")
            suite.expect(Layout.mode(at: CGPoint(x: dividers[0], y: 20), in: all) == nil, "a click on a rule picks nothing")
        }
        suite.expect(Layout.dividerOffsets(in: Layout.recordingModes).count == 3,
               "the recording bar sets what is filmed, its options and its way back apart")
        suite.expect(Layout.dividerOffsets(in: [.text, .recording]).count == 1,
               "a bar that starts with a divided mode draws no rule at its edge")
        suite.expect(Layout.mode(at: CGPoint(x: 1, y: 20), in: all) == nil, "the bar's edge picks nothing")
        suite.expect(Layout.itemFrame(.record, in: all) == nil, "an item the bar does not show has no frame")
    }

    private static func placement(_ suite: TestSuite) {
        let all = Layout.modes(available: ScreenCaptureTool.allCases)
        let screen = CGRect(x: -215, y: 982, width: 1920, height: 1080)
        let size = Layout.barSize(modes: all)

        let waiting = Layout.barFrame(modes: all, in: screen)
        suite.expect(abs(waiting.midX - screen.midX) <= 0.5 && screen.contains(waiting) && waiting.maxY < screen.midY,
               "before any area the bar waits centered, in the lower half of its display")

        // AppKit coordinates: "under" the area is a lower y.
        let area = CGRect(x: 400, y: 1500, width: 600, height: 300)
        let under = Layout.barFrame(modes: all, under: area, in: screen)
        suite.expect(abs(under.midX - area.midX) <= 0.5, "the bar is centered under the area")
        suite.expect(under.maxY == area.minY - Layout.areaGap, "at the measured distance below it")

        let low = CGRect(x: 400, y: 1000, width: 600, height: 300)
        let above = Layout.barFrame(modes: all, under: low, in: screen)
        suite.expect(above.minY == low.maxY + Layout.areaGap, "an area too low for that gets the bar above it")

        let full = screen.insetBy(dx: 20, dy: 20)
        let inside = Layout.barFrame(modes: all, under: full, in: screen)
        suite.expect(screen.contains(inside) && full.intersects(inside),
               "an area that fills the display gets the bar over its lower part")

        let corner = CGRect(x: 1600, y: 1700, width: 100, height: 80)
        let clamped = Layout.barFrame(modes: all, under: corner, in: screen)
        suite.expect(clamped.maxX <= screen.maxX - Layout.screenMargin && clamped.size == size,
               "near an edge the bar slides back inside its display")
        suite.expect(screen.contains(Layout.barFrame(modes: Layout.recordingModes, under: corner, in: screen)),
               "the recording bar obeys the same rule")
    }

    private static func timer(_ suite: TestSuite) {
        let allowed = ScreenshotSupport.allowedDelays
        suite.expect(allowed.first == 0, "the delays upstream allows start with none")
        var delay = 0
        var seen = [delay]
        for _ in allowed.indices.dropLast() {
            delay = Layout.nextDelay(after: delay, allowed: allowed)
            seen.append(delay)
        }
        suite.expect(seen == allowed, "clicking the timer walks through every allowed delay")
        suite.expect(Layout.nextDelay(after: delay, allowed: allowed) == 0, "after the longest delay it is off again")
        suite.expect(Layout.nextDelay(after: 7, allowed: allowed) == allowed[0],
               "a delay upstream no longer allows starts over")
        suite.expect(Layout.nextDelay(after: 3, allowed: []) == 0, "no allowed delay means no delay")
        suite.expect(Layout.nextDelay(after: 3, allowed: Layout.recordingCountdowns) == 5
            && Layout.nextDelay(after: 10, allowed: Layout.recordingCountdowns) == 0,
               "the recording countdown walks its own steps and comes back to none")
        suite.expect(Layout.recordingCountdowns.contains(3), "upstream's default countdown is one of the steps")
    }

    private static func preferences(_ suite: TestSuite) {
        let enabled = DefaultsKey.forkCaptureMenuShortcutEnabled
        let shortcut = DefaultsKey.forkCaptureMenuShortcut
        for key in [enabled, shortcut] {
            suite.expect(key.hasPrefix("fork"), "\(key) carries the fork prefix")
            suite.expect(SettingsBackupSupport.exportKeys().contains(key), "\(key) travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[enabled] as? Bool == true, "the capture menu shortcut is on by default")
        let stored = Defaults.registeredDefaults[shortcut] as? String
        suite.expect(stored.flatMap { GlobalShortcut(storageValue: $0) } == Layout.defaultShortcut,
               "the registered shortcut reads back as the default one")
        suite.expect(Layout.defaultShortcut.keyCode == 23 && Layout.defaultShortcut.modifiers == [.shift, .command],
               "the default is Shift-Command and the fifth digit key")
    }

    /// The bar as set in the settings, what the menu shows first, what a recording films.
    private static func settings(_ suite: TestSuite) {
        let all = ScreenCaptureTool.allCases
        suite.expect(Layout.modes(available: all, stored: nil) == Layout.mainModes
            && Layout.modes(available: all, stored: "") == Layout.mainModes,
               "nothing stored: every item, in the default order")
        suite.expect(Layout.modes(available: all, stored: "recording,area,!window,fullScreen")
            == [.recording, .area, .fullScreen, .scrolling, .timer, .text],
               "the stored order is kept, a hidden item is left out, an item not mentioned comes last")
        suite.expect(Layout.modes(available: [.screenshot], stored: "recording,area") == [.area, .fullScreen, .window, .timer],
               "an item whose tool is unavailable is still left out")
        suite.expect(Layout.items(stored: "area,area,bogus,!text").map(\.mode) == Layout.mainModes.filter { $0 != .text } + [.text]
            || Layout.items(stored: "area,area,bogus,!text").first?.mode == .area,
               "repeats and unknown names are dropped")
        let hiddenAll = Layout.mainModes.compactMap(Layout.storageID).map { "!" + $0 }.joined(separator: ",")
        suite.expect(Layout.items(stored: hiddenAll).filter(\.shown).map(\.mode) == [.area],
               "at least one item stays shown")
        let items = Layout.items(stored: nil)
        suite.expect(Layout.items(stored: Layout.encoded(items)) == items
            && Layout.encoded(items) == "area,fullScreen,window,scrolling,timer,text,recording",
               "the items survive being stored")
        let moved = Layout.moving(items, at: 1, by: -1)
        suite.expect(moved.map(\.mode).prefix(2) == [.fullScreen, .area] && Layout.moving(items, at: 0, by: -1) == items
            && Layout.moving(items, at: items.count - 1, by: 1) == items,
               "an item moves one place, and not past either end")

        suite.expect(Layout.Opening.stored(nil) == .bar && Layout.Opening.stored("select") == .select
            && Layout.Opening.stored("bogus") == .bar,
               "the menu opens on its bar alone unless set otherwise")
        suite.expect(Layout.RecordingScope.stored(nil) == .area && Layout.RecordingScope.stored("window") == .window
            && Layout.RecordingScope.fullScreen.mode == .scopeScreen
            && Layout.RecordingScope(mode: .scopeWindow) == .window && Layout.RecordingScope(mode: .record) == nil,
               "a recording films an area unless set otherwise, and each choice has its item")
        for key in [DefaultsKey.forkCaptureMenuItems, DefaultsKey.forkCaptureMenuOpening,
                    DefaultsKey.forkCaptureMenuAreaAtOnce, DefaultsKey.forkRecorderScope] {
            suite.expect(Defaults.registeredDefaults[key] != nil && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) has a default and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkCaptureMenuAreaAtOnce] as? Bool == true,
               "“Area” captures as soon as the area is drawn, by default")
    }
}
