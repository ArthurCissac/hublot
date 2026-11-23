// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The clipboard history as a shelf of large cards along the bottom of the
/// screen, opened by every way upstream opens its history. Upstream keeps
/// the entries, the search, the copy and the pins; the shelf shows them and
/// pastes into the app that was in front.
///
/// Reached from two lines at the head of upstream's `toggleHistoryWindow`
/// and `showHistoryWindow`, which go on with upstream's own window or island
/// page when this returns false. Main thread only.
final class ForkClipboardShelf {
    typealias Layout = ForkClipboardShelfLayout

    static let shared = ForkClipboardShelf()

    private var panel: ForkClipboardShelfPanel?
    private let model = ForkClipboardShelfModel()
    private var pasteTarget: NSRunningApplication?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var closing = false

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkClipboardShelf) && AppFeature.clipboardHistory.isAvailable
    }

    var isVisible: Bool { panel?.isVisible == true && !closing }

    /// Opens or closes the shelf. False when the shelf is off: upstream goes on.
    func toggle() -> Bool {
        guard Self.isEnabled() else { return false }
        if isVisible { hide() } else { present() }
        return true
    }

    /// Opens the shelf. False when the shelf is off: upstream goes on.
    func show() -> Bool {
        guard Self.isEnabled() else { return false }
        present()
        return true
    }

    private func present() {
        rememberPasteTarget()
        let panel = ensurePanel()
        model.open()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = Layout.shelfFrame(screenFrame: screen?.frame ?? .zero)
        closing = false
        panel.alphaValue = 1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
        } else {
            // Up from below the screen's bottom edge. The size never changes, so the frame can move.
            panel.setFrame(Layout.hiddenFrame(for: frame), display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().setFrame(frame, display: true)
            }
        }
        panel.makeKey()
        installMonitors()
    }

    func hide() {
        removeMonitors()
        guard let panel, panel.isVisible, !closing else { return }
        model.close()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        // Back down below the screen's edge.
        closing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(Layout.hiddenFrame(for: panel.frame), display: true)
        }, completionHandler: { [weak self, weak panel] in
            guard let self, self.closing else { return }
            self.closing = false
            panel?.orderOut(nil)
        })
    }

    /// The app in front when the shelf opened gets the paste.
    private func rememberPasteTarget() {
        let app = NSWorkspace.shared.frontmostApplication
        pasteTarget = app.flatMap {
            Layout.pasteTargetIsUsable(bundleID: $0.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier,
                                       isTerminated: $0.isTerminated, isRegular: $0.activationPolicy == .regular)
                ? $0 : nil
        }
    }

    private func ensurePanel() -> ForkClipboardShelfPanel {
        if let panel { return panel }
        let panel = ForkClipboardShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        // The level of the menu bar, over the Dock it covers, as measured on the reference app.
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = ForkClipboardShelfView(model: model) { [weak self] action, entry in
            self?.perform(action, on: entry)
        }
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        return panel
    }

    // MARK: - Actions

    func perform(_ action: Layout.Action, on entry: ClipboardHistoryEntry? = nil) {
        let service = ClipboardHistoryService.shared
        switch action {
        case .close:
            hide()
        case .previous, .next, .first, .last:
            model.move(action)
        case .previousTab, .nextTab:
            model.switchTab(forward: action == .nextTab)
        case .preview:
            model.togglePreview()
        case .paste, .copy:
            guard let entry = entry ?? model.selectedEntry else { return }
            copy(entry, thenPaste: action == .paste)
        case .pasteNumber(let number):
            guard let entry = model.entry(numbered: number) else { return }
            copy(entry, thenPaste: true)
        case .remove:
            guard let entry = entry ?? model.selectedEntry else { return }
            model.willRemove(entry)
            ForkClipboardBoardStore.shared.remove(entry)
            service.remove(entry)
        case .togglePin:
            guard let entry = entry ?? model.selectedEntry else { return }
            service.togglePin(entry)
        }
    }

    /// Upstream's copy, then the paste in the app that was in front, once the
    /// keys still held for ⌘1 to ⌘9 are released.
    private func copy(_ entry: ClipboardHistoryEntry, thenPaste: Bool) {
        let target = pasteTarget
        // Copying a card again is no new copy: no sound.
        ForkClipboardCopySoundPlayer.shared.stayQuiet()
        ClipboardHistoryService.shared.copy(entry) { [weak self] copied in
            guard let self else { return }
            self.hide()
            guard copied else {
                NSSound.beep()
                return
            }
            guard thenPaste, let target, !target.isTerminated else { return }
            target.activate(options: [])
            guard ClipboardHistoryPasteTarget.acceptsSyntheticPaste(bundleID: target.bundleIdentifier) else { return }
            guard AXIsProcessTrusted() else {
                Permissions.shared.requestAccessibility()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                TransientPaste.shared.pasteCurrentContents()
            }
        }
    }

    // MARK: - Keys and dismissal

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            // A pinboard being renamed takes every key, Return and Escape included.
            if self.model.renamingBoardID != nil { return event }
            let flags = event.modifierFlags
            guard let action = Layout.action(keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers,
                                             command: flags.contains(.command), option: flags.contains(.option),
                                             shift: flags.contains(.shift), control: flags.contains(.control),
                                             queryIsEmpty: self.model.query.isEmpty)
            else { return event }
            self.perform(action)
            return nil
        }
        // A click anywhere else puts the shelf away, as Paste does.
        let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.hide() }
        }
        monitors = [keys, clicks].compactMap { $0 }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // The paste itself brings the target back in front: that is not a reason to close.
            guard app?.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
            self?.hide()
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }
}

