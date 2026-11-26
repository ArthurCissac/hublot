// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Lot 8, Juicy's menu bar item and panel layout: an iPhone-like battery
/// with the level inside, its colour following the level, the devices pinned
/// beside it in a chosen order, and the panel's cards in the order the user
/// dragged them. Pure.
enum ForkBatteryMenuLogic {
    // MARK: - The icon

    /// What the battery shows inside, and beside it.
    enum IconText: String, CaseIterable, Equatable { case percent, time, both }

    /// The battery's colour: `normal` is a muted tone, as in Arthur's
    /// reference capture of 26/11/2026.
    enum IconTint: Equatable { case normal, red, orange, green }

    /// Green while charging, red under 20 %, orange in Low Power Mode,
    /// muted otherwise; in that order.
    static func iconTint(percent: Int, charging: Bool, lowPower: Bool = false) -> IconTint {
        if charging { return .green }
        if percent < 20 { return .red }
        return lowPower ? .orange : .normal
    }

    /// The share of the battery's body filled.
    static func iconFill(percent: Int) -> CGFloat {
        CGFloat(max(0, min(100, percent))) / 100
    }

    /// « 1:30 » for a time left, nil when macOS does not know.
    static func shortTime(minutes: Int?) -> String? {
        guard let minutes, minutes > 0, minutes < 100 * 60 else { return nil }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// The text inside the battery and the one beside it.
    static func iconTexts(percent: Int, minutesLeft: Int?, mode: IconText, showNumber: Bool) -> (inside: String?, beside: String?) {
        let time = shortTime(minutes: minutesLeft)
        switch mode {
        case .percent: return (showNumber ? "\(percent)" : nil, nil)
        case .time: return (showNumber ? (time ?? "\(percent)") : nil, nil)
        case .both: return (showNumber ? "\(percent)" : nil, time)
        }
    }

    /// The battery's body grows with what it holds: room for « 100 » or
    /// « 1:30 ». Wide enough for a number read from a distance (Arthur's
    /// request of 26/11/2026).
    static func iconBodyWidth(for text: String?, large: Bool) -> CGFloat {
        let base: CGFloat = large ? 36 : 32
        guard let text, text.count > 2 else { return base }
        return base + CGFloat(text.count - 2) * (large ? 8.5 : 7.5)
    }

    /// The battery's height and the size of its number: the inside sits
    /// 2.4 pt in from the outline, so the number is a little smaller than
    /// the body allows.
    static func iconBodyHeight(large: Bool) -> CGFloat { large ? 16 : 15 }
    static func iconNumberSize(large: Bool) -> CGFloat { large ? 11.5 : 10.5 }

    // MARK: - Pinned devices

    /// The pinned devices, by name, in their order; the single pin of the
    /// first version still counts.
    static func pinnedNames(stored: String, legacy: String) -> [String] {
        if !stored.isEmpty, let names = try? JSONDecoder().decode([String].self, from: Data(stored.utf8)) {
            var seen = Set<String>()
            return names.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        return legacy.isEmpty ? [] : [legacy]
    }

    static func encodePinned(_ names: [String]) -> String {
        guard let data = try? JSONEncoder().encode(names) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func togglingPin(_ name: String, in names: [String]) -> [String] {
        names.contains(name) ? names.filter { $0 != name } : names + [name]
    }

    static func movingPin(_ names: [String], from index: Int, by offset: Int) -> [String] {
        let target = index + offset
        guard names.indices.contains(index), names.indices.contains(target) else { return names }
        var moved = names
        moved.swapAt(index, target)
        return moved
    }

    // MARK: - The panel's cards

    enum Card: String, CaseIterable, Equatable { case info, devices, apps, history, flow }

    /// The cards in their stored order, each once, the missing ones after.
    static func cardOrder(stored: String) -> [Card] {
        var seen = Set<Card>()
        var order = stored.split(separator: ",").compactMap { Card(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        order += Card.allCases.filter { !seen.contains($0) }
        return order
    }

    static func encodeOrder(_ order: [Card]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// A card dragged onto another takes its place.
    static func moving(_ card: Card, onto target: Card, in order: [Card]) -> [Card] {
        guard card != target, let from = order.firstIndex(of: card), let to = order.firstIndex(of: target) else { return order }
        var moved = order
        moved.remove(at: from)
        moved.insert(card, at: to)
        return moved
    }

    /// The chart's spans, in hours.
    static let chartHours = [6, 12, 24]
}
