// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The Printer page's views (see `ForkBambu`): the island's page with the
/// camera and the print state, its button among the island's controls, and
/// the settings shown on its card.

private typealias BambuLogic = ForkBambuLogic

private let forkBambuGreen = Color(red: 0.36, green: 0.84, blue: 0.5)

// MARK: - The island's page

/// The island's Printer page: the printer, read only while it shows.
struct ForkBambuIslandPage: View {
    let size: CGSize

    var body: some View {
        ForkBambuLive(width: size.width - 12)
            .padding(.horizontal, 6)
            .padding(.vertical, BambuLogic.pagePadding / 2)
            .frame(width: size.width, height: size.height, alignment: .top)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .onAppear { ForkBambu.shared.pageOpened() }
            .onDisappear { ForkBambu.shared.pageClosed() }
    }
}

/// The camera in 16:9, then the print: its name and state, its progress and
/// time left, its layer and temperatures. On the Printer page and in Home;
/// whoever shows it opens and closes the printer's connections.
struct ForkBambuLive: View {
    let width: CGFloat
    @ObservedObject private var bambu = ForkBambu.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = ForkBambuStrings.current
        Group {
            switch bambu.link {
            case .off, .needsSetup:
                message(text.needsSetup, button: text.openSettings) { NotchService.shared.openSettings(showing: .printer) }
            case .refused:
                message(text.refused, button: text.openSettings) { NotchService.shared.openSettings(showing: .printer) }
            case .certificateChanged:
                message(text.certificateChanged, button: text.openSettings) { NotchService.shared.openSettings(showing: .printer) }
            default:
                VStack(spacing: 8) {
                    camera(text)
                    state(text)
                }
            }
        }
    }

    private func camera(_ text: ForkBambuStrings) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            shape.fill(Color.white.opacity(0.06))
            if let picture = bambu.picture {
                Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit).clipShape(shape)
            } else if bambu.cameraFailed {
                Label(text.cameraUnavailable, systemImage: "video.slash")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(330, (width * 9 / 16).rounded()))
        .overlay(alignment: .topTrailing) {
            if bambu.picture != nil, bambu.cameraFailed {
                Image(systemName: "video.slash.fill").font(.system(size: 10)).padding(6)
                    .foregroundStyle(.orange).help(text.cameraUnavailable)
            }
        }
        .accessibilityLabel(bambu.name ?? text.title)
    }

    private func state(_ text: ForkBambuStrings) -> some View {
        let status = bambu.status
        let french = l10n.language == .fr
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(status.job ?? bambu.name ?? text.noJob)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(linkWords(text, french: french))
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(chipColor.opacity(0.22)))
                    .foregroundStyle(chipColor)
            }
            if let percent = status.percent, status.printing || status.state == "FINISH" {
                HStack(spacing: 8) {
                    GeometryReader { proxy in
                        Capsule().fill(Color.white.opacity(0.1))
                            .overlay(alignment: .leading) {
                                Capsule().fill(forkBambuGreen).frame(width: max(4, proxy.size.width * CGFloat(percent) / 100))
                            }
                    }
                    .frame(height: 6)
                    Text("\(percent) %").font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                    if let minutes = status.remainingMinutes, status.printing {
                        Text(text.left(BambuLogic.remaining(minutes)))
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
            Text(details(status, text: text))
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        }
        .padding(.horizontal, 4)
        .frame(height: BambuLogic.statusHeight, alignment: .top)
    }

    private var chipColor: Color {
        switch bambu.status.state ?? "" {
        case "RUNNING", "PREPARE": return forkBambuGreen
        case "PAUSE": return .orange
        case "FAILED": return .red
        default: return Color.white.opacity(0.8)
        }
    }

    private func linkWords(_ text: ForkBambuStrings, french: Bool) -> String {
        switch bambu.link {
        case .connecting where bambu.status.state == nil: return text.connecting
        case .unreachable: return text.unreachable
        default: return BambuLogic.stateText(bambu.status, french: french)
        }
    }

    private func details(_ status: BambuLogic.Status, text: ForkBambuStrings) -> String {
        var parts: [String] = []
        if let layer = status.layer, let total = status.totalLayers, total > 0, status.printing {
            parts.append("\(text.layer) \(layer)/\(total)")
        }
        if let nozzle = BambuLogic.temperature(status.nozzle, target: status.nozzleTarget) { parts.append("\(text.nozzle) \(nozzle)") }
        if let bed = BambuLogic.temperature(status.bed, target: status.bedTarget) { parts.append("\(text.bed) \(bed)") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private func message(_ words: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: BambuLogic.pageSymbol).font(.system(size: 22)).foregroundStyle(.white.opacity(0.45))
            Text(words)
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Printer button among the island's controls: opens the page.
struct ForkBambuIslandTile: View {
    let service: NotchService

    var body: some View {
        NotchActionTile(symbol: BambuLogic.pageSymbol, title: ForkBambuStrings.current.title) {
            service.open(.printer)
        }
    }
}

// MARK: - Settings

/// The Printer page's settings, on its card in the island's Content tab
/// (even while it is off, so its switch is there).
struct ForkBambuSettingsSection: View {
    private enum Field { case host, serial }

    @AppStorage(DefaultsKey.forkBambuEnabled) private var enabled = false
    @AppStorage(DefaultsKey.forkBambuHost) private var host = ""
    @AppStorage(DefaultsKey.forkBambuSerial) private var serial = ""
    @ObservedObject private var bambu = ForkBambu.shared
    @State private var hostDraft = ""
    @State private var serialDraft = ""
    @State private var code = ""
    @FocusState private var focus: Field?

    private let fieldInset: CGFloat = 38

    var body: some View {
        let text = ForkBambuStrings.current
        VStack(alignment: .leading, spacing: 10) {
            ForkOptionRow(symbol: BambuLogic.pageSymbol, title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                searchRow(text)
                field(.host, title: text.address, caption: hostCaption(text), placeholder: "192.168.1.40", text: text)
                field(.serial, title: text.serial, caption: text.serialCaption, placeholder: "03919A…", text: text)
                codeRow(text)
                ForkOptionRow(symbol: statusSymbol, title: text.connection, caption: statusText(text)) {
                    HStack(spacing: 6) {
                        if bambu.link == .certificateChanged {
                            Button(text.forgetCertificate) { bambu.forgetCertificates() }.fixedSize()
                        }
                        Button(text.test) {
                            saveDrafts()
                            bambu.reconnect()
                        }
                        .fixedSize()
                        .disabled(!bambu.hasCode || BambuLogic.host(hostDraft) == nil && bambu.host == nil)
                    }
                }
            }
        }
        .onAppear {
            hostDraft = host
            serialDraft = serial
        }
        .onChange(of: host) { _, now in if focus != .host { hostDraft = now } }
        .onChange(of: serial) { _, now in if focus != .serial { serialDraft = now } }
        .onChange(of: focus) { previous, _ in if let previous { save(previous) } }
        .onDisappear { saveDrafts() }
    }

    private func searchRow(_ text: ForkBambuStrings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForkOptionRow(symbol: "dot.radiowaves.left.and.right", title: text.search,
                          caption: bambu.searching ? text.searching : bambu.searched && bambu.found.isEmpty ? text.noneFound : nil) {
                HStack(spacing: 6) {
                    if bambu.searching { ProgressView().controlSize(.small) }
                    Button(text.search) { bambu.search() }.fixedSize().disabled(bambu.searching)
                }
            }
            ForEach(bambu.found) { printer in
                HStack(spacing: 8) {
                    Image(systemName: BambuLogic.pageSymbol).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text([printer.name, printer.model].compactMap { $0 }.joined(separator: " · ")).font(.callout)
                        Text("\(printer.host) · \(printer.serial)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Button(text.choose) {
                        bambu.choose(printer)
                        hostDraft = printer.host
                        serialDraft = printer.serial
                    }
                    .fixedSize()
                    .disabled(printer.host == host && printer.serial == serial)
                }
                .padding(.leading, fieldInset)
            }
        }
    }

    private func field(_ field: Field, title: String, caption: String, placeholder: String, text: ForkBambuStrings) -> some View {
        let draft = field == .host ? $hostDraft : $serialDraft
        let saved = field == .host ? host : serial
        return VStack(alignment: .leading, spacing: 6) {
            ForkOptionRow(symbol: field == .host ? "network" : "number", title: title, caption: caption) { EmptyView() }
            HStack(spacing: 6) {
                TextField(placeholder, text: draft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: field)
                    .onSubmit { save(field) }
                Button(text.save) { save(field) }
                    .fixedSize()
                    .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespaces) == saved || !valid(field, draft.wrappedValue))
            }
            .padding(.leading, fieldInset)
        }
    }

    private func valid(_ field: Field, _ value: String) -> Bool {
        let typed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return field == .host ? BambuLogic.host(typed) != nil : typed.isEmpty || BambuLogic.isSerial(typed)
    }

    private func save(_ field: Field) {
        if field == .host {
            if let valid = BambuLogic.host(hostDraft) {
                host = valid
                hostDraft = valid
            }
        } else {
            let typed = serialDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if typed.isEmpty || BambuLogic.isSerial(typed) { serial = typed.uppercased() }
        }
    }

    private func saveDrafts() {
        save(.host)
        save(.serial)
    }

    private func hostCaption(_ text: ForkBambuStrings) -> String {
        let typed = hostDraft.trimmingCharacters(in: .whitespaces)
        return !typed.isEmpty && typed != host && BambuLogic.host(typed) == nil ? text.invalidAddress : text.addressCaption
    }

    @ViewBuilder
    private func codeRow(_ text: ForkBambuStrings) -> some View {
        if bambu.hasCode {
            ForkOptionRow(symbol: "key.fill", title: text.code, caption: text.codeCaption) {
                Button(text.forgetCode) { bambu.forgetCode() }.fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForkOptionRow(symbol: "key", title: text.code, caption: text.codeCaption) { EmptyView() }
                HStack(spacing: 6) {
                    SecureField(text.code, text: $code).labelsHidden().textFieldStyle(.roundedBorder)
                        .onSubmit { if bambu.setCode(code) { code = "" } }
                    Button(text.save) { if bambu.setCode(code) { code = "" } }
                        .fixedSize()
                        .disabled(BambuLogic.cleanCode(code) == nil)
                }
                .padding(.leading, fieldInset)
            }
        }
    }

    private var statusSymbol: String {
        switch bambu.link {
        case .live: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .refused, .unreachable, .certificateChanged: return "exclamationmark.triangle.fill"
        case .idle: return "circle"
        case .off, .needsSetup: return "circle.dashed"
        }
    }

    private func statusText(_ text: ForkBambuStrings) -> String {
        switch bambu.link {
        case .off: return text.off
        case .needsSetup: return text.needsSetup
        case .idle: return text.idle
        case .connecting: return text.connecting
        case .live: return text.live
        case .refused: return text.refused
        case .unreachable: return text.unreachable
        case .certificateChanged: return text.certificateChanged
        }
    }
}
