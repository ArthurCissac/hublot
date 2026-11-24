// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Direct ways in from the menu bar panel (see `ForkMenuShortcutsLogic`):
/// the heaviest apps with a Quit button in the System section, a quit
/// button on hover over every process line, and the cleaning tools in the
/// Disks section. Each is placed by one line in an upstream panel file.

/// Quitting from the panel. An app quits as its own menu would, asking to
/// save if it needs to; Option forces, through upstream's confirmation.
/// A process that is not an app can only be forced, confirmed the same way.
enum ForkProcessQuit {
    typealias Logic = ForkMenuShortcutsLogic

    static func offer(pid: pid_t, name: String, row: ProcessUsage?) -> Logic.QuitOffer {
        let app = NSRunningApplication(processIdentifier: pid)
        let regular = app.map { $0.activationPolicy == .regular && !$0.isTerminated } ?? false
        return Logic.offer(isRegularApp: regular, bundleID: app?.bundleIdentifier,
                           isProtected: KillProcessSupport.isProtected(pid: pid, name: name),
                           canForce: row.map { ProcessUsageService.shared.canForceQuit($0) } ?? false)
    }

    static func offer(for row: ProcessUsage) -> Logic.QuitOffer {
        offer(pid: row.pid, name: row.name, row: row)
    }

    static func perform(_ row: ProcessUsage, inNotch: Bool) {
        let optionKey = NSEvent.modifierFlags.contains(.option)
        switch Logic.action(for: offer(for: row), optionKey: optionKey) {
        case .quit: NSRunningApplication(processIdentifier: row.pid)?.terminate()
        case .forceQuit: ProcessUsageService.shared.confirmForceQuit(row, inNotch: inNotch)
        case .none: break
        }
    }
}

/// A quit button over a process line while the pointer is on it, in place
/// of its value. Applied outside the line's own button, so the two never nest.
struct ForkProcessQuitOnHover: ViewModifier {
    let row: ProcessUsage
    @Environment(\.notchPresentation) private var inNotch
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if hovered, ForkProcessQuit.offer(for: row) != .none {
                    ForkProcessQuitButton(row: row, inNotch: inNotch)
                }
            }
            .onHover { hovered = $0 }
    }
}

private struct ForkProcessQuitButton: View {
    let row: ProcessUsage
    let inNotch: Bool

    var body: some View {
        let text = ForkMenuShortcutsStrings.current
        let forceOnly = ForkProcessQuit.offer(for: row) == .forceOnly
        Button {
            ForkProcessQuit.perform(row, inNotch: inNotch)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(forceOnly ? Color.red : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.background, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forceOnly ? text.forceQuit : text.quit)
        .screenshotSafeHelp(forceOnly ? text.forceQuit : text.quitHelp)
    }
}

/// The System section's "Heaviest apps": the apps taking the most memory,
/// their share of the processor beside it, each with a Quit button. Read
/// every few seconds while the panel shows it, off the main thread, through
/// upstream's own process readings.
struct ForkHeavyAppsBlock: View {
    typealias Logic = ForkMenuShortcutsLogic
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var rows: [ProcessUsage] = []
    @State private var cpu: [pid_t: Double] = [:]
    @State private var loaded = false
    @State private var lastRefresh = Date.distantPast

    var body: some View {
        let text = ForkMenuShortcutsStrings.current
        VStack(alignment: .leading, spacing: 5) {
            Text(text.heavyAppsTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if rows.isEmpty {
                Text(loaded ? text.nothing : text.measuring)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 16)
            } else {
                ForEach(rows) { row in line(row, text) }
            }
        }
        .onAppear { refresh() }
        .onReceive(monitor.$snapshot) { _ in
            guard Date().timeIntervalSince(lastRefresh) >= Logic.refreshInterval else { return }
            refresh()
        }
    }

    private func line(_ row: ProcessUsage, _ text: ForkMenuShortcutsStrings) -> some View {
        HStack(spacing: 7) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
            Text(row.name)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let usage = cpu[row.pid] {
                Text(String(format: "%.0f %%", locale: MetricFormat.locale, usage))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(ByteCountFormatter.string(fromByteCount: Int64(row.value), countStyle: .memory))
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(text.quit) {
                ForkProcessQuit.perform(row, inNotch: inNotch)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .screenshotSafeHelp(text.quitHelp)
        }
        .padding(.leading, 16)
    }

    private func refresh() {
        lastRefresh = Date()
        DispatchQueue.global(qos: .utility).async {
            let memory = ProcessUsageService.shared.topMemory(limit: 25)
            let processor = ProcessUsageService.shared.topCPU(limit: 40, sampleInterval: Logic.refreshInterval)
            DispatchQueue.main.async {
                let byPid = Dictionary(memory.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
                let kept = Logic.heavyApps(memory.map { (pid: $0.pid, memory: $0.value) }) { pid in
                    ForkProcessQuit.offer(pid: pid, name: byPid[pid]?.name ?? "", row: byPid[pid])
                }
                rows = kept.compactMap { byPid[$0] }
                cpu = Dictionary(processor.map { ($0.pid, $0.value) }, uniquingKeysWith: max)
                loaded = !memory.isEmpty || loaded
            }
        }
    }
}

/// The Disks section's tools: the one-click scan, the disk map, the antivirus
/// and maintenance, two by two. Each closes the panel and opens its window.
/// Hidden with the Cleaner page's tools bar, by the same setting.
struct ForkDiskPanelTools: View {
    @AppStorage(DefaultsKey.forkCleanerTools) private var enabled = true

    var body: some View {
        if enabled {
            let disk = ForkDiskToolsStrings.current
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tool(ForkSmartScanStrings.current.title, symbol: "wand.and.stars", prominent: true) {
                    ForkSmartScanWindow.shared.show()
                }
                tool(disk.diskMapTitle, symbol: "square.grid.3x3.square") { ForkDiskMapWindow.shared.show() }
                tool(disk.antivirusTitle, symbol: "checkmark.shield") { ForkAntivirusWindow.shared.show() }
                tool(ForkMaintenanceStrings.current.title, symbol: "wrench.and.screwdriver") {
                    ForkMaintenanceWindow.shared.show()
                }
            }
        }
    }

    @ViewBuilder
    private func tool(_ title: String, symbol: String, prominent: Bool = false,
                      show: @escaping () -> Void) -> some View {
        let label = Label(title, systemImage: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        if prominent {
            Button { open(show) } label: { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button { open(show) } label: { label }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    /// The panel goes first, so the window it opens comes to the front.
    private func open(_ show: @escaping () -> Void) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return show() }
        delegate.closePopover(completion: show)
    }
}
