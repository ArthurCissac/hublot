// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI
import UniformTypeIdentifiers

/// The shelf's drawing, at the reference app's measures (docs/reference/paste.md):
/// a dark panel along the bottom of the screen, the search and the tabs
/// centred on one line, square cards with a band in their app's colour.
/// Upstream's own preview opens beside the cards on Space.
struct ForkClipboardShelfView: View {
    typealias Layout = ForkClipboardShelfLayout

    @ObservedObject var model: ForkClipboardShelfModel
    @ObservedObject private var store = ForkClipboardBoardStore.shared
    @ObservedObject private var l10n = L10n.shared
    let perform: (Layout.Action, ClipboardHistoryEntry?) -> Void
    @FocusState private var searchFocused: Bool
    @State private var editingPreview = false
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool
    @AppStorage(DefaultsKey.forkClipboardShelfGlass) private var glass = true
    @AppStorage(DefaultsKey.forkClipboardShelfTint) private var tintHex = ForkShelfTint.defaultHex
    @AppStorage(DefaultsKey.forkClipboardShelfTintIntensity) private var tintIntensity = ForkShelfTint.defaultIntensity
    /// The tab a card is being dragged over.
    @State private var dropTab: ForkClipboardBoards.Tab?
    private static let dragTypes: [UTType] = [.text, .image, .fileURL]

    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 2 * (Layout.headerCenter - Layout.panelInset.top))
            Color.clear
                .frame(height: max(0, Layout.cardTop - 2 * Layout.headerCenter + Layout.panelInset.top))
            HStack(spacing: 0) {
                cards
                if model.previewing, let entry = model.selectedEntry {
                    ClipboardEntryPreviewSidebar(text: text, entry: entry, isEditing: $editingPreview,
                                                 onClose: { model.closePreview() })
                        .frame(width: 320)
                        .padding(.trailing, 12)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { panelBackground }
        .overlay(panelShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.leading, Layout.panelInset.side)
        .padding(.trailing, Layout.panelInset.side)
        .padding(.bottom, Layout.panelInset.bottom)
        .padding(.top, Layout.panelInset.top)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.presentation) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }

    /// The colour chosen in the settings, at its strength; nil for none.
    private var tint: Color? {
        guard let rgb = ForkShelfTint.components(tintHex) else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private var usesGlass: Bool {
        if #available(macOS 26.0, *) { return glass }
        return false
    }

    /// Liquid Glass on macOS 26 and later when chosen, tinted; otherwise the
    /// dark panel measured on the reference app, with the tint laid over it.
    @ViewBuilder
    private var panelBackground: some View {
        let strength = ForkShelfTint.intensity(tintIntensity)
        if #available(macOS 26.0, *), glass {
            Color.clear
                .glassEffect(.regular.tint(tint?.opacity(strength)), in: panelShape)
        } else {
            ZStack {
                panelShape.fill(.ultraThickMaterial)
                panelShape.fill(ForkShelfColors.panel)
                if let tint { panelShape.fill(tint.opacity(strength * 0.55)) }
            }
        }
    }

    // MARK: - Header

    /// The app's icon at the left, the search and the tabs in the middle, the new pinboard button after them.
    private var header: some View {
        ZStack {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Spacer()
            }
            .padding(.horizontal, 18)
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(model.query.isEmpty ? 0.85 : 1))
                        .onTapGesture { searchFocused = true }
                    // Typing anywhere searches: the field is there, unseen, until something is typed.
                    TextField("", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($searchFocused)
                        .frame(width: model.query.isEmpty ? 1 : 180)
                        .opacity(model.query.isEmpty ? 0.01 : 1)
                }
                tabBar
            }
        }
    }

    private var tabBar: some View {
        let fork = ForkStrings.current
        return HStack(spacing: 6) {
            tabButton(.history, title: fork.tabHistory, symbol: "clock.arrow.circlepath", color: nil)
            tabButton(.pinned, title: fork.tabPinned, symbol: "pin", color: nil)
            ForEach(store.boards.boards) { board in
                if model.renamingBoardID == board.id {
                    TextField("", text: $renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(width: 140)
                        .focused($renameFocused)
                        .onSubmit { finishRename(board.id) }
                        .onExitCommand { model.renamingBoardID = nil; searchFocused = true }
                        .onChange(of: renameFocused) { _, focused in if !focused { finishRename(board.id) } }
                } else {
                    tabButton(.board(board.id), title: board.name, symbol: nil, color: board.color)
                        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(board) })
                        .contextMenu { boardMenu(board) }
                }
            }
            Button {
                let id = store.create()
                model.tab = .board(id)
                if let board = store.boards.boards.first(where: { $0.id == id }) { startRename(board) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: Layout.tabHeight)
            }
            .buttonStyle(.plain)
            .help(fork.newBoard)
            .accessibilityLabel(fork.newBoard)
        }
    }

    private func tabButton(_ tab: ForkClipboardBoards.Tab, title: String, symbol: String?,
                           color: ForkClipboardBoards.Color?) -> some View {
        let selected = model.tab == tab
        return Button { model.tab = tab } label: {
            HStack(spacing: 7) {
                if let color {
                    Circle().fill(Self.swatch(color)).frame(width: 9, height: 9)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.85))
            .padding(.horizontal, 12)
            .frame(height: Layout.tabHeight)
            .background { tabBackground(selected: selected) }
            .overlay {
                if dropTab == tab { Capsule().strokeBorder(ForkShelfColors.selection, lineWidth: 2) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // A card dropped on a pinboard's tab is filed there; on Pinned it leaves its pinboard.
        .onDrop(of: Self.dragTypes, isTargeted: Binding(
            get: { dropTab == tab },
            set: { targeted in
                if targeted, ForkClipboardBoards.drop(on: tab) != nil { dropTab = tab } else if dropTab == tab { dropTab = nil }
            })) { _ in
            dropTab = nil
            guard let id = ForkClipboardDrag.take(),
                  let entry = ClipboardHistoryService.shared.entries.first(where: { $0.id == id }) else { return false }
            return store.drop(entry, on: tab)
        }
    }

    @ViewBuilder
    private func tabBackground(selected: Bool) -> some View {
        if selected {
            if #available(macOS 26.0, *), glass {
                Color.clear.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                Capsule().fill(ForkShelfColors.selectedTab)
            }
        }
    }

    @ViewBuilder
    private func boardMenu(_ board: ForkClipboardBoards.Board) -> some View {
        let fork = ForkStrings.current
        Button(fork.renameBoard) { startRename(board) }
        Menu(fork.boardColor) {
            ForEach(ForkClipboardBoards.Color.allCases, id: \.self) { color in
                Button(fork.colorName(color)) { store.recolor(board.id, to: color) }
            }
        }
        Divider()
        Button(fork.deleteBoard, role: .destructive) {
            if model.tab == .board(board.id) { model.tab = .history }
            store.delete(board.id)
        }
    }

    private func startRename(_ board: ForkClipboardBoards.Board) {
        renameDraft = board.name
        model.renamingBoardID = board.id
        DispatchQueue.main.async { renameFocused = true }
    }

    private func finishRename(_ id: UUID) {
        guard model.renamingBoardID == id else { return }
        store.rename(id, to: renameDraft)
        model.renamingBoardID = nil
        searchFocused = true
    }

    static func swatch(_ color: ForkClipboardBoards.Color) -> Color {
        switch color {
        case .red: return Color(red: 0.94, green: 0.27, blue: 0.27)
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return Color(red: 0.2, green: 0.55, blue: 1)
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cards: some View {
        if model.entries.isEmpty {
            Text(emptyText)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.cardSize.height)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Layout.cardSpacing) {
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            ForkClipboardCard(entry: entry, number: Layout.shortcutNumber(at: index),
                                              selected: entry.id == model.selectionID, text: text,
                                              board: store.boards.board(of: entry.id), glass: usesGlass)
                                .id(entry.id)
                                // A click copies the card and closes the shelf at once. No
                                // double-click on top of it: telling the two apart made every
                                // click wait a third of a second.
                                .onTapGesture {
                                    model.selectionID = entry.id
                                    perform(.copy, entry)
                                }
                                .contextMenu { menu(for: entry) }
                                // Dragged out, the card carries its content to another app, or to a tab.
                                .onDrag { ForkClipboardDrag.begin(entry) }
                                // In a pinboard, a card dropped on another goes just before it.
                                .onDrop(of: Self.dragTypes, isTargeted: nil) { _ in
                                    guard case .board(let boardID) = model.tab, let id = ForkClipboardDrag.take() else {
                                        return false
                                    }
                                    store.move(id, before: entry.id, in: boardID)
                                    return true
                                }
                        }
                    }
                    .padding(.horizontal, Layout.cardLeading)
                    // Room for the selection ring, which is drawn outside the card.
                    .padding(.vertical, Layout.selectionWidth)
                }
                .frame(height: Layout.cardSize.height + 2 * Layout.selectionWidth)
                .onChange(of: model.selectionID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .padding(.top, -Layout.selectionWidth)
        }
    }

    private var emptyText: String {
        guard model.query.isEmpty else { return text.noResults }
        switch model.tab {
        case .history: return text.empty
        case .pinned: return ForkStrings.current.pinnedEmpty
        case .board: return ForkStrings.current.boardEmpty
        }
    }

    @ViewBuilder
    private func menu(for entry: ClipboardHistoryEntry) -> some View {
        let fork = ForkStrings.current
        Button(fork.clipboardPaste) { perform(.paste, entry) }
        Button(text.copy) { perform(.copy, entry) }
        Button(entry.isPinned ? text.unpin : text.pin) {
            if entry.isPinned { store.remove(entry) }
            perform(.togglePin, entry)
        }
        Menu(fork.fileIn) {
            ForEach(store.boards.boards) { board in
                Button(board.name) { store.put(entry, in: board.id) }
                    .disabled(store.boards.board(of: entry.id)?.id == board.id)
            }
            if !store.boards.boards.isEmpty { Divider() }
            Button(fork.newBoard) { store.put(entry, in: store.create()) }
        }
        if store.boards.board(of: entry.id) != nil {
            Button(fork.removeFromBoard) { store.remove(entry) }
        }
        Divider()
        Button(text.delete, role: .destructive) { perform(.remove, entry) }
    }
}

