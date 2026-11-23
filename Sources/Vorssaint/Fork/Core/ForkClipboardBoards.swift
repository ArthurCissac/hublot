// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Pinboards: named, coloured groups of pinned clipboard entries, as in
/// Paste. They hold no content: an entry stays in upstream's history, pinned,
/// which is what keeps it (never expired, outside the history's limit), and a
/// pinboard only lists which entries it gathers. An entry is in one pinboard
/// at most. Pure values and operations; reading and writing the file is elsewhere.
struct ForkClipboardBoards: Codable, Equatable {
    enum Color: String, Codable, CaseIterable {
        case red, orange, yellow, green, teal, blue, purple, pink, gray

        /// A colour this version does not know reads as gray.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Color(rawValue: raw) ?? .gray
        }
    }

    struct Board: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var color: Color
        var entryIDs: [UUID]

        init(id: UUID = UUID(), name: String, color: Color, entryIDs: [UUID] = []) {
            self.id = id
            self.name = name
            self.color = color
            self.entryIDs = entryIDs
        }

        /// Missing keys are filled in, so a damaged file still opens.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            color = (try? container.decodeIfPresent(Color.self, forKey: .color)) ?? .gray
            entryIDs = (try? container.decodeIfPresent([UUID].self, forKey: .entryIDs)) ?? []
        }
    }

    /// What the shelf shows above its cards.
    enum Tab: Equatable, Hashable {
        case history, pinned, board(UUID)
    }

    static let currentVersion = 1
    static let longestName = 40

    var version = ForkClipboardBoards.currentVersion
    var boards: [Board] = []

    init(boards: [Board] = []) {
        self.boards = boards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        boards = (try? container.decodeIfPresent([Board].self, forKey: .boards)) ?? []
    }

    static func decoded(_ data: Data?) -> ForkClipboardBoards {
        guard let data, let boards = try? JSONDecoder().decode(ForkClipboardBoards.self, from: data) else {
            return ForkClipboardBoards()
        }
        return boards
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    // MARK: - Pinboards

    /// A new pinboard, named after its rank, in the next colour of the list.
    mutating func create(defaultName: (Int) -> String) -> UUID {
        let colors = Color.allCases.filter { $0 != .gray }
        let board = Board(name: defaultName(boards.count + 1), color: colors[boards.count % colors.count])
        boards.append(board)
        return board.id
    }

    mutating func rename(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestName))
        guard !trimmed.isEmpty, let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].name = trimmed
    }

    mutating func recolor(_ id: UUID, to color: Color) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].color = color
    }

    /// The pinboard goes; its entries stay pinned, back among the loose pins.
    mutating func delete(_ id: UUID) {
        boards.removeAll { $0.id == id }
    }

    // MARK: - Entries

    /// Files a pinned entry in a pinboard, taking it out of any other. An
    /// entry that is not pinned is refused: nothing would keep it.
    @discardableResult
    mutating func put(_ entryID: UUID, in boardID: UUID, isPinned: Bool) -> Bool {
        guard isPinned, let target = boards.firstIndex(where: { $0.id == boardID }) else { return false }
        remove(entryID)
        boards[target].entryIDs.append(entryID)
        return true
    }

    mutating func remove(_ entryID: UUID) {
        for index in boards.indices { boards[index].entryIDs.removeAll { $0 == entryID } }
    }

    /// Moves an entry within its pinboard to just before another one, or to
    /// the end when there is none: a card dropped on a card of the same pinboard.
    mutating func move(_ entryID: UUID, before targetID: UUID?, in boardID: UUID) {
        guard entryID != targetID, let index = boards.firstIndex(where: { $0.id == boardID }),
              boards[index].entryIDs.contains(entryID) else { return }
        boards[index].entryIDs.removeAll { $0 == entryID }
        let position = targetID.flatMap { boards[index].entryIDs.firstIndex(of: $0) } ?? boards[index].entryIDs.endIndex
        boards[index].entryIDs.insert(entryID, at: position)
    }

    /// What dropping a card on a tab does.
    enum Drop: Equatable {
        /// Filed in that pinboard, pinned if it was not.
        case file(UUID)
        /// Pinned, and out of any pinboard.
        case unfile
    }

    /// The history takes nothing: everything is in it already.
    static func drop(on tab: Tab) -> Drop? {
        switch tab {
        case .history: return nil
        case .pinned: return .unfile
        case .board(let id): return .file(id)
        }
    }

    func board(of entryID: UUID) -> Board? {
        boards.first { $0.entryIDs.contains(entryID) }
    }

    /// Drops what no longer belongs: entries gone from the history or
    /// unpinned elsewhere, an entry listed twice (the first board keeps it),
    /// and empty names.
    func pruned(pinnedIDs: Set<UUID>, defaultName: (Int) -> String) -> ForkClipboardBoards {
        var seen = Set<UUID>()
        var copy = self
        copy.version = Self.currentVersion
        for index in copy.boards.indices {
            copy.boards[index].entryIDs = copy.boards[index].entryIDs.filter { id in
                guard pinnedIDs.contains(id), !seen.contains(id) else { return false }
                seen.insert(id)
                return true
            }
            if copy.boards[index].name.trimmingCharacters(in: .whitespaces).isEmpty {
                copy.boards[index].name = defaultName(index + 1)
            }
        }
        return copy
    }

    // MARK: - Tabs

    var tabs: [Tab] {
        [.history, .pinned] + boards.map { .board($0.id) }
    }

    /// ⌘← and ⌘→: the tab beside, stopping at either end.
    func tab(beside tab: Tab, forward: Bool) -> Tab {
        let all = tabs
        guard let index = all.firstIndex(of: tab) else { return .history }
        return all[min(max(index + (forward ? 1 : -1), 0), all.count - 1)]
    }

    /// The entries a tab shows, in the order they come in: the history as
    /// given, the loose pins as given, a pinboard in its own order.
    func entries<Entry>(for tab: Tab, from all: [Entry], id: (Entry) -> UUID, isPinned: (Entry) -> Bool) -> [Entry] {
        switch tab {
        case .history:
            return all
        case .pinned:
            let filed = Set(boards.flatMap(\.entryIDs))
            return all.filter { isPinned($0) && !filed.contains(id($0)) }
        case .board(let boardID):
            guard let board = boards.first(where: { $0.id == boardID }) else { return [] }
            let byID = Dictionary(all.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
            return board.entryIDs.compactMap { byID[$0] }
        }
    }
}
