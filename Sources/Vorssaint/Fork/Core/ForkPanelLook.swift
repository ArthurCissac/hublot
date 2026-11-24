// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The simple menus (`forkSimplePanels`): the menu bar panel without the
/// logo, its active tab named in the tab bar instead of a title in capitals,
/// and the blocks of a tab shown only when they are of use. Pure, so
/// upstream's panel code that the tests compile can ask it.
enum ForkPanelLook {
    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkSimplePanels)
    }

    /// The logo's row and the space under it: 28 points, 4 above and below, 12 to the tabs.
    static let logoRowHeight: CGFloat = 48

    static func hidesLogo(in defaults: UserDefaults = .standard) -> Bool { isOn(in: defaults) }

    // MARK: Mixer, Network, System and Fans

    /// A value not there yet: a quiet bar instead of « - » or « Measuring… ».
    static func showsPlaceholder(present: Bool, in defaults: UserDefaults = .standard) -> Bool {
        !present && isOn(in: defaults)
    }

    /// A list still filling: placeholder rows instead of « Measuring… ».
    static func showsLoadingRows(loading: Bool, in defaults: UserDefaults = .standard) -> Bool {
        loading && isOn(in: defaults)
    }

    /// Device names on up to two lines rather than cut in the middle.
    static func deviceLines(in defaults: UserDefaults = .standard) -> Int { isOn(in: defaults) ? 2 : 1 }

    /// The device pickers take the room the row leaves rather than 164 points.
    static let pickerWidth: CGFloat = 164
    static func pickerMaxWidth(in defaults: UserDefaults = .standard) -> CGFloat {
        isOn(in: defaults) ? .infinity : pickerWidth
    }

    static func pickerPriority(in defaults: UserDefaults = .standard) -> Double { isOn(in: defaults) ? 1 : 0 }

    /// The system sounds' output, chosen once, lives in Options.
    static func systemSoundsInOptions(in defaults: UserDefaults = .standard) -> Bool { isOn(in: defaults) }

    /// A fan turning slower than one turn a minute is stopped, and says so.
    static func fanStopped(rpm: Double, in defaults: UserDefaults = .standard) -> Bool {
        isOn(in: defaults) && rpm < 1
    }

    /// What the panel's fixed parts lose with the logo gone.
    static func chromeSaving(in defaults: UserDefaults = .standard) -> CGFloat {
        isOn(in: defaults) ? logoRowHeight : 0
    }

    /// Choosing a disk is only a question with several of them, or while
    /// the tab is being arranged.
    static func showsDiskChooser(diskCount: Int, editing: Bool, in defaults: UserDefaults = .standard) -> Bool {
        !isOn(in: defaults) || editing || diskCount > 1
    }

    /// The disk tab's blocks: the space first, then the tools, the activity
    /// and the health; ejecting only once an external disk is there.
    /// Works on upstream's private block type through its raw names.
    static func diskBlocks<Block: RawRepresentable>(_ blocks: [Block], hasExternalDisk: Bool,
                                                    in defaults: UserDefaults = .standard) -> [Block]
        where Block.RawValue == String {
        guard isOn(in: defaults) else { return blocks }
        var kept = blocks.filter { hasExternalDisk || $0.rawValue != "protection" }
        if let tools = kept.firstIndex(where: { $0.rawValue == "tools" }) {
            let block = kept.remove(at: tools)
            let afterUsage = kept.firstIndex(where: { $0.rawValue == "usage" }).map { $0 + 1 } ?? 0
            kept.insert(block, at: afterUsage)
        }
        return kept
    }

    /// The disk's health as one word: good from 80 %, worn from 50 %.
    enum Health: Equatable { case good, worn, failing, unknown }

    static func health(percent: Int?) -> Health {
        guard let percent else { return .unknown }
        return percent >= 80 ? .good : (percent >= 50 ? .worn : .failing)
    }

    /// The keep-awake durations on one row: all of upstream's when they fit,
    /// otherwise without the longest timed ones (the end-time chip covers them).
    static let durations = [15, 30, 60, 120, 240, 0]
    static let shortDurations = [15, 30, 60, 120, 0]
}
