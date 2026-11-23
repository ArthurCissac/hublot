// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The clipboard shelf: where it goes, the order of its cards, its keys.
enum ForkClipboardTests {
    typealias Layout = ForkClipboardShelfLayout

    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let shelf = Layout.shelfFrame(screenFrame: screen)
        suite.expect(shelf == CGRect(x: 0, y: 0, width: 1512, height: 332),
               "the shelf takes the whole width of the display, 332 points high, along its very bottom, as measured")
        let second = Layout.shelfFrame(screenFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1080))
        suite.expect(second.minX == -1920 && second.minY == 200 && second.width == 1920, "on another display, it stays on that display")
        suite.expect(Layout.shelfFrame(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 200)).height == 200,
               "on a very short display it never runs past the top")
        suite.expect(Layout.hiddenFrame(for: shelf) == CGRect(x: 0, y: -332, width: 1512, height: 332),
               "it starts its way up from just below the display's edge")
        suite.expect(Layout.cardTop + Layout.cardSize.height + Layout.panelInset.bottom + 24 == Layout.windowHeight,
               "the cards leave 24 points under them, inside the panel, as measured")

        let now = Date(timeIntervalSince1970: 10_000)
        struct Item: Equatable { let name: String; let copied: Date }
        let items = [Item(name: "pinned old", copied: now.addingTimeInterval(-500)),
                     Item(name: "recent", copied: now),
                     Item(name: "middle", copied: now.addingTimeInterval(-100)),
                     Item(name: "same time", copied: now)]
        suite.expect(Layout.ordered(items, copiedAt: \.copied).map(\.name) == ["recent", "same time", "middle", "pinned old"],
               "newest copy first, pinned entries by their own date, ties in the history's order")

        suite.expect(Layout.shortcutNumber(at: 0) == 1 && Layout.shortcutNumber(at: 8) == 9 && Layout.shortcutNumber(at: 9) == nil,
               "the first nine cards answer to ⌘1 to ⌘9")

        func key(_ code: Int, cmd: Bool = false, opt: Bool = false, shift: Bool = false, empty: Bool = true) -> Layout.Action? {
            Layout.action(keyCode: code, characters: nil, command: cmd, option: opt, shift: shift, control: false,
                          queryIsEmpty: empty)
        }
        suite.expect(key(123) == .previous && key(124) == .next && key(115) == .first && key(119) == .last,
               "the arrows move along the cards, Home and End to either end")
        suite.expect(key(123, cmd: true) == .previousTab && key(124, cmd: true) == .nextTab,
               "Command and an arrow change tab, as in Paste")
        suite.expect(key(36) == .paste && key(76) == .paste && key(36, shift: true) == .copy,
               "Return pastes, Shift-Return only copies")
        suite.expect(key(51, cmd: true) == .remove && key(51) == nil, "Command-Delete removes a card; Delete alone edits the search")
        suite.expect(key(35, opt: true) == .togglePin && key(35) == nil, "Option-P pins; P alone is typed")
        suite.expect(key(49) == .preview && key(49, empty: false) == nil, "Space previews, unless a search is being typed")
        suite.expect(key(53) == .close, "Escape closes")
        suite.expect(key(18, cmd: true) == .pasteNumber(1) && key(25, cmd: true) == .pasteNumber(9)
            && key(83, cmd: true) == .pasteNumber(1) && key(18) == nil,
               "Command and a digit, keypad included, paste that card; a digit alone is typed")
        suite.expect(key(0) == nil && key(0, cmd: true) == nil, "letters reach the search field")

        suite.expect(Layout.moved(.next, from: nil, count: 5) == 0 && Layout.moved(.next, from: 4, count: 5) == 4
            && Layout.moved(.previous, from: 0, count: 5) == 0 && Layout.moved(.last, from: 1, count: 5) == 4
            && Layout.moved(.next, from: 2, count: 0) == nil,
               "moving stays inside the cards")
        suite.expect(Layout.selectionAfterRemoving(at: 2, count: 5) == 2 && Layout.selectionAfterRemoving(at: 4, count: 5) == 3
            && Layout.selectionAfterRemoving(at: 0, count: 1) == nil,
               "after a removal the next card is selected, or the new last one")

        suite.expect(Layout.pasteTargetIsUsable(bundleID: "com.apple.TextEdit", ownBundleID: "agency.nexflow.hublot",
                                                isTerminated: false, isRegular: true)
            && !Layout.pasteTargetIsUsable(bundleID: "agency.nexflow.hublot", ownBundleID: "agency.nexflow.hublot",
                                           isTerminated: false, isRegular: true)
            && !Layout.pasteTargetIsUsable(bundleID: "com.apple.TextEdit", ownBundleID: "x", isTerminated: true, isRegular: true),
               "a paste goes only to the app that was in front, never to this app or one that has quit")

        let key = DefaultsKey.forkClipboardShelf
        suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
               "the shelf is on by default, and the choice travels in backups")
    }
}