/// The shelf's window: it takes the keyboard for the search and the keys,
/// without making the app active, so the app in front stays the one to paste into.
final class ForkClipboardShelfPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// What the shelf shows: the search, the cards it finds, the selection.
final class ForkClipboardShelfModel: ObservableObject {
    typealias Layout = ForkClipboardShelfLayout

    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published var selectionID: UUID?
    @Published private(set) var previewing = false
    @Published private(set) var presentation = UUID()
    @Published var tab: ForkClipboardBoards.Tab = .history { didSet { if tab != oldValue { selectionID = nil; refresh() } } }
    @Published var renamingBoardID: UUID?
    private var watcher: Any?
    private var boardsWatcher: Any?

    var selectedEntry: ClipboardHistoryEntry? { entries.first { $0.id == selectionID } ?? entries.first }

    func open() {
        presentation = UUID()
        query = ""
        previewing = false
        renamingBoardID = nil
        ForkClipboardBoardStore.shared.refresh()
        // A pinboard deleted meanwhile leaves its tab.
        if !ForkClipboardBoardStore.shared.boards.tabs.contains(tab) { tab = .history }
        refresh()
        selectionID = entries.first?.id
        if boardsWatcher == nil {
            boardsWatcher = ForkClipboardBoardStore.shared.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        if watcher == nil {
            watcher = ClipboardHistoryService.shared.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
    }

    func close() {
        ClipboardHistoryService.shared.cancelSearch(on: .view(presentation))
        watcher = nil
        boardsWatcher = nil
        ForkClipboardDrag.cancel()
        previewing = false
        renamingBoardID = nil
        query = ""
    }

    func refresh() {
        let found = ClipboardHistoryService.shared.filteredEntries(matching: query, surface: .view(presentation)) { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        // A search keeps upstream's ranking; the full history reads newest first.
        let ordered = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? Layout.ordered(found, copiedAt: \.copiedAt) : found
        entries = ForkClipboardBoardStore.shared.boards.entries(for: tab, from: ordered, id: \.id, isPinned: \.isPinned)
        if let selectionID, !entries.contains(where: { $0.id == selectionID }) {
            self.selectionID = entries.first?.id
        } else if selectionID == nil {
            selectionID = entries.first?.id
        }
    }

    func move(_ action: Layout.Action) {
        let index = entries.firstIndex { $0.id == selectionID }
        guard let next = Layout.moved(action, from: index, count: entries.count) else { return }
        selectionID = entries[next].id
    }

    func switchTab(forward: Bool) {
        tab = ForkClipboardBoardStore.shared.boards.tab(beside: tab, forward: forward)
    }

    func entry(numbered number: Int) -> ClipboardHistoryEntry? {
        let index = number - 1
        return entries.indices.contains(index) ? entries[index] : nil
    }

    func willRemove(_ entry: ClipboardHistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let next = Layout.selectionAfterRemoving(at: index, count: entries.count)
        selectionID = next.map { $0 >= index ? entries[$0 + 1].id : entries[$0].id }
    }

    func togglePreview() {
        previewing.toggle()
    }

    func closePreview() {
        previewing = false
    }
}
