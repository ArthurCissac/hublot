// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics

/// The capture menu: its shortcut opens a selection; the area drawn is kept on
/// screen, framed, with a bar under it, and the bar's buttons decide what is
/// done with that area. A recording opens a short bar of its own first, with
/// its options and a start button; a scrolling capture starts at once on the
/// area framed, or, with none, as soon as its area is drawn, its window
/// clicked, or Return takes the whole display.
///
/// The proportions were measured on the reference app's all-in-one bar (see
/// docs/reference/cleanshot-x.md); the drawing and the wording are the fork's.
/// Pure geometry and choices, so the harness can pin them down.
enum ForkCaptureMenuLayout {
    /// Everything a bar can show: the main bar's seven items, then the items
    /// of the recording bar. A scrolling capture has no bar of its own: it
    /// takes the area framed, or with none draws its area, or takes the window
    /// clicked or the whole display, and starts at once, its controls on its
    /// own strip (ForkScrollingControls).
    enum Mode: CaseIterable {
        case area, fullScreen, window, scrolling, timer, text, recording
        case record, microphone, systemAudio, mono, clicks, keys, camera, cameraShape, countdown, back
        /// What a recording films: the area drawn, a window, or the whole display.
        case scopeArea, scopeWindow, scopeScreen

        /// The upstream capture tool a mode relies on: a mode is offered only
        /// while that tool's feature is available.
        var tool: ScreenCaptureTool {
            switch self {
            case .area, .fullScreen, .window, .timer: return .screenshot
            case .scrolling: return .scrolling
            case .text: return .text
            case .recording, .record, .microphone, .systemAudio, .mono, .clicks, .keys, .camera, .cameraShape,
                 .countdown, .back, .scopeArea, .scopeWindow, .scopeScreen:
                return .recording
            }
        }

        /// A setting rather than an action: a click changes it and the bar stays.
        var isSetting: Bool {
            switch self {
            case .timer, .microphone, .systemAudio, .mono, .clicks, .keys, .camera, .cameraShape,
                 .countdown, .scopeArea, .scopeWindow, .scopeScreen:
                return true
            default: return false
            }
        }

        /// Needs an area on screen to act on.
        var needsArea: Bool {
            switch self {
            case .area, .text, .recording, .record: return true
            default: return false
            }
        }

        /// A thin rule sets these apart from what comes before them.
        var followsDivider: Bool {
            switch self {
            case .text, .recording, .scopeArea, .microphone, .back: return true
            default: return false
            }
        }
    }

    static let barHeight: CGFloat = 55
    static let itemWidth: CGFloat = 62.5
    static let sideInset: CGFloat = 3.75
    static let dividerGap: CGFloat = 6.5
    static let cornerRadius: CGFloat = 14
    /// From the area's bottom edge to the bar.
    static let areaGap: CGFloat = 37
    /// From the display's edges to the bar, at least.
    static let screenMargin: CGFloat = 8

    /// Shift-Command-5, by key position rather than by character, so it is the
    /// same key on every keyboard layout.
    static let defaultShortcut = GlobalShortcut(keyCode: 23, modifiers: [.shift, .command])

    /// The main bar's items, in their default order.
    static let mainModes: [Mode] = [.area, .fullScreen, .window, .scrolling, .timer, .text, .recording]

    /// The main bar: the items chosen in the settings (`stored`, see
    /// `items(stored:)`), in their order, among the capture tools available.
    static func modes(available tools: [ScreenCaptureTool], stored: String? = nil) -> [Mode] {
        items(stored: stored).filter(\.shown).map(\.mode).filter { tools.contains($0.tool) }
    }

    // MARK: - The bar as set in the settings

    /// One item of the main bar in the settings: shown or not.
    struct Item: Equatable {
        let mode: Mode
        var shown: Bool
    }

    /// A main item's name in the preferences.
    static func storageID(_ mode: Mode) -> String? {
        switch mode {
        case .area: return "area"
        case .fullScreen: return "fullScreen"
        case .window: return "window"
        case .scrolling: return "scrolling"
        case .timer: return "timer"
        case .text: return "text"
        case .recording: return "recording"
        default: return nil
        }
    }

    /// The main bar's items as stored: names in order, comma separated, a
    /// hidden one marked with "!". Unknown names and repeats are dropped; an
    /// item the preference does not mention (one added later) comes last,
    /// shown. Nothing stored: every item, in the default order. At least one
    /// item always stays shown.
    static func items(stored: String?) -> [Item] {
        var items: [Item] = []
        for raw in (stored ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let hidden = raw.hasPrefix("!")
            let name = hidden ? String(raw.dropFirst()) : raw
            guard let mode = mainModes.first(where: { storageID($0) == name }),
                  !items.contains(where: { $0.mode == mode }) else { continue }
            items.append(Item(mode: mode, shown: !hidden))
        }
        for mode in mainModes where !items.contains(where: { $0.mode == mode }) {
            items.append(Item(mode: mode, shown: true))
        }
        if !items.contains(where: \.shown) { items[0].shown = true }
        return items
    }

    static func encoded(_ items: [Item]) -> String {
        items.compactMap { item in storageID(item.mode).map { item.shown ? $0 : "!" + $0 } }.joined(separator: ",")
    }

