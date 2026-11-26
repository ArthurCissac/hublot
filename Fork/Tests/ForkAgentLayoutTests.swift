// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The AI page in Hublot's style and Explorer on one page (ForkAgentLayoutLogic).
enum ForkAgentLayoutTests {
    typealias Logic = ForkAgentLayoutLogic
    typealias Item = ForkAgentLayoutLogic.Item

    static func run(_ suite: TestSuite) {
        let tiles = [NotchAgentTile(card: .limits, provider: .claude), NotchAgentTile(card: .forkTime, provider: nil),
                     NotchAgentTile(card: .spend, provider: nil), NotchAgentTile(card: .projects, provider: nil)]
        suite.expect(Logic.widgetTiles(tiles).map(\.card) == [.limits, .projects, .spend],
                     "the time and the cost of projects make one widget, where the first of them stands")
        suite.expect(Logic.span(.projects, columns: 3) == 2 && Logic.span(.forkWaiting, columns: 3) == 3
            && Logic.span(.spend, columns: 3) == 1 && Logic.span(.projects, columns: 1) == 1,
                     "projects take two columns, a waiting session the whole row, the rest one")
        suite.expect(Logic.columns(width: 520) == 3 && Logic.columns(width: 380) == 2 && Logic.columns(width: 250) == 1,
                     "three columns in a wide island, fewer in a narrow one")

        func item(_ id: String, _ span: Int = 1, banner: Bool = false) -> Item { Item(id: id, span: span, banner: banner) }
        let rows = Logic.rows([item("wait", 3, banner: true), item("a"), item("b"), item("p", 2), item("c"), item("d")], columns: 3)
        suite.expect(rows.map { $0.map(\.id) } == [["wait"], ["a", "b", "c"], ["p", "d"]],
                     "a banner has its row; a wide widget lets a later one fill the place it cannot")
        suite.expect(Logic.rows([item("a"), item("w", 3, banner: true), item("b")], columns: 3).map { $0.map(\.id) } == [["a"], ["w"], ["b"]],
                     "nothing reaches past a banner")
        suite.expect(Logic.rows([item("x", 5)], columns: 3).first?.first?.span == 3,
                     "a widget is never wider than the grid")

        suite.expect(Logic.naturalHeight([[item("w", 3, banner: true)], [item("a")]]) == Logic.bannerHeight + Logic.spacing + Logic.comfortableHeight
            && Logic.naturalHeight([]) == 0,
                     "the page at ease: banners short, widgets comfortable")
        let three = [[item("a")], [item("b")], [item("c")]]
        suite.expect(Logic.rowHeights(three, available: 1_000) == Array(repeating: Logic.comfortableHeight, count: 3),
                     "with room, every row is at ease")
        let tight = Logic.rowHeights(three, available: 230)
        suite.expect(tight.allSatisfy { $0 == tight[0] } && tight[0] < Logic.comfortableHeight
            && tight.reduce(0, +) + 2 * Logic.spacing <= 230,
                     "without room, rows shrink alike to fit, nothing scrolls")
        suite.expect(Logic.rowHeights(three, available: 50).allSatisfy { $0 == Logic.minimumHeight },
                     "a row never shrinks past the least it reads at")

        let modules = ["controls", "music", "agents", "weather"]
        suite.expect(Logic.explorerShown(modules, hidden: ["music", "weather"], searching: false, name: { $0 }) == ["controls", "agents"]
            && Logic.explorerShown(modules, hidden: ["music"], searching: true, name: { $0 }) == modules,
                     "pages hidden from Explorer come back only for a search")
        suite.expect(Logic.hidden("music,,weather") == ["music", "weather"] && Logic.stored(["weather", "music"]) == "music,weather"
            && Logic.hidden(nil).isEmpty,
                     "Explorer's hidden pages are kept as a sorted list")
        suite.expect(Logic.explorerRows(count: 20, columns: 6, presetRows: 3, tileHeight: 86, spacing: 8, room: 800, fitsAll: true) == 4
            && Logic.explorerRows(count: 20, columns: 6, presetRows: 3, tileHeight: 86, spacing: 8, room: 800, fitsAll: false) == 3
            && Logic.explorerRows(count: 60, columns: 6, presetRows: 3, tileHeight: 86, spacing: 8, room: 400, fitsAll: true) == 4
            && Logic.explorerRows(count: 4, columns: 6, presetRows: 1, tileHeight: 86, spacing: 8, room: 800, fitsAll: true) == 1,
                     "Explorer shows every row the screen holds, never fewer than before")

        for key in [DefaultsKey.forkAgentsHublotStyle, DefaultsKey.forkExplorerFitsAll] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
                         "\(key) is on out of the box and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkExplorerHidden] as? String == ""
            && SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkExplorerHidden),
                     "Explorer hides nothing out of the box, and its choice travels in backups")
    }
}
