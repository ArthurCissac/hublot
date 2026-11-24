// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 9i: the Care window. Every cleaning tool in one window, a sidebar on
/// the left to go from one to another: the one-click scan, upstream's
/// cleaner, the antivirus, maintenance, upstream's uninstaller and the disk
/// map. A scan under way goes on while another tool is shown; closing the
/// window stops it, as each tool's own window used to. Every way in (the
/// Cleaner page's bar, the menu's Disks tools, the tiles, a tool's own
/// buttons) opens it on the right tool. Laid out by the fork; nothing comes
/// from another app. The logic is `ForkCareHubLogic`.
final class ForkCareHub {
    typealias Module = ForkCareHubLogic.Module
    static let shared = ForkCareHub()
    private var window: NSWindow?
    private(set) var model: ForkCareHubModel?

    func isShowing(_ module: Module) -> Bool {
        window != nil && model?.module == module
    }

    /// `antivirus` hands over a scan already made (by the one-click scan or
    /// the downloads' watch), so its threats show in Protection.
    func show(_ module: Module? = nil, antivirus: ForkAntivirusModel? = nil) {
        if let window, let model {
            if let antivirus { model.adopt(antivirus) }
            if let module { model.select(module) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let start = module ?? ForkCareHubLogic.module(stored: UserDefaults.standard.string(forKey: DefaultsKey.forkCareHubModule))
        let model = ForkCareHubModel(start: start, antivirus: antivirus)
        let window = ForkCareWindow.make(title: ForkCareHubStrings.current.title,
                                         size: NSSize(width: 1_080, height: 700), minSize: NSSize(width: 920, height: 580),
                                         content: ForkCareHubView(model: model))
        window.setFrameAutosaveName("ForkCareHub")
        // Lot 9j: the backgrounds are drawn for the dark; the window keeps it.
        window.appearance = NSAppearance(named: .darkAqua)
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                               queue: .main) { [weak model, weak window] _ in
            model?.visible = window?.occlusionState.contains(.visible) ?? false
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            model.stop()
            self?.window = nil
            self?.model = nil
        }
        self.window = window
        self.model = model
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

final class ForkCareHubModel: ObservableObject {
    typealias Module = ForkCareHubLogic.Module
    @Published private(set) var module: Module
    let smartScan: ForkSmartScanModel
    @Published private(set) var antivirus: ForkAntivirusModel
    /// The window can be seen: the backgrounds move only then.
    @Published var visible = true
    let maintenance = ForkMaintenanceModel()
    let diskMap = ForkDiskMapModel()

    init(start: Module, antivirus given: ForkAntivirusModel?) {
        module = start
        // Opens on a scheduled scan's results when one is waiting.
        smartScan = ForkCareAutomation.shared.takeScheduledScan() ?? ForkSmartScanModel()
        antivirus = given ?? smartScan.antivirus
    }

    func select(_ module: Module) {
        self.module = module
        UserDefaults.standard.set(module.rawValue, forKey: DefaultsKey.forkCareHubModule)
    }

    /// Another scan's results replace the antivirus shown; one of its own
    /// that was running is stopped, the one-click scan's is left to it.
    func adopt(_ given: ForkAntivirusModel) {
        guard given !== antivirus else { return }
        if antivirus !== smartScan.antivirus { antivirus.cancel() }
        antivirus = given
    }

    func stop() {
        smartScan.stopScanning()
        antivirus.cancel()
        if smartScan.antivirus !== antivirus { smartScan.antivirus.cancel() }
        diskMap.cancel()
    }
}

/// Upstream's Cleaner page drops the fork's tools bar inside the Care
/// window, whose sidebar already leads to every tool.
private struct ForkInCareHubKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forkInCareHub: Bool {
        get { self[ForkInCareHubKey.self] }
        set { self[ForkInCareHubKey.self] = newValue }
    }
}

// MARK: - The window

struct ForkCareHubView: View {
    @ObservedObject var model: ForkCareHubModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForkCareHubSidebar(model: model)
                .frame(width: 240)
            content
                .id(model.module)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.module)
        .environment(\.forkInCareHub, true)
        .environment(\.forkCareHubVisible, model.visible)
        .frame(minWidth: 920, minHeight: 580)
    }

    @ViewBuilder
    private var content: some View {
        switch model.module {
        case .smartScan: ForkCareWorkingSmartScan(scan: model.smartScan) { ForkSmartScanView(model: model.smartScan) }
        case .cleanup: upstreamPage(.cleanup) { CleanerSettings() }
        case .protection: ForkCareWorkingAntivirus(antivirus: model.antivirus) { ForkAntivirusView(model: model.antivirus) }
        case .performance: ForkCareWorkingMaintenance(maintenance: model.maintenance) { ForkMaintenanceView(model: model.maintenance) }
        case .applications: upstreamPage(.applications) { UninstallerView() }
        case .diskMap: ForkCareWorkingDiskMap(map: model.diskMap) { ForkDiskMapView(model: model.diskMap) }
        }
    }

