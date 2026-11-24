// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Translation

/// Translation of the selected text: Control-Option-Command-T reads the
/// selection of the app in front (Accessibility only, the clipboard stays
/// untouched), or the clipboard's text when nothing readable is selected,
/// and shows its translation in a panel under the island. macOS translates
/// on the Mac itself; the languages must be downloaded once. The logic is
/// `ForkTranslateLogic`.
final class ForkTranslate {
    static let shared = ForkTranslate()
    static let defaultShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_T), modifiers: [.control, .option, .command])

    /// Out of upstream's quick-tool range, after the fork's other shortcuts (9_101 to 9_106).
    private let hotkey = QuickToolHotkey(id: 9_108)
    private var observer: NSObjectProtocol?
    /// Registering the shortcut writes a preference under upstream's lock, and that write
    /// posts a change at once: registering again from it froze the app at launch. Deferred.
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.syncWithPreferences() }
    private(set) var shortcutRegistered = true

    var enabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkTranslateEnabled) }

    func start() {
        hotkey.onPress = { [weak self] in self?.translateSelection() }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.resync.schedule() }
        resync.schedule()
    }

    private func syncWithPreferences() {
        let wanted = enabled && UserDefaults.standard.bool(forKey: DefaultsKey.forkTranslateShortcutEnabled)
        shortcutRegistered = hotkey.sync(enabled: wanted, shortcut: Self.defaultShortcut,
                                         storageKey: DefaultsKey.forkTranslateShortcut) || !wanted
        if !enabled { ForkTranslatePanel.shared.close() }
    }

    /// Reads the selection off the main thread (an app may be slow to answer),
    /// then opens the panel with it, or with the clipboard's text.
    func translateSelection() {
        guard enabled else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app?.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let selection = pid.flatMap { SelectedTextReader.read(processID: $0)?.text }
            DispatchQueue.main.async {
                let clipboard = NSPasteboard.general.string(forType: .string)
                ForkTranslatePanel.shared.show(request: ForkTranslateLogic.request(selection: selection, clipboard: clipboard))
            }
        }
    }
}

// MARK: - The panel

/// Drops under the island in the middle of the screen the pointer is on,
/// like Todoist's panel; Esc, Close or a click elsewhere closes it.
final class ForkTranslatePanel {
    static let shared = ForkTranslatePanel()
    private var panel: NSPanel?
    private var monitors: [Any] = []

