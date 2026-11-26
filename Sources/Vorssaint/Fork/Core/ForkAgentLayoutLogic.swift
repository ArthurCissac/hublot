// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The AI page in Hublot's style (ForkAgentWidgets): a widget per kind of
/// information, laid out on a grid that always fits the island, never
/// scrolled; and Explorer showing all its tiles at once. Pure: which widgets
/// show, how wide each is, how the rows pack and how tall they get.
enum ForkAgentLayoutLogic {
    static func styleEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkAgentsHublotStyle)
    }

    static func explorerFitsAll(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkExplorerFitsAll)
    }

    // MARK: - Which widgets

    /// Columns a widget takes.
    static func span(_ card: NotchAgentCard, columns: Int) -> Int {
        switch card {
        case .forkWaiting: return columns
        case .projects: return min(2, columns)
        default: return 1
        }
    }

    static func columns(width: CGFloat) -> Int {
        width >= 470 ? 3 : width >= 300 ? 2 : 1
    }

    // MARK: - Rows

    struct Item: Equatable {
        let id: String
        let span: Int
        let banner: Bool
    }

    /// Rows in reading order; a widget too wide for what is left of a row
    /// lets a later one that fits take the place first.
    static func rows(_ items: [Item], columns: Int) -> [[Item]] {
        let columns = max(1, columns)
        var pending = items.map { Item(id: $0.id, span: min(max(1, $0.span), columns), banner: $0.banner) }
        var rows: [[Item]] = []
        while !pending.isEmpty {
            let first = pending.removeFirst()
            if first.banner {
                rows.append([first])
                continue
            }
            var row = [first]
            var room = columns - first.span
            var index = 0
            // A banner keeps its place: nothing reaches past it.
            while room > 0, index < pending.count, !pending[index].banner {
                if pending[index].span <= room {
                    room -= pending[index].span
                    row.append(pending.remove(at: index))
                } else {
                    index += 1
                }
            }
            rows.append(row)
        }
        return rows
    }

    static let spacing: CGFloat = 8
    static let bannerHeight: CGFloat = 34
    /// A widget's height with room to spare, and the least it reads at.
    static let comfortableHeight: CGFloat = 92
    static let minimumHeight: CGFloat = 62

    /// The page's height with every row at ease.
    static func naturalHeight(_ rows: [[Item]]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        let heights = rows.map { $0.first?.banner == true ? bannerHeight : comfortableHeight }
        return heights.reduce(0, +) + spacing * CGFloat(rows.count - 1)
    }

    /// Each row's height so the page fits `available`: rows at ease when
    /// they can be, all shrunk alike otherwise, never under the least.
    static func rowHeights(_ rows: [[Item]], available: CGFloat) -> [CGFloat] {
        guard !rows.isEmpty else { return [] }
        let banners = rows.filter { $0.first?.banner == true }.count
        let widgets = rows.count - banners
        guard widgets > 0 else { return rows.map { _ in bannerHeight } }
        let room = available - CGFloat(banners) * bannerHeight - spacing * CGFloat(rows.count - 1)
        let each = min(comfortableHeight, max(minimumHeight, floor(room / CGFloat(widgets))))
        return rows.map { $0.first?.banner == true ? bannerHeight : each }
    }

    /// The tiles the page shows, as widgets: the time and cost of projects as one.
    static func widgetTiles(_ tiles: [NotchAgentTile]) -> [NotchAgentTile] {
        var merged = false
        return tiles.compactMap { tile in
            guard tile.card == .projects || tile.card == .forkTime else { return tile }
            if merged { return nil }
            merged = true
            return NotchAgentTile(card: .projects, provider: nil)
        }
    }

    static func items(_ tiles: [NotchAgentTile], columns: Int) -> [Item] {
        widgetTiles(tiles).map { Item(id: $0.id, span: span($0.card, columns: columns), banner: $0.card == .forkWaiting) }
    }

    /// The page's height at ease, for the island to grow to.
    static func pageHeight(_ tiles: [NotchAgentTile], width: CGFloat) -> CGFloat {
        let columns = columns(width: width)
        return naturalHeight(rows(items(tiles, columns: columns), columns: columns))
    }

    // MARK: - Explorer

    /// The tiles Explorer shows: hidden ones only come back for a search.
    static func explorerShown<Module: Equatable>(_ modules: [Module], hidden: Set<String>, searching: Bool,
                                                 name: (Module) -> String) -> [Module] {
        searching ? modules : modules.filter { !hidden.contains(name($0)) }
    }

    static func hidden(_ stored: String?) -> Set<String> {
        Set((stored ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func stored(_ hidden: Set<String>) -> String {
        hidden.sorted().joined(separator: ",")
    }

    /// Every row of tiles, when Explorer shows them all, within the room the screen leaves.
    static func explorerRows(count: Int, columns: Int, presetRows: Int, tileHeight: CGFloat, spacing: CGFloat,
                             room: CGFloat, fitsAll: Bool) -> Int {
        guard fitsAll, columns > 0, count > 0 else { return presetRows }
        let all = Int(ceil(Double(count) / Double(columns)))
        let fitting = max(1, Int((room + spacing) / (tileHeight + spacing)))
        return max(presetRows, min(all, fitting))
    }
}