    /// The items with one moved up or down a place; unchanged at either end.
    static func moving(_ items: [Item], at index: Int, by offset: Int) -> [Item] {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return items }
        var moved = items
        moved.swapAt(index, target)
        return moved
    }

    /// What the shortcut shows first.
    enum Opening: String, CaseIterable {
        /// The bar alone: an item is picked, then its area drawn if it needs one.
        case bar
        /// The last area drawn, framed, with the bar under it.
        case lastArea
        /// A selection at once, as Shift-Command-4 does.
        case select

        static func stored(_ raw: String?) -> Opening { raw.flatMap(Opening.init(rawValue:)) ?? .bar }
    }

    /// What a recording films.
    enum RecordingScope: String, CaseIterable {
        case area, window, fullScreen

        static func stored(_ raw: String?) -> RecordingScope { raw.flatMap(RecordingScope.init(rawValue:)) ?? .area }

        var mode: Mode {
            switch self {
            case .area: return .scopeArea
            case .window: return .scopeWindow
            case .fullScreen: return .scopeScreen
            }
        }

        init?(mode: Mode) {
            switch mode {
            case .scopeArea: self = .area
            case .scopeWindow: self = .window
            case .scopeScreen: self = .fullScreen
            default: return nil
            }
        }
    }

    /// The recording bar: start, what is filmed (area, window, whole display),
    /// the two sound sources, mono, the click rings, the keys, the camera and
    /// its shape, the countdown, and the way back.
    static let recordingModes: [Mode] = [.record, .scopeArea, .scopeWindow, .scopeScreen, .microphone, .systemAudio,
                                         .mono, .clicks, .keys, .camera, .cameraShape, .countdown, .back]

    static func barSize(modes: [Mode]) -> CGSize {
        let dividers = CGFloat(dividerCount(in: modes))
        return CGSize(width: 2 * sideInset + CGFloat(modes.count) * itemWidth + dividers * dividerGap,
                      height: barHeight)
    }

    /// A mode's frame inside the bar, origin at the bar's top left. Nil for a
    /// mode the bar does not show.
    static func itemFrame(_ mode: Mode, in modes: [Mode]) -> CGRect? {
        guard let index = modes.firstIndex(of: mode) else { return nil }
        let dividersBefore = CGFloat(dividerCount(in: Array(modes[...index])))
        return CGRect(x: sideInset + CGFloat(index) * itemWidth + dividersBefore * dividerGap,
                      y: 0, width: itemWidth, height: barHeight)
    }

    /// Where each rule is drawn: the middle of the gap before a divided mode.
    static func dividerOffsets(in modes: [Mode]) -> [CGFloat] {
        modes.enumerated().compactMap { index, mode in
            guard index > 0, mode.followsDivider, let frame = itemFrame(mode, in: modes) else { return nil }
            return frame.minX - dividerGap / 2
        }
    }

    static func mode(at point: CGPoint, in modes: [Mode]) -> Mode? {
        modes.first { itemFrame($0, in: modes)?.contains(point) == true }
    }

    /// The bar's frame while no area is drawn yet, in AppKit coordinates:
    /// centered across, in the lower part of the display, clear of the Dock.
    static func barFrame(modes: [Mode], in screenFrame: CGRect) -> CGRect {
        let size = barSize(modes: modes)
        return CGRect(x: (screenFrame.midX - size.width / 2).rounded(),
                      y: (screenFrame.minY + screenFrame.height * 0.26).rounded(),
                      width: size.width, height: size.height)
    }

    /// The bar's frame once an area is drawn, in AppKit coordinates: centered
    /// under the area. Where there is no room below, above it; where there is
    /// room on neither side, over the area's lower part. Always inside the display.
    static func barFrame(modes: [Mode], under area: CGRect, in screenFrame: CGRect) -> CGRect {
        let size = barSize(modes: modes)
        let minimumX = screenFrame.minX + screenMargin
        let maximumX = max(minimumX, screenFrame.maxX - screenMargin - size.width)
        // Rounded first, then held inside: rounding last could push it half a point out.
        let x = min(max((area.midX - size.width / 2).rounded(), minimumX), maximumX)
        let below = area.minY - areaGap - size.height
        let above = area.maxY + areaGap
        let y: CGFloat
        if below >= screenFrame.minY + screenMargin {
            y = below
        } else if above + size.height <= screenFrame.maxY - screenMargin {
            y = above
        } else {
            y = max(screenFrame.minY + screenMargin, area.minY + areaGap / 2)
        }
        return CGRect(x: x, y: y.rounded(), width: size.width, height: size.height)
    }

    // MARK: - Settings changed from the bar

    /// The value a click on the timer or the countdown moves to: the next
    /// allowed one, wrapping back to the first.
    static func nextDelay(after current: Int, allowed: [Int]) -> Int {
        guard !allowed.isEmpty else { return 0 }
        guard let index = allowed.firstIndex(of: current) else { return allowed[0] }
        return allowed[(index + 1) % allowed.count]
    }

    /// The countdowns a recording can start after, in seconds.
    static let recordingCountdowns = [0, 3, 5, 10]

    private static func dividerCount(in modes: [Mode]) -> Int {
        modes.enumerated().filter { $0.offset > 0 && $0.element.followsDivider }.count
    }
}