    /// Upstream's pages as they are, under a band of the tool's animated picture.
    private func upstreamPage<Page: View>(_ module: ForkCareHubLogic.Module, @ViewBuilder _ page: () -> Page) -> some View {
        VStack(spacing: 0) {
            ForkCareHubBanner(module: module, working: false)
            page()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Each tool tells its background when it works

private struct ForkCareWorkingSmartScan<Content: View>: View {
    @ObservedObject var scan: ForkSmartScanModel
    @ViewBuilder let content: () -> Content
    var body: some View {
        let working: Bool = { switch scan.phase { case .scanning, .running: return true; default: return false } }()
        content().environment(\.forkCareHubWorking, working)
    }
}

private struct ForkCareWorkingAntivirus<Content: View>: View {
    @ObservedObject var antivirus: ForkAntivirusModel
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().environment(\.forkCareHubWorking, antivirus.activity != .idle)
    }
}

private struct ForkCareWorkingMaintenance<Content: View>: View {
    @ObservedObject var maintenance: ForkMaintenanceModel
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().environment(\.forkCareHubWorking, maintenance.running)
    }
}

private struct ForkCareWorkingDiskMap<Content: View>: View {
    @ObservedObject var map: ForkDiskMapModel
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().environment(\.forkCareHubWorking, map.scanning)
    }
}

/// The sidebar: the window's title, then one row per tool, its hue behind
/// the selected one.
private struct ForkCareHubSidebar: View {
    @ObservedObject var model: ForkCareHubModel

    var body: some View {
        let text = ForkCareHubStrings.current
        VStack(alignment: .leading, spacing: 4) {
            Text(text.title)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.top, 50)
                .padding(.bottom, 14)
            ForEach(ForkCareHubLogic.Module.allCases) { module in
                ForkCareHubRow(module: module, selected: model.module == module,
                               state: ForkCareHubStateLine(model: model, module: module)) {
                    model.select(module)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                ForkCareHubSidebarMaterial()
                LinearGradient(colors: [Color(care: model.module.tint).opacity(0.22), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
    }
}

private struct ForkCareHubRow<State: View>: View {
    let module: ForkCareHubLogic.Module
    let selected: Bool
    let state: State
    let action: () -> Void
    @SwiftUI.State private var hovered = false

    var body: some View {
        let text = ForkCareHubStrings.current
        let tint = Color(care: module.tint)
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                    Image(systemName: module.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.name(module)).font(.system(size: 13, weight: .semibold))
                    state.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.1 : (hovered ? 0.05 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(selected ? 0.45 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(module.digit)")), modifiers: .command)
        .onHover { hovered = $0 }
        .help("\(text.name(module)) (⌘\(module.digit))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The short line under a tool's name: what it is doing or found, else what it is for.
private struct ForkCareHubStateLine: View {
    @ObservedObject var model: ForkCareHubModel
    let module: ForkCareHubLogic.Module

    var body: some View {
        switch module {
        case .smartScan: SmartScanLine(scan: model.smartScan)
        case .protection: ProtectionLine(antivirus: model.antivirus)
        case .performance: PerformanceLine(maintenance: model.maintenance)
        case .diskMap: DiskMapLine(map: model.diskMap)
        case .cleanup, .applications: Text(ForkCareHubStrings.current.purpose(module))
        }
    }

    private struct SmartScanLine: View {
        @ObservedObject var scan: ForkSmartScanModel
        var body: some View {
            let text = ForkCareHubStrings.current
            switch scan.phase {
            case .scanning: Text(text.scanning)
            case .results: Text(text.resultsReady)
            case .running: Text(text.running)
            case .done: Text(text.done)
            case .welcome: Text(text.purpose(.smartScan))
            }
        }
    }

    private struct ProtectionLine: View {
        @ObservedObject var antivirus: ForkAntivirusModel
        var body: some View {
            let scanning = { if case .scanning = antivirus.activity { return true } else { return false } }()
            let line = ForkCareHubLogic.protectionState(threats: antivirus.threats.count, scanning: scanning,
                                                        lastScan: antivirus.lastScan?.date, now: .now,
                                                        french: L10n.shared.language == .fr)
            Text(line ?? ForkCareHubStrings.current.purpose(.protection))
        }
    }

    private struct PerformanceLine: View {
        @ObservedObject var maintenance: ForkMaintenanceModel
        var body: some View {
            let line = ForkCareHubLogic.performanceState(running: maintenance.running,
                                                         lastRun: maintenance.lastRuns.values.max(), now: .now,
                                                         french: L10n.shared.language == .fr)
            Text(line ?? ForkCareHubStrings.current.purpose(.performance))
        }
    }

    private struct DiskMapLine: View {
        @ObservedObject var map: ForkDiskMapModel
        var body: some View {
            let line = ForkCareHubLogic.diskMapState(scanning: map.scanning, files: map.scannedFiles,
                                                     hasMap: map.root != nil, french: L10n.shared.language == .fr)
            Text(line ?? ForkCareHubStrings.current.purpose(.diskMap))
        }
    }
}

/// The system's sidebar material, translucent over the desktop.
private struct ForkCareHubSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
