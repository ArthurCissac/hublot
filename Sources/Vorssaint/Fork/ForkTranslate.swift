// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Translation

/// Translation of the selected text: Control-Option-Command-T, the island's
/// Translate button or the menu's tile read the selection of the app in
/// front (Accessibility only, the clipboard stays untouched), or the
/// clipboard's text when nothing readable is selected, and show its
/// translation in the island's Translation page, into the language chosen
/// there. A text can also be typed in the page. With the island off, a panel
/// under the menu bar shows the same thing. macOS translates on the Mac
/// itself; the languages must be downloaded once. The logic is
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
    /// then shows its translation, or the clipboard's. From the menu's tile,
    /// the app the menu took the focus from comes back a moment after it
    /// closes: its selection is waited for rather than skipped.
    func translateSelection(attempt: Int = 0) {
        guard enabled else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let ours = app?.bundleIdentifier == Bundle.main.bundleIdentifier
        if ours, attempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.translateSelection(attempt: attempt + 1) }
            return
        }
        let pid = ours ? nil : app?.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let selection = pid.flatMap { SelectedTextReader.read(processID: $0)?.text }
            DispatchQueue.main.async {
                let clipboard = NSPasteboard.general.string(forType: .string)
                ForkTranslateModel.shared.show(ForkTranslateLogic.request(selection: selection, clipboard: clipboard))
                Self.present()
            }
        }
    }

    /// The island's Translation page when the island shows it, the panel otherwise.
    static func present() {
        if ForkTranslateLogic.showsInIsland(islandEnabled: NotchSupport.isEnabled(),
                                            pageShown: NotchSupport.modules().contains(.translate)) {
            ForkTranslatePanel.shared.close()
            NotchService.shared.open(.translate)
        } else {
            ForkTranslatePanel.shared.show()
        }
    }

    /// Neither the island nor the panel took the focus from the app, so once
    /// they are out of the way the paste lands in the selection it came from;
    /// the clipboard is put back afterwards.
    static func replace(with text: String) {
        if ForkTranslatePanel.shared.isShowing {
            ForkTranslatePanel.shared.close()
            TransientPaste.shared.paste(text)
        } else {
            NotchService.shared.perform { _ = TransientPaste.shared.paste(text) }
        }
    }

    static func dismiss() {
        if ForkTranslatePanel.shared.isShowing { ForkTranslatePanel.shared.close() } else { NotchService.shared.collapse() }
    }
}

// MARK: - The translation shown

/// What the page or the panel shows: the text, where it goes, and how far
/// macOS got. One for both, so the island and the panel never disagree.
final class ForkTranslateModel: ObservableObject {
    static let shared = ForkTranslateModel()
    typealias Logic = ForkTranslateLogic

    enum Phase: Equatable {
        case idle, checking, needsDownload, unsupported, translating, done(String), failed, needsNewerMacOS
    }

    @Published private(set) var request: Logic.Request?
    @Published private(set) var detected: String?
    @Published private(set) var preferred: String?
    /// Changes with each new text, so the translation starts over.
    @Published private(set) var revision = 0
    /// Asked for once the person agreed to download the languages.
    @Published private(set) var downloads = 0
    @Published var phase = Phase.idle
    @Published var draft = ""

    private init() {
        preferred = Logic.preferred(stored: UserDefaults.standard.string(forKey: DefaultsKey.forkTranslateTarget))
    }

    var target: String { Logic.target(forDetected: detected, preferred: preferred) }

    /// Starts over whenever the text or its language changes.
    var runKey: String { "\(revision)|\(target)" }

    func show(_ request: Logic.Request?) {
        self.request = request
        detected = request.map { Logic.detectedLanguage($0.text) } ?? nil
        restart()
    }

    func translateDraft() {
        guard let request = Logic.request(typed: draft) else { return }
        draft = ""
        show(request)
    }

    func choose(_ language: String?) {
        let stored = language.flatMap { Logic.preferred(stored: $0) }
        guard stored != preferred else { return }
        preferred = stored
        UserDefaults.standard.set(stored ?? Logic.automatic, forKey: DefaultsKey.forkTranslateTarget)
        if request != nil { restart() }
    }

    func download() {
        phase = .translating
        downloads += 1
    }

    private func restart() {
        revision += 1
        if request == nil { phase = .idle; return }
        if #available(macOS 15.0, *) { phase = .checking } else { phase = .needsNewerMacOS }
    }