/// The shelf's colours, as measured on the reference app in dark mode.
enum ForkShelfColors {
    static let panel = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255).opacity(0.72)
    static let selectedTab = Color(red: 0x31 / 255, green: 0x31 / 255, blue: 0x31 / 255)
    static let cardBody = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255)
    static let neutralBand = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)
    static let selection = Color(red: 0, green: 0x7A / 255, blue: 1)
}

/// One card: a band in its app's colour with the kind of content, when it
/// was copied and the app's icon; the content; a detail centred at the foot;
/// its ⌘-number and the colour of the pinboard it is filed in.
struct ForkClipboardCard: View {
    typealias Layout = ForkClipboardShelfLayout

    let entry: ClipboardHistoryEntry
    let number: Int?
    let selected: Bool
    let text: ClipboardFeatureStrings
    var board: ForkClipboardBoards.Board?
    /// In Liquid Glass, a card lets a little of the glass show through.
    var glass = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 10)
            footer
        }
        .frame(width: Layout.cardSize.width, height: Layout.cardSize.height)
        .background(ForkShelfColors.cardBody.opacity(glass ? 0.8 : 1))
        .clipShape(shape)
        .background {
            // The selection ring sits outside the card, as on the reference app.
            if selected {
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius + Layout.selectionWidth, style: .continuous)
                    .fill(ForkShelfColors.selection)
                    .padding(-Layout.selectionWidth)
            }
        }
        .contentShape(shape)
    }

    /// The band takes the colour of the app's icon; neutral when it has none.
    private var tint: Color {
        entry.sourceBundleID.flatMap(ForkAppTint.color(for:)) ?? ForkShelfColors.neutralBand
    }

    private var band: some View {
        ZStack(alignment: .leading) {
            tint
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(kindTitle)
                        .font(.system(size: 15, weight: .bold))
                    Text(entry.copiedAt, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                Spacer(minLength: 4)
                if let board {
                    Circle().fill(ForkClipboardShelfView.swatch(board.color))
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1) }
                        .frame(width: 10, height: 10)
                        .help(board.name)
                        .padding(.trailing, 6)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 58)
            // The app's icon, large, cut off by the card's edge.
            if let bundleID = entry.sourceBundleID {
                Image(nsImage: InstalledApps.icon(for: bundleID))
                    .resizable()
                    .frame(width: 60, height: 60)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 8)
            }
        }
        .frame(height: Layout.bandHeight)
        .clipped()
    }

    private var kindTitle: String {
        let fork = ForkStrings.current
        switch entry.kind {
        case .image: return fork.kindImage
        case .files: return entry.filePaths.count > 1 ? fork.kindFiles : fork.kindFile
        case .text:
            switch ForkClipboardCardInfo.detail(forText: entry.text) {
            case .link: return fork.kindLink
            case .color: return fork.kindColor
            default: return fork.kindText
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .text:
            if case let .color(red, green, blue) = ForkClipboardCardInfo.detail(forText: entry.text) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: red, green: green, blue: blue))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 8)
            } else {
                Text(entry.text.prefix(700))
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(1)
                    // The text fades out toward the foot instead of being cut.
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: aspect, contentMode: .fit, failureText: text.imageEntryLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            VStack(alignment: .leading, spacing: 6) {
                if let first = entry.filePaths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                        .resizable()
                        .frame(width: 56, height: 56)
                }
                Text(entry.fileNames.joined(separator: "\n"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(5)
            }
        }
    }

    private var aspect: CGFloat? {
        guard let width = entry.imageWidth, let height = entry.imageHeight, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    /// A text's length, a link's site, a colour's value, a picture's size, a number of files.
    private var detail: String {
        let fork = ForkStrings.current
        switch entry.kind {
        case .image: return entry.imageDimensionsLabel
        case .files: return String(format: text.fileCountFormat, entry.filePaths.count)
        case .text:
            switch ForkClipboardCardInfo.detail(forText: entry.text) {
            case .link(let domain): return domain
            case .color: return entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .text(let characters): return fork.clipboardCharacters(characters)
            case .image, .files: return ""
            }
        }
    }

    private var footer: some View {
        ZStack {
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .padding(.horizontal, 34)
            if let number {
                Text("⌘\(number)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
            }
        }
        .frame(height: 36)
    }
}
