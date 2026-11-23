// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The pinboards on disk: one small file beside upstream's history, written
/// the way upstream writes its own private files, and kept out of settings
/// backups like the history itself. Filing an entry pins it through
/// upstream's own pin, which may refuse (an entry too large to keep).
final class ForkClipboardBoardStore: ObservableObject {
    static let shared = ForkClipboardBoardStore()

    @Published private(set) var boards = ForkClipboardBoards()
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.clipboard-boards")
    private var loaded = false

    private static var fileURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("ForkClipboardBoards.json")
    }

    private static func defaultName(_ rank: Int) -> String {
        ForkStrings.current.boardDefaultName(rank)
    }

    /// Reads the file once, then drops what upstream's history no longer
    /// holds pinned. Called each time the shelf opens.
    func refresh() {
        if !loaded {
            loaded = true
            boards = ForkClipboardBoards.decoded(Self.fileURL.flatMap { try? Data(contentsOf: $0) })
        }
        let pinned = Set(ClipboardHistoryService.shared.entries.filter(\.isPinned).map(\.id))
        update { $0 = $0.pruned(pinnedIDs: pinned, defaultName: Self.defaultName) }
    }

    @discardableResult
    func create() -> UUID {
        var id = UUID()
        update { id = $0.create(defaultName: Self.defaultName) }
        return id
    }

    func rename(_ id: UUID, to name: String) { update { $0.rename(id, to: name) } }
    func recolor(_ id: UUID, to color: ForkClipboardBoards.Color) { update { $0.recolor(id, to: color) } }
    func delete(_ id: UUID) { update { $0.delete(id) } }
    func remove(_ entry: ClipboardHistoryEntry) { update { $0.remove(entry.id) } }

    /// Files the entry, pinning it first when it is not; nothing changes if
    /// upstream declines to pin it.
    func put(_ entry: ClipboardHistoryEntry, in boardID: UUID) {
        let service = ClipboardHistoryService.shared
        if !entry.isPinned { service.togglePin(entry) }
        let pinned = service.entries.first { $0.id == entry.id }?.isPinned == true
        update { $0.put(entry.id, in: boardID, isPinned: pinned) }
    }

    /// A card dropped on a tab: filed in a pinboard, or taken out of any.
    func drop(_ entry: ClipboardHistoryEntry, on tab: ForkClipboardBoards.Tab) -> Bool {
        switch ForkClipboardBoards.drop(on: tab) {
        case .file(let id):
            put(entry, in: id)
            return true
        case .unfile:
            if !entry.isPinned { ClipboardHistoryService.shared.togglePin(entry) }
            remove(entry)
            return true
        case nil:
            return false
        }
    }

    /// A card dropped on another card of the same pinboard goes just before it.
    func move(_ entryID: UUID, before targetID: UUID?, in boardID: UUID) {
        update { $0.move(entryID, before: targetID, in: boardID) }
    }

    private func update(_ change: (inout ForkClipboardBoards) -> Void) {
        var next = boards
        change(&next)
        guard next != boards else { return }
        boards = next
        guard let url = Self.fileURL, let data = next.encoded() else { return }
        queue.async { _ = PrivateFileStore.write(data, to: url) }
    }
}