    func show(request: ForkTranslateLogic.Request?) {
        close()
        let height = request.map { ForkTranslateLogic.panelHeight(original: $0.text, translated: nil) } ?? 150
        let size = CGSize(width: ForkTranslateLogic.panelWidth, height: height)
        let root = ForkTranslatePanelView(request: request,
                                          close: { [weak self] in self?.close() },
                                          replace: { [weak self] text in self?.replace(with: text) },
                                          resize: { [weak self] height in self?.resize(to: height) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let panel = ForkTodoistKeyPanel(contentRect: CGRect(origin: .zero, size: size),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 8,
                              width: size.width, height: size.height), display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        install(for: panel)
    }

    /// The top stays under the menu bar; the panel grows or shrinks downwards.
    private func resize(to height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// The panel never took the focus from the app, so the paste lands in the
    /// selection it came from; the clipboard is put back afterwards.
    private func replace(with text: String) {
        close()
        TransientPaste.shared.paste(text)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
    }

    private func install(for panel: NSPanel) {
        if let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.window === panel, Int(event.keyCode) == kVK_Escape else { return event }
            self?.close()
            return nil
        }) { monitors.append(key) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
    }
}

// MARK: - The panel's content

struct ForkTranslatePanelView: View {
    let request: ForkTranslateLogic.Request?
    let close: () -> Void
    let replace: (String) -> Void
    let resize: (CGFloat) -> Void

    var body: some View {
        let text = ForkTranslateStrings.current
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                Text(text.title).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 4)
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(text.close)
            }
            if let request {
                if #available(macOS 15.0, *) {
                    ForkTranslateResultView(request: request, close: close, replace: replace, resize: resize)
                } else {
                    message(text.needsNewerMacOS)
                }
            } else {
                message(text.nothingToTranslate)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func message(_ string: String) -> some View {
        Text(string).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

@available(macOS 15.0, *)
private struct ForkTranslateResultView: View {
    let request: ForkTranslateLogic.Request
    let close: () -> Void
    let replace: (String) -> Void
    let resize: (CGFloat) -> Void

    private enum Phase: Equatable {
        case checking, needsDownload, unsupported, translating, done(String), failed
    }

    @State private var phase = Phase.checking
    @State private var configuration: TranslationSession.Configuration?
    @State private var copied = false

    private var source: String? { ForkTranslateLogic.detectedLanguage(request.text) }
    private var target: String { ForkTranslateLogic.target(forDetected: source) }

    var body: some View {
        let text = ForkTranslateStrings.current
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(request.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if request.truncated {
                        Text(text.truncated(ForkTranslateLogic.maxCharacters)).font(.caption).foregroundStyle(.tertiary)
                    }
                    Divider()
                    resultView(text)
                }
            }
            buttons(text)
        }
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(request.text)
                phase = .done(response.targetText)
                resize(ForkTranslateLogic.panelHeight(original: request.text, translated: response.targetText))
            } catch {
                phase = .failed
            }
        }
        .task { await check() }
    }

    @ViewBuilder
    private func resultView(_ text: ForkTranslateStrings) -> some View {
        switch phase {
        case .checking, .translating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text.translating).font(.callout).foregroundStyle(.secondary)
            }
        case let .done(translation):
            Text(translation)
                .font(.system(size: 15))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .needsDownload:
            VStack(alignment: .leading, spacing: 8) {
                Text(text.needsDownload(languageName(source), languageName(target)))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(text.download) {
                        // The download sheet belongs to the app: it comes forward for it.
                        NSApp.activate(ignoringOtherApps: true)
                        phase = .translating
                        configuration = makeConfiguration()
                    }
                    Button(text.openSettings) { openLanguageSettings() }
                }
            }
        case .unsupported:
            Text(text.unsupported(languageName(source), languageName(target)))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text(text.failed).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buttons(_ text: ForkTranslateStrings) -> some View {
        HStack(spacing: 8) {
            if case let .done(translation) = phase {
                Button(copied ? text.copied : text.copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translation, forType: .string)
                    copied = true
                }
                if ForkTranslateLogic.canReplace(request) {
                    Button(text.replace) { replace(translation) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            Spacer()
            Button(text.close) { close() }.keyboardShortcut(.cancelAction)
        }
    }

    private func makeConfiguration() -> TranslationSession.Configuration {
        TranslationSession.Configuration(source: source.map { Locale.Language(identifier: $0) },
                                         target: Locale.Language(identifier: target))
    }

    /// Translates at once when the languages are on the Mac; otherwise says
    /// what to download first, rather than a system sheet out of nowhere.
    private func check() async {
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status
        if let source {
            status = await availability.status(from: Locale.Language(identifier: source),
                                               to: Locale.Language(identifier: target))
        } else {
            status = (try? await availability.status(for: request.text, to: Locale.Language(identifier: target))) ?? .supported
        }
        switch status {
        case .installed:
            phase = .translating
            configuration = makeConfiguration()
        case .supported:
            phase = .needsDownload
        default:
            phase = .unsupported
        }
    }

    private func languageName(_ code: String?) -> String {
        guard let code else { return "?" }
        let locale = Locale(identifier: L10n.shared.language == .fr ? "fr" : "en")
        return locale.localizedString(forLanguageCode: code) ?? code
    }

    private func openLanguageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        close()
    }
}

// MARK: - Settings

/// The translation's switches, next to the island's other pages.
struct ForkTranslateSettingsSection: View {
    @AppStorage(DefaultsKey.forkTranslateEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkTranslateShortcutEnabled) private var shortcut = true

    var body: some View {
        let text = ForkTranslateStrings.current
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.headline)
            ForkOptionRow(symbol: "character.bubble", title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                ForkOptionRow(symbol: "command", title: text.shortcut,
                              caption: ForkTranslate.shared.shortcutRegistered ? text.shortcutCaption : text.shortcutTaken) {
                    Toggle(text.shortcut, isOn: $shortcut).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}
