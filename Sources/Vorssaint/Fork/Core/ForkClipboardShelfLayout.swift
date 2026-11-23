// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The clipboard shelf: the history as a row of large cards along the bottom
/// of the pointer's display, the way Paste shows it. Upstream keeps the
/// history, its search, its copy and its pins; this decides where the shelf
/// goes, in which order the cards come, and what each key does. Pure choices.
/// The sizes were measured on the reference app's shelf (docs/reference/paste.md);
/// the drawing is the fork's.
enum ForkClipboardShelfLayout {
    /// The window: the whole width of the display, along its very bottom, over the Dock.
    static let windowHeight: CGFloat = 332
    /// The panel drawn inside the window, and its corners.
    static let panelInset = (side: CGFloat(9), bottom: CGFloat(8), top: CGFloat(1))
    static let panelCornerRadius: CGFloat = 24
    /// The line the search, the tabs and the buttons sit on, from the window's top.
    static let headerCenter: CGFloat = 30
    static let tabHeight: CGFloat = 24
    /// Square cards, their top from the window's top, the first one from the panel's edge.
    static let cardSize = CGSize(width: 232, height: 232)
    static let cardSpacing: CGFloat = 24
    static let cardTop: CGFloat = 68
    static let cardLeading: CGFloat = 23
    static let cardCornerRadius: CGFloat = 16
    /// The coloured band at the top of a card.
    static let bandHeight: CGFloat = 48
    static let selectionWidth: CGFloat = 4

    /// Along the very bottom of the display, as wide as it, over the Dock.
    static func shelfFrame(screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width,
               height: min(windowHeight, screenFrame.height)).integral
    }

    /// Where the shelf starts its way up: just below the display's bottom edge.
    static func hiddenFrame(for frame: CGRect) -> CGRect {
        frame.offsetBy(dx: 0, dy: -frame.height)
    }

    /// The cards in the order Paste shows them: newest copy first, pinned
    /// entries among the others by the date they were copied. Ties keep the
    /// history's own order.
    static func ordered<Entry>(_ entries: [Entry], copiedAt: (Entry) -> Date) -> [Entry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                let left = copiedAt(lhs.element), right = copiedAt(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }

    /// The ⌘-number a card answers to: the first nine, 1 to 9.
    static func shortcutNumber(at position: Int) -> Int? {
        (0..<9).contains(position) ? position + 1 : nil
    }

    enum Action: Equatable {
        case previous, next, first, last, previousTab, nextTab
        case paste, copy, remove, togglePin, preview, close
        case pasteNumber(Int)
    }

    /// What a key does in the shelf: ⌘← and ⌘→ change tab, Home and End go
    /// to either end of the cards. Typing goes to the search field: only
    /// keys that cannot be typed, or are held with Command or Option, act.
    /// Space opens the preview only while nothing is being searched.
    static func action(keyCode: Int, characters: String?, command: Bool, option: Bool, shift: Bool,
                       control: Bool, queryIsEmpty: Bool) -> Action? {
        switch keyCode {
        case 53: return .close
        case 123: return command ? .previousTab : .previous
        case 124: return command ? .nextTab : .next
        case 115: return .first
        case 119: return .last
        case 36, 76: return shift ? .copy : .paste
        case 51, 117: return command ? .remove : nil
        case 49: return queryIsEmpty && !command && !option && !control ? .preview : nil
        default: break
        }
        if command, !option, !control {
            let digits: [Int: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                      83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
            if let number = digits[keyCode] { return .pasteNumber(number) }
        }
        if option, !command, !control, keyCode == 35 { return .togglePin }
        return nil
    }

    /// The selection after a move, held inside the list.
    static func moved(_ action: Action, from index: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let current = index.map { min(max($0, 0), count - 1) }
        switch action {
        case .previous: return max(0, (current ?? 0) - 1)
        case .next: return current.map { min(count - 1, $0 + 1) } ?? 0
        case .first: return 0
        case .last: return count - 1
        default: return current
        }
    }

    /// The card to select once the selected one is removed: the one that
    /// took its place, or the new last one.
    static func selectionAfterRemoving(at index: Int, count: Int) -> Int? {
        let remaining = count - 1
        guard remaining > 0 else { return nil }
        return min(index, remaining - 1)
    }

    /// Whether the app that was in front can receive the paste: not this app,
    /// not one that has quit.
    static func pasteTargetIsUsable(bundleID: String?, ownBundleID: String?, isTerminated: Bool,
                                    isRegular: Bool) -> Bool {
        !isTerminated && isRegular && bundleID != nil && bundleID != ownBundleID
    }
}