    func languageName(_ code: String?) -> String {
        guard let code else { return "?" }
        let locale = Locale(identifier: L10n.shared.language == .fr ? "fr" : "en")
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Runs the translation for the model, out of sight: checks the languages
/// are on the Mac first, rather than a system sheet out of nowhere.
@available(macOS 15.0, *)
private struct ForkTranslateRunner: View {
    @ObservedObject var model: ForkTranslateModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                guard let request = model.request else { return }
                do {
                    let response = try await session.translate(request.text)
                    model.phase = .done(response.targetText)
                } catch {
                    model.phase = .failed
                }
            }
            .task { await check() }
            .onChange(of: model.downloads) { _, _ in
                // The download sheet belongs to the app: it comes forward for it.
                NSApp.activate(ignoringOtherApps: true)
                configuration = makeConfiguration()
            }
    }

    private func makeConfiguration() -> TranslationSession.Configuration {
        TranslationSession.Configuration(source: model.detected.map { Locale.Language(identifier: $0) },
                                         target: Locale.Language(identifier: model.target))
    }

    private func check() async {
        guard let request = model.request else { return }
        let availability = LanguageAvailability()
        let target = Locale.Language(identifier: model.target)
        let status: LanguageAvailability.Status
        if let source = model.detected {
            status = await availability.status(from: Locale.Language(identifier: source), to: target)
        } else {
            status = (try? await availability.status(for: request.text, to: target)) ?? .supported
        }
        switch status {
        case .installed:
            model.phase = .translating
            configuration = makeConfiguration()
        case .supported:
            model.phase = .needsDownload
        default:
            model.phase = .unsupported
        }
    }
}

// MARK: - The island's page

struct ForkTranslateIslandPage: View {
    let size: CGSize

