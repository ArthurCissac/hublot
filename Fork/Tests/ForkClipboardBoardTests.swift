// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Pinboards: groups of pinned clipboard entries.
enum ForkClipboardBoardTests {
    typealias Boards = ForkClipboardBoards

    static func run(_ suite: TestSuite) {
        let name: (Int) -> String = { "Tableau \($0)" }
        var boards = Boards()
        let work = boards.create(defaultName: name)
        let home = boards.create(defaultName: name)
        suite.expect(boards.boards.map(\.name) == ["Tableau 1", "Tableau 2"] && boards.boards[0].color != boards.boards[1].color,
               "a new pinboard is named after its rank, in the next colour")
        boards.rename(work, to: "  Travail  ")
        boards.rename(home, to: "   ")
        boards.recolor(home, to: .green)
        suite.expect(boards.boards[0].name == "Travail" && boards.boards[1].name == "Tableau 2" && boards.boards[1].color == .green,
               "a pinboard is renamed, never to an empty name, and recoloured")
        boards.rename(work, to: String(repeating: "x", count: 100))
        suite.expect(boards.boards[0].name.count == Boards.longestName, "a name is kept to a sensible length")

        let a = UUID(), b = UUID(), c = UUID()
        suite.expect(!boards.put(a, in: work, isPinned: false) && boards.board(of: a) == nil,
               "an entry that is not pinned is refused: nothing would keep it")
        suite.expect(boards.put(a, in: work, isPinned: true) && boards.put(b, in: work, isPinned: true),
               "pinned entries are filed")
        boards.put(a, in: home, isPinned: true)
        suite.expect(boards.board(of: a)?.id == home && boards.boards[0].entryIDs == [b],
               "filing an entry elsewhere moves it: one pinboard per entry")
        boards.remove(b)
        suite.expect(boards.board(of: b) == nil, "an entry taken out of its pinboard is back among the loose pins")

        // Tabs and what they show.
        struct Item { let id: UUID; let pinned: Bool }
        let items = [Item(id: a, pinned: true), Item(id: b, pinned: true), Item(id: c, pinned: false)]
        suite.expect(boards.tabs == [.history, .pinned, .board(work), .board(home)], "History, Pinned, then each pinboard")
        suite.expect(boards.entries(for: .history, from: items, id: \.id, isPinned: \.pinned).map(\.id) == [a, b, c],
               "History shows everything")
        suite.expect(boards.entries(for: .pinned, from: items, id: \.id, isPinned: \.pinned).map(\.id) == [b],
               "Pinned shows the pins filed nowhere")
        suite.expect(boards.entries(for: .board(home), from: items, id: \.id, isPinned: \.pinned).map(\.id) == [a],
               "a pinboard shows its own entries")
        suite.expect(boards.entries(for: .board(UUID()), from: items, id: \.id, isPinned: \.pinned).isEmpty,
               "a pinboard that no longer exists shows nothing")
        suite.expect(boards.tab(beside: .history, forward: false) == .history && boards.tab(beside: .history, forward: true) == .pinned
            && boards.tab(beside: .board(home), forward: true) == .board(home),
               "⌘← and ⌘→ move between tabs and stop at either end")

        // Dragging cards.
        var ordered = Boards(boards: [Boards.Board(name: "Ordre", color: .blue, entryIDs: [a, b, c])])
        let board = ordered.boards[0].id
        ordered.move(c, before: a, in: board)
        suite.expect(ordered.boards[0].entryIDs == [c, a, b], "a card dropped on another goes just before it")
        ordered.move(c, before: nil, in: board)
        suite.expect(ordered.boards[0].entryIDs == [a, b, c], "dropped past the last card, it goes to the end")
        ordered.move(UUID(), before: a, in: board)
        ordered.move(a, before: a, in: board)
        suite.expect(ordered.boards[0].entryIDs == [a, b, c], "a card from elsewhere, or dropped on itself, changes nothing")
        suite.expect(Boards.drop(on: .history) == nil && Boards.drop(on: .pinned) == .unfile && Boards.drop(on: .board(board)) == .file(board),
               "a card dropped on a pinboard's tab is filed there, on Pinned it leaves its pinboard, History takes nothing")

        boards.delete(home)
        suite.expect(boards.boards.count == 1 && boards.board(of: a) == nil,
               "deleting a pinboard puts its entries back among the loose pins: nothing is lost")

        // Keeping the file honest.
        var messy = Boards(boards: [Boards.Board(name: "", color: .blue, entryIDs: [a, b, a]),
                                    Boards.Board(name: "Deux", color: .red, entryIDs: [a, c])])
        messy = messy.pruned(pinnedIDs: [a, b], defaultName: name)
        suite.expect(messy.boards[0].entryIDs == [a, b] && messy.boards[1].entryIDs.isEmpty && messy.boards[0].name == "Tableau 1",
               "entries unpinned or gone are dropped, a duplicate stays in the first pinboard, an empty name gets a default")

        let round = Boards.decoded(boards.encoded())
        suite.expect(round == boards, "pinboards are saved and read back")
        let tolerant = Boards.decoded(Data(#"{"boards":[{"name":"Idées","color":"chartreuse","entryIDs":["3F2504E0-4F89-11D3-9A0C-0305E82C3301"]},{"color":"blue"}]}"#.utf8))
        suite.expect(tolerant.boards.count == 2 && tolerant.boards[0].color == .gray && tolerant.boards[0].entryIDs.count == 1
            && tolerant.boards[1].entryIDs.isEmpty && tolerant.version == Boards.currentVersion,
               "an unknown colour reads as gray, missing keys are filled in, a file without a version is version 1")
        suite.expect(Boards.decoded(Data("garbage".utf8)).boards.isEmpty && Boards.decoded(nil).boards.isEmpty,
               "an unreadable or missing file means no pinboards, and the pins stay where they are")
    }
}
