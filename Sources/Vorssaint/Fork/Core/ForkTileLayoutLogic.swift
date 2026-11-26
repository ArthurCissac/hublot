// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The menu's tiles arranged by hand (`forkTileOrder`): the fork's and
/// upstream's in one order, dragged anywhere, each shown or hidden (hiding
/// stays in each tile's own setting). Pure: the order from what is stored,
/// a move, and where a tile the order does not know yet goes.
enum ForkTileLayoutLogic {
    /// A tile's name in the stored order.
    static func forkKey(_ raw: String) -> String { "fork." + raw }
    static func panelKey(_ raw: String) -> String { "panel." + raw }
    /// A Home Assistant favourite's own tile, by entity id (ForkHome).
    static func homeKey(_ raw: String) -> String { "home." + raw }

    /// The stored order: names separated by commas, each once.
    static func parse(_ stored: String?) -> [String] {
        var seen = Set<String>()
        return (stored ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encode(_ keys: [String]) -> String { keys.joined(separator: ",") }

    /// Every known tile once: the stored order first, unknown names dropped;
    /// a tile it does not name yet goes right after the tile before it in
    /// `known`'s own order (the first such goes first), so a new action lands
    /// beside its family rather than at the end.
    static func ordered(stored: [String], known: [String]) -> [String] {
        let knownSet = Set(known)
        var result = stored.filter(knownSet.contains)
        for (index, key) in known.enumerated() where !result.contains(key) {
            let before = known[..<index].last(where: result.contains)
            let at = before.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(key, at: at)
        }
        return result
    }

    /// `key` dragged onto `target`: it takes the target's place, the others
    /// shifting toward where it came from.
    static func move(_ key: String, onto target: String, in order: [String]) -> [String] {
        guard key != target, let from = order.firstIndex(of: key), let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(key, at: to)
        return result
    }

    /// `key` dragged to the end of everything.
    static func moveToEnd(_ key: String, in order: [String]) -> [String] {
        guard order.contains(key) else { return order }
        return order.filter { $0 != key } + [key]
    }

    /// The tiles shown and those hidden, each in the order's own sequence.
    static func split(_ order: [String], hidden: (String) -> Bool) -> (shown: [String], hidden: [String]) {
        (order.filter { !hidden($0) }, order.filter(hidden))
    }

    // MARK: - Moving while editing

    /// A tile's swing while the grid is being arranged, in degrees, and how
    /// long one swing lasts; each tile starts a little apart from the next so
    /// they do not move as one.
    static let jiggleAngle = 1.6
    static let jiggleDuration = 0.14

    static func jiggleDelay(index: Int) -> Double { Double(index % 5) * 0.037 }
}