    var body: some View {
        ForkTranslateBoard(model: .shared)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// The island's Translate button: translates the selection of the app in front.
struct ForkTranslateIslandTile: View {
    let service: NotchService

    var body: some View {
        NotchActionTile(symbol: ForkTranslateLogic.pageSymbol, title: ForkTranslateStrings.current.translate) {
            ForkTranslate.shared.translateSelection()
        }
    }
}

/// The page's content, also the panel's: the language it goes to, the text,
/// its translation, then a field to type another one.
struct ForkTranslateBoard: View {
    @ObservedObject var model: ForkTranslateModel
    @ObservedObject private var l10n = L10n.shared
    @State private var copied = false

    var body: some View {
        let text = ForkTranslateStrings.current
        VStack(alignment: .leading, spacing: 8) {
            header(text)
            ScrollView(.vertical, showsIndicators: false) {
                content(text).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            field(text)
        }
        .foregroundStyle(.white)
        .background {
            if #available(macOS 15.0, *), model.request != nil {
                ForkTranslateRunner(model: model).id(model.runKey)
            }
        }
        .onChange(of: model.runKey) { _, _ in copied = false }
    }

    private func header(_ text: ForkTranslateStrings) -> some View {
        HStack(spacing: 8) {
            if model.request != nil {
                Text(model.detected.map { model.languageName($0) } ?? text.unknownLanguage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            }
            languageMenu(text)
            Spacer(minLength: 4)
            if case let .done(translation) = model.phase {
                pill(copied ? text.copied : text.copy, symbol: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translation, forType: .string)
                    copied = true
                }
                if let request = model.request, ForkTranslateLogic.canReplace(request) {
                    pill(text.replace, symbol: "arrow.left.arrow.right", prominent: true) {
                        ForkTranslate.replace(with: translation)
                    }
                }
            }
        }
    }

    /// The language the text goes to; Automatic keeps French into English and the rest into French.
    private func languageMenu(_ text: ForkTranslateStrings) -> some View {
        Menu {
            Button {
                model.choose(nil)
            } label: {
                if model.preferred == nil { Label(text.automatic, systemImage: "checkmark") } else { Text(text.automatic) }
            }
            Divider()
            ForEach(ForkTranslateLogic.languages, id: \.self) { code in
                Button {
                    model.choose(code)
                } label: {
                    if model.preferred == code {
                        Label(model.languageName(code), systemImage: "checkmark")
                    } else {
                        Text(model.languageName(code))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(menuTitle(text)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(text.languageHelp)
        .accessibilityLabel(text.languageHelp)
    }

    private func menuTitle(_ text: ForkTranslateStrings) -> String {
        if model.request != nil { return model.languageName(model.target) }
        return model.preferred.map { model.languageName($0) } ?? text.automatic
    }

    @ViewBuilder
    private func content(_ text: ForkTranslateStrings) -> some View {
        if let request = model.request {
            VStack(alignment: .leading, spacing: 8) {
                Text(request.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
                if request.truncated {
                    Text(text.truncated(ForkTranslateLogic.maxCharacters)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                result(text)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        } else {
            message(text.empty)
        }
    }

    @ViewBuilder
    private func result(_ text: ForkTranslateStrings) -> some View {
        switch model.phase {
        case .idle, .checking, .translating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text.translating).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
            }
        case let .done(translation):
            Text(translation)
                .font(.system(size: 15))
                .textSelection(.enabled)
        case .needsDownload:
            VStack(alignment: .leading, spacing: 8) {
                message(text.needsDownload(model.languageName(model.detected), model.languageName(model.target)))
                HStack(spacing: 8) {
                    pill(text.download, symbol: "arrow.down.circle", prominent: true) { model.download() }
                    pill(text.openSettings, symbol: "globe") { openLanguageSettings() }
                }
            }
        case .unsupported:
            message(text.unsupported(model.languageName(model.detected), model.languageName(model.target)))
        case .failed:
            message(text.failed)
        case .needsNewerMacOS:
            message(text.needsNewerMacOS)
        }
    }

    private func field(_ text: ForkTranslateStrings) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "character.cursor.ibeam").foregroundStyle(.white.opacity(0.6))
            TextField("", text: $model.draft, prompt: Text(text.placeholder).foregroundStyle(.white.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { model.translateDraft() }
            if ForkTranslateLogic.request(typed: model.draft) != nil {
                Button { model.translateDraft() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .help(text.translate)
                .accessibilityLabel(text.translate)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func pill(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(prominent ? Color.accentColor : Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func message(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 12.5))
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private func openLanguageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        ForkTranslate.dismiss()
    }
}

// MARK: - The panel, with the island off

/// Drops under the menu bar in the middle of the screen the pointer is on,
/// dark like the island; Esc, the close button or a click elsewhere closes it.
final class ForkTranslatePanel {
    static let shared = ForkTranslatePanel()
    private var panel: NSPanel?
    private var monitors: [Any] = []

    var isShowing: Bool { panel != nil }

    func show() {
        close()
        let model = ForkTranslateModel.shared
        let height = model.request.map { ForkTranslateLogic.panelHeight(original: $0.text, translated: nil) } ?? 190
        let size = CGSize(width: ForkTranslateLogic.panelWidth, height: height)
        let host = NSHostingView(rootView: ForkTranslatePanelView(model: model,
                                                                  close: { [weak self] in self?.close() },
                                                                  resize: { [weak self] height in self?.resize(to: height) }))
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
        panel.appearance = NSAppearance(named: .darkAqua)
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
        guard let panel, abs(panel.frame.height - height) > 1 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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
            // The language menu opens a window of its own: a click in it stays in the panel.
            let inMenu = event.window.map { String(describing: type(of: $0)).contains("Menu") } ?? false
            if event.window !== self?.panel, !inMenu { self?.close() }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
    }
}

private struct ForkTranslatePanelView: View {
    @ObservedObject var model: ForkTranslateModel
    let close: () -> Void
    let resize: (CGFloat) -> Void

    var body: some View {
        let text = ForkTranslateStrings.current
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: ForkTranslateLogic.pageSymbol).font(.system(size: 14, weight: .semibold))
                Text(text.title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 4)
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityLabel(text.close)
            }
            .foregroundStyle(.white)
            ForkTranslateBoard(model: model)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .onChange(of: model.phase) { _, phase in
            guard let request = model.request else { return }
            if case let .done(translation) = phase {
                resize(ForkTranslateLogic.panelHeight(original: request.text, translated: translation))
            }
        }
        .onChange(of: model.revision) { _, _ in
            resize(model.request.map { ForkTranslateLogic.panelHeight(original: $0.text, translated: nil) } ?? 190)
        }
    }
}

// MARK: - Settings

/// The translation's switches and language, next to the island's other pages.
struct ForkTranslateSettingsSection: View {
    @AppStorage(DefaultsKey.forkTranslateEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkTranslateShortcutEnabled) private var shortcut = true
    @ObservedObject private var model = ForkTranslateModel.shared

    var body: some View {
        let text = ForkTranslateStrings.current
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.headline)
            ForkOptionRow(symbol: ForkTranslateLogic.pageSymbol, title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                ForkOptionRow(symbol: "globe", title: text.targetTitle, caption: text.targetCaption) {
                    Picker(text.targetTitle, selection: Binding(get: { model.preferred ?? ForkTranslateLogic.automatic },
                                                                set: { model.choose($0) })) {
                        Text(text.automatic).tag(ForkTranslateLogic.automatic)
                        Divider()
                        ForEach(ForkTranslateLogic.languages, id: \.self) { code in
                            Text(model.languageName(code)).tag(code)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ForkOptionRow(symbol: "command", title: text.shortcut,
                              caption: ForkTranslate.shared.shortcutRegistered ? text.shortcutCaption : text.shortcutTaken) {
                    Toggle(text.shortcut, isOn: $shortcut).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}
