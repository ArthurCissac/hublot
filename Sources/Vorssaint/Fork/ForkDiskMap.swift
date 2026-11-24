// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 9, the disk map (see `ForkDiskMapLogic`): a folder is read in the
/// background, then drawn as rectangles sized by what each item takes on
/// disk. A click on a folder opens it, the path above goes back up, and the
/// item picked can be shown in the Finder or moved to the Trash, after a
/// confirmation. Opened from the Cleaner page; nothing is read before the
/// round button asks for it, nor while the window is closed.
final class ForkDiskMapWindow {
    static let shared = ForkDiskMapWindow()

    /// Opens the Care window on the disk map (lot 9i).
    func show() { ForkCareHub.shared.show(.diskMap) }
}

/// One item of the map: a folder with what it holds, or a file. Small files
/// are only counted in their folder's `looseSize`.
final class ForkDiskNode: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var size: Int64
    var children: [ForkDiskNode]
    /// Files too small to keep one by one, counted here.
    var looseSize: Int64
    weak var parent: ForkDiskNode?

    init(url: URL, isDirectory: Bool, size: Int64, children: [ForkDiskNode] = [], looseSize: Int64 = 0) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
        self.looseSize = looseSize
        for child in children { child.parent = self }
    }

    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

final class ForkDiskMapModel: ObservableObject {
    @Published var root: ForkDiskNode?
    @Published var current: ForkDiskNode?
    @Published var selected: ForkDiskNode?
    @Published var scanning = false
    @Published var scannedFiles = 0
    @Published var scannedPath = ""
    /// The home folder's volume, free and total, for the welcome screen.
    let space: (free: Int64, total: Int64)? = {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity
        else { return nil }
        return (free, Int64(total))
    }()
    /// The reading under way; set to stop it.
    private var progress: Progress?
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.disk-map", qos: .utility)

    func scan(_ url: URL) {
        cancel()
        root = nil
        current = nil
        selected = nil
        scanning = true
        scannedFiles = 0
        let progress = Progress()
        self.progress = progress
        queue.async { [weak self] in
            var lastReport = Date()
            let node = ForkDiskMapModel.read(url, progress: progress) { files, path in
                guard Date().timeIntervalSince(lastReport) > 0.2 else { return }
                lastReport = Date()
                DispatchQueue.main.async { [weak self] in
                    self?.scannedFiles = files
                    self?.scannedPath = path
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.progress === progress, !progress.cancelled else { return }
                self.root = node
                self.current = node
                self.scanning = false
            }
        }
    }

    func cancel() {
        progress?.cancelled = true
        progress = nil
        scanning = false
    }

    /// Shared by the main thread and the reading: a stop flag and a count, read loosely.
    final class Progress: @unchecked Sendable {
        var files = 0
        var cancelled = false
    }

    /// A folder's tree, one level of recursion per folder; links and other
    /// volumes are not followed, unreadable folders count as empty.
    private static func read(_ url: URL, progress: Progress, report: (Int, String) -> Void) -> ForkDiskNode {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .volumeIdentifierKey]
        let volume = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        func walk(_ folder: URL) -> ForkDiskNode {
            if progress.cancelled { return ForkDiskNode(url: folder, isDirectory: true, size: 0) }
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])) ?? []
            var children: [ForkDiskNode] = []
            var loose: Int64 = 0
            var total: Int64 = 0
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    if let volume, let other = values.volumeIdentifier as? NSObject, !other.isEqual(volume) { continue }
                    let child = walk(entry)
                    total += child.size
                    if child.size > 0 { children.append(child) }
                } else {
                    let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    total += size
                    progress.files += 1
                    if size >= ForkDiskMapLogic.smallFile {
                        children.append(ForkDiskNode(url: entry, isDirectory: false, size: size))
                    } else {
                        loose += size
                    }
                }
            }
            report(progress.files, folder.path)
            children.sort { $0.size > $1.size }
            return ForkDiskNode(url: folder, isDirectory: true, size: total, children: children, looseSize: loose)
        }
        return walk(url)
    }

    func open(_ node: ForkDiskNode) {
        guard node.isDirectory else {
            selected = node
            return
        }
        current = node
        selected = nil
    }

    /// The folders from the top to the one shown.
    var path: [ForkDiskNode] {
        var nodes: [ForkDiskNode] = []
        var node = current
        while let next = node {
            nodes.insert(next, at: 0)
            node = next.parent
        }
        return nodes
    }

    func showInFinder(_ node: ForkDiskNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    /// Asks first, then moves the item to the Trash and takes its size off every folder above it.
    func trash(_ node: ForkDiskNode) {
        let text = ForkDiskToolsStrings.current
        let alert = NSAlert()
        alert.messageText = text.trashConfirm(node.name)
        alert.informativeText = text.trashConfirmDetail(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
        alert.addButton(withTitle: text.trash)
        alert.addButton(withTitle: text.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.recycle([node.url]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    let failure = NSAlert(error: error)
                    failure.runModal()
                    return
                }
                node.parent?.children.removeAll { $0 === node }
                var ancestor = node.parent
                while let folder = ancestor {
                    folder.size -= node.size
                    ancestor = folder.parent
                }
                self.selected = nil
                self.objectWillChange.send()
            }
        }
    }
}

