// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The simple menus: what the switch changes in the panel's frame, the disk
/// chooser, the disk tab's blocks and the health's single word.
enum ForkPanelLookTests {
    private enum Block: String { case usage, activity, smart, protection, tools }

    static func run(_ suite: TestSuite) {
        typealias Look = ForkPanelLook
        let name = "ForkPanelLookTests.\(UUID().uuidString)"
        guard let on = UserDefaults(suiteName: name) else { return }
        defer { on.removePersistentDomain(forName: name) }
        on.set(true, forKey: DefaultsKey.forkSimplePanels)
        let offName = name + ".off"
        guard let off = UserDefaults(suiteName: offName) else { return }
        defer { off.removePersistentDomain(forName: offName) }
        off.set(false, forKey: DefaultsKey.forkSimplePanels)

        suite.expect(Look.hidesLogo(in: on) && !Look.hidesLogo(in: off)
            && Look.chromeSaving(in: on) == Look.logoRowHeight && Look.chromeSaving(in: off) == 0,
                     "without the logo the panel's fixed parts are 48 points shorter; off, nothing changes")
        suite.expect(Look.showsPlaceholder(present: false, in: on) && !Look.showsPlaceholder(present: true, in: on)
            && !Look.showsPlaceholder(present: false, in: off)
            && Look.showsLoadingRows(loading: true, in: on) && !Look.showsLoadingRows(loading: false, in: on)
            && !Look.showsLoadingRows(loading: true, in: off),
                     "a missing value or a list still filling shows a placeholder, not « - » nor « Measuring… »; off, as before")
        suite.expect(Look.deviceLines(in: on) == 2 && Look.deviceLines(in: off) == 1
            && Look.pickerMaxWidth(in: on) == .infinity && Look.pickerMaxWidth(in: off) == Look.pickerWidth
            && Look.pickerPriority(in: on) > Look.pickerPriority(in: off),
                     "device names get the room they need; off, the 164-point pickers stay")
        suite.expect(Look.systemSoundsInOptions(in: on) && !Look.systemSoundsInOptions(in: off),
                     "the system sounds' output moves into Options")
        suite.expect(Look.fanStopped(rpm: 0, in: on) && Look.fanStopped(rpm: 0.4, in: on) && !Look.fanStopped(rpm: 1200, in: on)
            && !Look.fanStopped(rpm: 0, in: off),
                     "a fan not turning reads « Stopped » instead of 0 rpm")
        suite.expect(!Look.showsDiskChooser(diskCount: 1, editing: false, in: on)
            && Look.showsDiskChooser(diskCount: 2, editing: false, in: on)
            && Look.showsDiskChooser(diskCount: 1, editing: true, in: on)
            && Look.showsDiskChooser(diskCount: 1, editing: false, in: off),
                     "the disk chooser shows with several disks or while arranging the tab")

        let blocks: [Block] = [.usage, .activity, .smart, .protection, .tools]
        suite.expect(Look.diskBlocks(blocks, hasExternalDisk: false, in: on) == [.usage, .tools, .activity, .smart]
            && Look.diskBlocks(blocks, hasExternalDisk: true, in: on) == [.usage, .tools, .activity, .smart, .protection]
            && Look.diskBlocks([.tools, .smart] as [Block], hasExternalDisk: false, in: on) == [.tools, .smart]
            && Look.diskBlocks(blocks, hasExternalDisk: false, in: off) == blocks,
                     "the space then the tools come first; ejecting only with an external disk; off, upstream's order")

        suite.expect(Look.health(percent: 98) == .good && Look.health(percent: 80) == .good
            && Look.health(percent: 65) == .worn && Look.health(percent: 20) == .failing
            && Look.health(percent: nil) == .unknown,
                     "the disk's health reads good from 80 %, worn from 50 %")
        suite.expect(Look.shortDurations.allSatisfy(Look.durations.contains) && Look.durations.last == 0,
                     "the shorter durations row only leaves out long timed choices, never « until stopped »")
    }
}
