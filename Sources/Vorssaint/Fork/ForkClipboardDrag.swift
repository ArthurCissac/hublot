// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// A clipboard card being dragged. Out of the shelf it carries what was
/// copied, for whichever app it is dropped on; inside the shelf, the tabs and
/// the cards of a pinboard recognize it by the card it came from, never by
/// what it carries, so text dragged in from another app is not taken for a card.
/// Main thread only.
enum ForkClipboardDrag {
    private static var current: (id: UUID, since: Date)?
    /// A drag longer than this has long been dropped somewhere else.
    private static let lifetime: TimeInterval = 60

    static func begin(_ entry: ClipboardHistoryEntry) -> NSItemProvider {
        current = (entry.id, Date())
        return itemProvider(for: entry)
    }

    /// The card being dragged, read once by the place it is dropped on.
    static func take() -> UUID? {
        defer { current = nil }
        guard let current, Date().timeIntervalSince(current.since) <= lifetime else { return nil }
        return current.id
    }

    static func cancel() {
        current = nil
    }

    /// What the card carries to another app: its text, its picture, or its first file.
    static func itemProvider(for entry: ClipboardHistoryEntry) -> NSItemProvider {
        switch entry.kind {
        case .text:
            return NSItemProvider(object: entry.text as NSString)
        case .image:
            if let name = entry.imageFile, let directory = ClipboardImageStore.directory,
               let image = NSImage(contentsOf: directory.appendingPathComponent(name)) {
                return NSItemProvider(object: image)
            }
        case .files:
            if let first = entry.filePaths.first {
                return NSItemProvider(object: URL(fileURLWithPath: first) as NSURL)
            }
        }
        return NSItemProvider()
    }
}
