// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A QR code that opens a local dev server on a phone, shown under the
/// pointer from the port manager: the server's address on this Mac's
/// network, a copy and an open action. Esc or a click elsewhere closes it.
/// Nothing is sent anywhere: the code is drawn on the Mac.
final class ForkLocalQRController {
    static let shared = ForkLocalQRController()

    private var panel: ForkLocalQRPanel?
    private var keyMonitor: Any?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private init() {}

    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.forkLocalQREnabled)
    }

    func show(_ entry: PortManagerEntry) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(entry) }
            return
        }
        close()
        let destination = ForkLocalQRLogic.destination(port: entry.port, endpoint: entry.address,
                                                       readings: NetworkAddressService.readLocalAddresses())
        let content = ForkLocalQRView(destination: destination, port: entry.port, process: entry.processName,
                                      copy: { [weak self] in self?.copy($0) },
                                      open: { [weak self] in self?.open($0) })
        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = ForkLocalQRPanel(contentRect: CGRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Above the island and the menu panel it can be opened from.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let visible = NSScreen.pointerVisibleFrame
        let pointer = NSEvent.mouseLocation
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height - 18)
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        self.panel = panel

        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        for monitor in [keyMonitor, localMonitor, globalMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        localMonitor = nil
        globalMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(url.absoluteString, forType: .string)
        close()
        QuickToolHUD.show(icon: "qrcode", message: ForkLocalQRStrings.current.copied)
    }

    private func open(_ url: URL) {
        close()
        if !NSWorkspace.shared.open(url) { NSSound.beep() }
    }

    private func installMonitors(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === panel, Int(event.keyCode) == kVK_Escape else { return event }
            self?.close()
            return nil
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }
}

/// Takes key focus for its buttons without bringing the app forward.
final class ForkLocalQRPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
}

struct ForkLocalQRView: View {
    let destination: ForkLocalQRLogic.Destination
    let port: Int
    let process: String
    let copy: (URL) -> Void
    let open: (URL) -> Void
    private let strings = ForkLocalQRStrings.current

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "iphone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.title).font(.headline)
                Spacer(minLength: 8)
                Text(verbatim: ":\(port) · \(process)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            switch destination {
            case let .url(url, connection):
                code(url, connection: connection)
            case .localOnly:
                message(symbol: "lock.laptopcomputer", title: strings.localOnlyTitle, detail: strings.localOnlyDetail,
                        commands: "next dev -H 0.0.0.0\nvite --host")
            case .noNetwork:
                message(symbol: "wifi.slash", title: strings.noNetworkTitle, detail: strings.noNetworkDetail, commands: nil)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    private func code(_ url: URL, connection: String?) -> some View {
        if let image = ForkLocalQRLogic.image(for: url.absoluteString, moduleSize: 8) {
            Image(decorative: image, scale: 2)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(strings.title)
        }
        Text(verbatim: url.absoluteString)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .textSelection(.enabled)
        Text(strings.sameNetwork(connection))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            Button(strings.copyLink) { copy(url) }
                .keyboardShortcut("c", modifiers: .command)
            Button(strings.openHere) { open(url) }
        }
    }

    private func message(symbol: String, title: String, detail: String, commands: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let commands {
                Text(verbatim: commands)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 6)
    }
}

/// The port's context menu entry, for any TCP port.
struct ForkPortQRMenuItem: View {
    let entry: PortManagerEntry
    @AppStorage(DefaultsKey.forkLocalQREnabled) private var enabled = true

    var body: some View {
        if enabled, entry.protocolName == "TCP" {
            Button(ForkLocalQRStrings.current.menuItem) { ForkLocalQRController.shared.show(entry) }
        }
    }
}

/// The small button on the rows of usual dev server ports.
struct ForkPortQRButton: View {
    let entry: PortManagerEntry
    @AppStorage(DefaultsKey.forkLocalQREnabled) private var enabled = true

    var body: some View {
        if enabled, ForkLocalQRLogic.showsButton(port: entry.port, protocolName: entry.protocolName,
                                                 processName: entry.processName) {
            Button { ForkLocalQRController.shared.show(entry) } label: { Image(systemName: "qrcode") }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .screenshotSafeHelp(ForkLocalQRStrings.current.button)
                .accessibilityLabel(ForkLocalQRStrings.current.button)
        }
    }
}

/// Turns the button and the menu entry off, on the port manager's page.
struct ForkLocalQRToggle: View {
    @AppStorage(DefaultsKey.forkLocalQREnabled) private var enabled = true

    var body: some View {
        Toggle(isOn: $enabled) {
            Label(ForkLocalQRStrings.current.toggle, systemImage: "qrcode")
                .font(.callout)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}