/// Screens on the disk map gradient: welcome with one round "Scan" button
/// (any folder through a link), the reading under way, then the map.
struct ForkDiskMapView: View {
    @ObservedObject var model: ForkDiskMapModel
    @State private var hovered: UUID?

    var body: some View {
        let text = ForkDiskToolsStrings.current
        let care = ForkCareStrings.current
        let stage = ForkCareLogic.stage(working: model.scanning, summaryReady: model.current != nil)
        ZStack {
            ForkCareBackground(tool: .diskMap)
            Group {
                switch stage {
                case .welcome: welcome(text, care).padding(.horizontal, 32).padding(.vertical, 24)
                case .working: reading(text, care).padding(.horizontal, 32).padding(.vertical, 24)
                case .summary:
                    if let current = model.current { result(current, text, care).padding(.top, 28) }
                }
            }
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.22), value: stage)
        .environment(\.forkCareTool, .diskMap)
    }

    // MARK: - Welcome and reading

    private func welcome(_ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForkCareHero(symbol: "square.grid.3x3.square", title: text.diskMapTitle, subtitle: care.diskSubtitle)
            if let space = model.space {
                Text(care.freeSpace(Self.bytes(space.free), Self.bytes(space.total)))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.careSecondary)
            }
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.analyze) { model.scan(URL(fileURLWithPath: NSHomeDirectory())) }
            ForkCareLink(title: text.chooseFolder, symbol: "folder") { chooseFolder() }
        }
    }

    private func reading(_ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForkCareRoundButton(title: care.working, working: true) {}
            Text(text.scanning(model.scannedFiles))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.carePrimary)
                .monospacedDigit()
            Text(model.scannedPath)
                .font(.system(size: 12))
                .foregroundStyle(Color.careSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            ForkCareLink(title: care.stop, symbol: "stop.fill") { model.cancel() }
            Spacer(minLength: 8)
        }
    }

    // MARK: - Result

    private func result(_ current: ForkDiskNode, _ text: ForkDiskToolsStrings, _ care: ForkCareStrings) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(model.path) { node in
                    Button(node.name) { model.open(node) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: node === model.path.last ? .semibold : .regular))
                        .foregroundStyle(node === model.path.last ? Color.carePrimary : Color.careSecondary)
                    if node !== model.path.last {
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.careSecondary)
                    }
                }
                Text(Self.bytes(current.size)).font(.system(size: 12)).foregroundStyle(Color.careSecondary).padding(.leading, 6)
                Spacer()
                ForkCareLink(title: text.chooseFolder, symbol: "folder") { chooseFolder() }
                ForkCareLink(title: text.rescan, symbol: "arrow.clockwise") { if let root = model.root { model.scan(root.url) } }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            HSplitView {
                map(current).frame(minWidth: 420)
                list(current, text).frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
            }
        }
    }

    private func items(_ folder: ForkDiskNode) -> (nodes: [ForkDiskNode], rest: Int64) {
        let shown = ForkDiskMapLogic.shown(sizes: folder.children.map(\.size))
        return (shown.indices.map { folder.children[$0] }, shown.rest + folder.looseSize)
    }

    private func map(_ folder: ForkDiskNode) -> some View {
        GeometryReader { proxy in
            let content = items(folder)
            let sizes = content.nodes.map { Double($0.size) } + (content.rest > 0 ? [Double(content.rest)] : [])
            let frames = ForkDiskMapLogic.squarify(sizes, in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 8, dy: 8))
            ZStack(alignment: .topLeading) {
                ForEach(Array(content.nodes.enumerated()), id: \.element.id) { index, node in
                    tile(node, frame: frames[index], tint: Self.tint(index, directory: node.isDirectory))
                }
                if content.rest > 0, let frame = frames.last {
                    // A neutral slate that carries the white label on either background.
                    RoundedRectangle(cornerRadius: 6).fill(Color(care: ForkCareLogic.RGB(hex: 0x64748B)).opacity(0.85))
                        .overlay(label(ForkDiskToolsStrings.current.other, size: content.rest, frame: frame))
                        .frame(width: max(0, frame.width - 3), height: max(0, frame.height - 3))
                        .offset(x: frame.minX + 1.5, y: frame.minY + 1.5)
                }
            }
        }
    }

    private func tile(_ node: ForkDiskNode, frame: CGRect, tint: Color) -> some View {
        let picked = model.selected === node
        return RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(hovered == node.id ? 1 : 0.82))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(picked ? Color.carePrimary : Color.clear, lineWidth: 2.5))
            .overlay(label(node.name, size: node.size, frame: frame))
            .frame(width: max(0, frame.width - 3), height: max(0, frame.height - 3))
            .offset(x: frame.minX + 1.5, y: frame.minY + 1.5)
            .onHover { inside in hovered = inside ? node.id : (hovered == node.id ? nil : hovered) }
            .onTapGesture(count: 2) { model.open(node) }
            .onTapGesture { model.selected = node }
            .screenshotSafeHelp(node.url.path)
            .accessibilityElement()
            .accessibilityLabel("\(node.name), \(Self.bytes(node.size))")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func label(_ name: String, size: Int64, frame: CGRect) -> some View {
        if frame.width > 70, frame.height > 34 {
            VStack(spacing: 2) {
                Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(Self.bytes(size)).font(.system(size: 10))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .padding(4)
        }
    }

    private static func tint(_ index: Int, directory: Bool) -> Color {
        guard directory else { return Color(nsColor: .systemGray) }
        let palette: [NSColor] = [.systemBlue, .systemTeal, .systemIndigo, .systemPurple, .systemGreen, .systemOrange, .systemPink, .systemBrown]
        return Color(nsColor: palette[index % palette.count])
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func list(_ folder: ForkDiskNode, _ text: ForkDiskToolsStrings) -> some View {
        VStack(spacing: 0) {
            List(folder.children.prefix(200)) { node in
                HStack {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(node.isDirectory ? Color.carePrimary : Color.careSecondary)
                    Text(node.name).foregroundStyle(Color.carePrimary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Self.bytes(node.size)).monospacedDigit().foregroundStyle(Color.careSecondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.open(node) }
                .onTapGesture { model.selected = node }
                .listRowBackground(model.selected === node ? Color.careFill(0.16) : Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.18))
            HStack {
                if let selected = model.selected {
                    Text(selected.name).font(.system(size: 12)).foregroundStyle(Color.carePrimary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(text.showInFinder) { model.showInFinder(selected) }.buttonStyle(.bordered).controlSize(.small)
                    Button(text.trash, role: .destructive) { model.trash(selected) }.buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(text.pickHint).font(.system(size: 12)).foregroundStyle(Color.careSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.25))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.root?.url
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.scan(url)
    }
}
