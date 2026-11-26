// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The Home page's views (see `ForkHome`): the island's page of favourites
/// by room, its button among the island's controls, a favourite's menu tile,
/// the list to choose devices from, and the settings.

private typealias HomeLogic = ForkHomeLogic

/// A cover's colour, also a single-button shutter's.

/// Each kind of device's colour when lit.
private func forkHomeTint(_ entity: ForkHomeLogic.Entity) -> Color {
    switch entity.kind {
    case .light: return Color(red: 1, green: 0.78, blue: 0.3)
    case .cover: return Color(red: 0.4, green: 0.74, blue: 1)
    case .toggle: return Color(red: 0.36, green: 0.84, blue: 0.5)
    case .scene, .script: return Color(red: 0.74, green: 0.6, blue: 1)
    case .button: return .orange
    case .sensor, .binarySensor: return Color(red: 1, green: 0.6, blue: 0.32)
    case .camera: return Color(red: 0.55, green: 0.85, blue: 0.95)
    }
}

// MARK: - The island's page

/// Favourites by room, a tile each. A click does a tile's main action
/// (toggle, open or close, run, press); a drag across a cover or a dimmable
/// light sets its level; a right click offers the rest. The island grows to
/// show every favourite (ForkHomeLogic.pageHeight), so nothing scrolls.
struct ForkHomeIslandPage: View {
    let size: CGSize
    @ObservedObject private var home = ForkHome.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.forkHomeFavorites) private var favoritesRaw = ""
    @State private var editing = false

    var body: some View {
        let text = ForkHomeStrings.current
        Group {
            if editing {
                ForkHomePicker(island: true)
            } else if home.status == .connected, home.viewingPrinter {
                ForkHomePrinterView(size: size)
            } else if home.status == .connected, home.viewing != nil {
                ForkHomeCameraView()
            } else if home.status != .connected {
                blocked(text)
            } else if HomeLogic.favorites(favoritesRaw).isEmpty {
                message(text.empty, button: text.choose) { editing = true }
            } else if home.favorites.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rooms(text)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, HomeLogic.pagePadding / 2)
        .frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .notchBand(trailing: {
            if home.status == .connected { ForkEditButton(on: $editing) }
        })
        .onDisappear {
            editing = false
            home.stopViewing()
            home.hidePrinter()
        }
    }

    private func rooms(_ text: ForkHomeStrings) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: HomeLogic.tileSpacing),
                            count: HomeLogic.columns(width: size.width - 12))
        let groups = home.groups(other: text.other)
        let printer = home.showsPrinterTile ? home.printerPlacement(groups, other: text.other) : nil
        return VStack(alignment: .leading, spacing: HomeLogic.roomSpacing) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                room(group.title, columns: columns) {
                    ForEach(group.entities) { ForkHomeTile(entity: $0) }
                    if index == groups.count - 1, printer == .inLast { ForkHomePrinterTile() }
                }
            }
            if printer == .newGroup {
                room(text.other, columns: columns) { ForkHomePrinterTile() }
            } else if printer == .alone {
                room(nil, columns: columns) { ForkHomePrinterTile() }
            }
        }
    }

    private func room<Tiles: View>(_ title: String?, columns: [GridItem], @ViewBuilder tiles: () -> Tiles) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: HomeLogic.roomTitleHeight, alignment: .topLeading)
            }
            LazyVGrid(columns: columns, spacing: HomeLogic.tileSpacing) { tiles() }
        }
    }

    @ViewBuilder
    private func blocked(_ text: ForkHomeStrings) -> some View {
        switch home.status {
        case .connecting:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text.connecting).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unreachable:
            message(text.unreachable, button: text.retry) { home.reconnect() }
        case .unauthorized:
            message(text.unauthorized, button: text.openSettings) { NotchService.shared.openSettings(showing: .home) }
        default:
            message(text.needsSetup, button: text.openSettings) { NotchService.shared.openSettings(showing: .home) }
        }
    }

    private func message(_ words: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: HomeLogic.pageSymbol).font(.system(size: 22)).foregroundStyle(.white.opacity(0.45))
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

/// One favourite in the island. A cover shows its up, stop and down
/// buttons; a gate or a garage door acts on a second click only.
struct ForkHomeTile: View {
    let entity: ForkHomeLogic.Entity
    @ObservedObject private var home = ForkHome.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var dragged: Int?
    /// The level just sent, shown until Home Assistant's answer arrives.
    @State private var sent: Int?
    @State private var hovered = false
    /// A gate's first click, waiting for the second.
    @State private var armed: ForkHomeLogic.Command?

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    /// A shutter (not a gate): one button, whose arrow says where a click sends it.
    private var isShutter: Bool { entity.kind == .cover && !entity.needsConfirmation }

    var body: some View {
        let french = l10n.language == .fr
        let on = HomeLogic.isOn(entity)
        let tint = forkHomeTint(entity)
        let level = dragged ?? sent ?? HomeLogic.level(entity)
        let failed = home.failed.contains(entity.id)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                shape.fill(Color.white.opacity(on ? 0.13 : 0.065))
                if let level {
                    Rectangle()
                        .fill(tint.opacity(0.3))
                        .frame(width: proxy.size.width * CGFloat(level) / 100)
                }
                if entity.kind == .cover, entity.needsConfirmation {
                    gateFace(on: on, tint: tint, french: french)
                } else {
                    HStack(spacing: 9) {
                        icon(on: on, tint: tint, size: 30)
                        words(french: french)
                        Spacer(minLength: 0)
                        if isShutter, entity.canStop { stopButton }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(border(failed: failed), lineWidth: 1))
            .contentShape(shape)
            .gesture(press(width: proxy.size.width))
        }
        .frame(height: HomeLogic.tileHeight)
        .onHover { hovered = $0 }
        .onChange(of: HomeLogic.level(entity)) { _, _ in sent = nil }
        .contextMenu { menu }
        .help(failed ? ForkHomeStrings.current.failed : isShutter ? title(HomeLogic.command(for: home.coverDirection(entity))) : entity.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(HomeLogic.actionable(entity) || entity.kind == .camera ? .isButton : [])
        .accessibilityAction { act(.main) }
        .accessibilityAction(named: title(.stop)) { if isShutter, entity.canStop { home.stopCover(entity) } }
        .accessibilityAdjustableAction { direction in
            guard let current = HomeLogic.level(entity) else { return }
            let next = direction == .increment ? min(100, current + 10) : max(0, current - 10)
            home.perform(.level(next), on: entity)
        }
    }

    /// A shutter's stop, beside the arrow (the tile's click goes where the arrow says).
    private var stopButton: some View {
        Button { home.stopCover(entity) } label: {
            Image(systemName: HomeLogic.commandSymbol(.stop))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(entity.available ? 0.9 : 0.4))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.13)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!entity.available || home.status != .connected)
        .help(title(.stop))
        .accessibilityLabel("\(title(.stop)) \(entity.name)")
    }

    private func border(failed: Bool) -> Color {
        if failed { return Color.red.opacity(0.8) }
        if armed != nil { return Color.orange.opacity(0.9) }
        return Color.white.opacity(hovered ? 0.14 : 0)
    }

    private func icon(on: Bool, tint: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(on ? tint : Color.white.opacity(0.12)).frame(width: size, height: size)
            if home.pending.contains(entity.id), !isShutter {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: isShutter ? HomeLogic.commandSymbol(HomeLogic.command(for: home.coverDirection(entity)))
                                            : HomeLogic.symbol(entity))
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(on ? Color.black.opacity(0.75) : Color.white.opacity(entity.available ? 0.9 : 0.4))
            }
        }
    }

    @ViewBuilder
    private func words(french: Bool) -> some View {
        let state = stateLine(french: french)
        if entity.kind == .sensor {
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                Text(state).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                Text(state).font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            }
        }
    }

    /// A gate or a garage door: its name and state, then buttons that say
    /// what they do; the one clicked once asks to confirm.
    private func gateFace(on: Bool, tint: Color, french: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                icon(on: on, tint: tint, size: 22)
                Text(entity.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(HomeLogic.stateText(entity, french: french))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            }
            HStack(spacing: 5) {
                ForEach(HomeLogic.coverButtons(entity), id: \.self) { command in
                    Button { act(command) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: armed == command ? "checkmark" : HomeLogic.commandSymbol(command))
                                .font(.system(size: 9, weight: .bold))
                            Text(armed == command ? ForkHomeStrings.current.confirm : title(command))
                                .font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .foregroundStyle(armed == command ? Color.black.opacity(0.8) : Color.white)
                        .background(Capsule().fill(armed == command ? Color.orange : Color.white.opacity(0.13)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!entity.available || home.status != .connected)
                    .help(armed == command ? HomeLogic.confirmText(command, for: entity, french: french) : title(command))
                    .accessibilityLabel("\(title(command)) \(entity.name)")
                }
            }
        }
        .padding(.horizontal, 9)
    }

    private func stateLine(french: Bool) -> String {
        if let armed { return HomeLogic.confirmText(armed, for: entity, french: french) }
        if let dragged { return french ? "\(dragged) %" : "\(dragged)%" }
        if isShutter, entity.available { return home.coverText(entity, french: french) }
        return HomeLogic.stateText(entity, french: french)
    }

    /// Up and down for covers, open and close for gates and doors.
    private func title(_ command: ForkHomeLogic.Command) -> String {
        let text = ForkHomeStrings.current
        switch command {
        case .open: return entity.needsConfirmation ? text.open : text.up
        case .close: return entity.needsConfirmation ? text.close : text.down
        case .stop: return text.stop
        case .turnOn: return text.turnOn
        case .turnOff: return text.turnOff
        case .main, .level: return entity.name
        }
    }

    /// A camera opens; a gate waits for a second click; everything else acts at once.
    private func act(_ command: ForkHomeLogic.Command) {
        if entity.kind == .camera { return home.startViewing(entity.id) }
        if isShutter { return home.pressCover(entity) }
        guard entity.needsConfirmation else { return home.perform(command, on: entity) }
        if armed == command {
            armed = nil
            home.perform(command, on: entity, confirmed: true)
        } else {
            armed = command
            DispatchQueue.main.asyncAfter(deadline: .now() + HomeLogic.confirmWindow) { if armed == command { armed = nil } }
        }
    }

    /// A click acts; a sideways drag on a cover or a dimmable light sets its level.
    private func press(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard entity.canSetLevel, entity.available,
                      dragged != nil || abs(value.translation.width) > 8 else { return }
                dragged = HomeLogic.level(at: value.location.x, width: width)
            }
            .onEnded { value in
                if let level = dragged {
                    sent = level
                    home.perform(.level(level), on: entity)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { sent = nil }
                } else if abs(value.translation.width) < 8, abs(value.translation.height) < 8 {
                    act(.main)
                }
                dragged = nil
            }
    }

    /// Chosen from the menu, a command needs no second click.
    @ViewBuilder
    private var menu: some View {
        let text = ForkHomeStrings.current
        if entity.kind == .cover {
            ForEach(HomeLogic.coverButtons(entity), id: \.self) { command in
                Button(title(command)) { home.perform(command, on: entity, confirmed: true) }
            }
            Divider()
        } else if entity.kind == .light || entity.kind == .toggle {
            Button(text.turnOn) { home.perform(.turnOn, on: entity) }
            Button(text.turnOff) { home.perform(.turnOff, on: entity) }
            Divider()
        }
        Button(text.removeFavorite) { home.toggleFavorite(entity.id) }
    }
}

/// A camera in the island, its picture following every moment; the arrow
/// goes back to the favourites.
private struct ForkHomeCameraView: View {
    @ObservedObject private var home = ForkHome.shared

    var body: some View {
        let text = ForkHomeStrings.current
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { home.stopViewing() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(text.back)
                .accessibilityLabel(text.back)
                Text(home.viewing.flatMap(home.entity)?.name ?? "")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if home.pictureFailed, home.picture != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(text.pictureFailed)
                }
            }
            .frame(height: 26)
            ZStack {
                shape.fill(Color.white.opacity(0.06))
                if let picture = home.picture {
                    Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit).clipShape(shape)
                } else if home.pictureFailed {
                    Text(text.pictureFailed).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(home.viewing.flatMap(home.entity)?.name ?? text.back)
        }
    }
}

/// The 3D printer among the favourites: its state at a glance, a click
/// shows its camera and print in place (ForkBambuLive).
struct ForkHomePrinterTile: View {
    @ObservedObject private var home = ForkHome.shared
    @ObservedObject private var bambu = ForkBambu.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var hovered = false

    var body: some View {
        let text = ForkHomeStrings.current
        let status = bambu.status
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button { home.showPrinter() } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(status.printing ? Color(red: 0.36, green: 0.84, blue: 0.5) : Color.white.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: ForkBambuLogic.pageSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(status.printing ? Color.black.opacity(0.75) : Color.white.opacity(0.9))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bambu.name ?? text.printerTile).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                    Text(subtitle(status, text: text)).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: HomeLogic.tileHeight, maxHeight: HomeLogic.tileHeight)
            .background(shape.fill(Color.white.opacity(status.printing ? 0.13 : 0.065)))
            .overlay(shape.strokeBorder(Color.white.opacity(hovered ? 0.14 : 0), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(text.removeFromHome) { UserDefaults.standard.set(false, forKey: DefaultsKey.forkHomeShowsPrinter) }
        }
        .accessibilityLabel(bambu.name ?? text.printerTile)
    }

    private func subtitle(_ status: ForkBambuLogic.Status, text: ForkHomeStrings) -> String {
        let french = l10n.language == .fr
        guard status.state != nil else { return text.printerHint }
        var parts = [ForkBambuLogic.stateText(status, french: french)]
        if status.printing, let percent = status.percent { parts.append(french ? "\(percent) %" : "\(percent)%") }
        if status.printing, let minutes = status.remainingMinutes {
            parts.append(ForkBambuStrings.current.left(ForkBambuLogic.remaining(minutes)))
        }
        return parts.joined(separator: " · ")
    }
}

/// The printer in the Home page: a back arrow, then the camera and the print.
private struct ForkHomePrinterView: View {
    let size: CGSize
    @ObservedObject private var home = ForkHome.shared
    @ObservedObject private var bambu = ForkBambu.shared

    var body: some View {
        let text = ForkHomeStrings.current
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { home.hidePrinter() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(text.back)
                .accessibilityLabel(text.back)
                Text(bambu.name ?? text.printerTile).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: HomeLogic.printerBar - 8)
            ForkBambuLive(width: size.width - 12)
        }
        .onAppear { bambu.pageOpened() }
        .onDisappear { bambu.pageClosed() }
    }
}

/// The Home button among the island's controls: opens the page.
struct ForkHomeIslandTile: View {
    let service: NotchService

    var body: some View {
        NotchActionTile(symbol: HomeLogic.pageSymbol, title: ForkHomeStrings.current.title) {
            service.open(.home)
        }
    }
}

// MARK: - A favourite's menu tile

/// A favourite as a tile of the menu, lit like the menu's own switches. A
/// sensor's tile shows its value and opens the island's page; a gate's
/// acts on a second click.
struct ForkHomeMenuTile: View {
    let id: String
    @ObservedObject private var home = ForkHome.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var armed = false

    var body: some View {
        let entity = home.entity(id)
        let french = l10n.language == .fr
        let shutter = entity.flatMap { $0.kind == .cover && !$0.needsConfirmation ? $0 : nil }
        let title = entity.map { entity in
            if armed { return HomeLogic.confirmText(.main, for: entity, french: french) }
            return HomeLogic.actionable(entity) || entity.kind == .camera ? entity.name
                : "\(entity.name) · \(HomeLogic.stateText(entity, french: french))"
        } ?? HomeLogic.fallbackName(id)
        let arrow = shutter.map { HomeLogic.commandSymbol(HomeLogic.command(for: home.coverDirection($0))) }
        ForkTile(title: title, symbol: arrow ?? entity.map(HomeLogic.symbol) ?? HomeLogic.pageSymbol,
                 on: armed || (entity.map(HomeLogic.isOn) ?? false),
                 tint: armed ? .orange : entity.map(forkHomeTint) ?? .accentColor,
                 badge: home.failed.contains(id) ? .failed : nil, busy: home.pending.contains(id),
                 enabled: home.status == .connected && entity != nil) {
            guard let entity else { return }
            if shutter != nil {
                home.pressCover(entity)
            } else if entity.kind == .camera {
                home.startViewing(entity.id)
                ForkQuickActions.closingPanel { NotchService.shared.open(.home) }
            } else if !HomeLogic.actionable(entity) {
                ForkQuickActions.closingPanel { NotchService.shared.open(.home) }
            } else if !entity.needsConfirmation {
                home.perform(.main, on: entity)
            } else if armed {
                armed = false
                home.perform(.main, on: entity, confirmed: true)
            } else {
                armed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + HomeLogic.confirmWindow) { armed = false }
            }
        }
    }

    /// The name the menu's edit list shows.
    static func title(_ id: String) -> String {
        ForkHome.shared.entity(id)?.name ?? HomeLogic.fallbackName(id)
    }
}

// MARK: - Choosing devices

/// Every device Home Assistant offers, by room, with a search field: the
/// star makes it a favourite, the square also gives it a menu tile.
struct ForkHomePicker: View {
    var island = false
    @ObservedObject private var home = ForkHome.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.forkHomeFavorites) private var favoritesRaw = ""
    @AppStorage(DefaultsKey.forkHomeMenuTiles) private var menuRaw = ""
    @State private var query = ""

    var body: some View {
        let text = ForkHomeStrings.current
        let _ = (favoritesRaw, menuRaw)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.search, text: $query).textFieldStyle(.plain)
                if home.loadingChoices { ProgressView().controlSize(.mini) }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
            content(text)
        }
        .onAppear { home.loadChoices() }
        .onChange(of: home.status) { _, now in if now == .connected { home.loadChoices() } }
    }

    @ViewBuilder
    private func content(_ text: ForkHomeStrings) -> some View {
        let shown = home.choices.filter { HomeLogic.matches($0, area: home.rooms.areaOfEntity[$0.id], query: query) }
        if home.status != .connected {
            note(text.notConnected)
        } else if home.choices.isEmpty && home.loadingChoices {
            note(text.loading)
        } else if shown.isEmpty {
            note(text.noDevices)
        } else {
            ScrollView(.vertical, showsIndicators: !island) {
                LazyVStack(spacing: 1) {
                    ForEach(shown.prefix(400)) { row($0, text: text) }
                }
            }
            .frame(maxHeight: island ? .infinity : 280)
        }
    }

    private func note(_ words: String) -> some View {
        Text(words).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
    }

    private func row(_ entity: ForkHomeLogic.Entity, text: ForkHomeStrings) -> some View {
        let favorite = home.isFavorite(entity.id)
        let tile = home.isMenuTile(entity.id)
        let french = l10n.language == .fr
        let detail = [HomeLogic.kindLabel(entity, french: french), home.rooms.areaOfEntity[entity.id],
                      HomeLogic.stateText(entity, french: french)]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 10) {
            Image(systemName: HomeLogic.symbol(entity))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(forkHomeTint(entity))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { home.toggleMenuTile(entity.id) } label: {
                Image(systemName: tile ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .foregroundStyle(tile ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!favorite)
            .opacity(favorite ? 1 : 0.3)
            .help(text.menuTile)
            .accessibilityLabel("\(text.menuTile) \(entity.name)")
            Button { home.toggleFavorite(entity.id) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(text.favorite)
            .accessibilityLabel("\(text.favorite) \(entity.name)")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(favorite ? Color.primary.opacity(0.06) : .clear))
    }
}

// MARK: - Settings

/// The Home page's settings, on its page in the island's Content tab (even
/// while it is off, so its switch is there): the switch, the addresses, the
/// token (Keychain only), the connection and the devices.
struct ForkHomeSettingsSection: View {
    private enum Field { case address, fallback }

    @AppStorage(DefaultsKey.forkHomeEnabled) private var enabled = false
    @AppStorage(DefaultsKey.forkHomeURL) private var address = ""
    @AppStorage(DefaultsKey.forkHomeFallbackURL) private var fallback = ""
    @AppStorage(DefaultsKey.forkHomeShowsPrinter) private var showsPrinter = true
    @ObservedObject private var home = ForkHome.shared
    @State private var addressDraft = ""
    @State private var fallbackDraft = ""
    @State private var token = ""
    @FocusState private var focus: Field?

    /// Fields sit under their title, as wide as the page: beside a long
    /// caption their buttons were pushed out of sight.
    private let fieldInset: CGFloat = 38

    var body: some View {
        let text = ForkHomeStrings.current
        VStack(alignment: .leading, spacing: 10) {
            ForkOptionRow(symbol: HomeLogic.pageSymbol, title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                if ForkBambuLogic.pageAvailable(in: .standard) {
                    ForkOptionRow(symbol: ForkBambuLogic.pageSymbol, title: text.showPrinter, caption: text.showPrinterCaption) {
                        Toggle(text.showPrinter, isOn: $showsPrinter).labelsHidden().toggleStyle(.switch)
                    }
                }
                addressRow(.address, text: text)
                addressRow(.fallback, text: text)
                tokenRow(text)
                ForkOptionRow(symbol: statusSymbol, title: text.connection, caption: statusText(text)) {
                    Button(text.test) {
                        saveDrafts()
                        home.reconnect()
                    }
                    .fixedSize()
                    .disabled(!home.hasToken || mainAddress == nil)
                }
                ForkOptionRow(symbol: "star", title: text.devices, caption: text.devicesCaption) { EmptyView() }
                ForkHomePicker()
            }
        }
        .onAppear {
            addressDraft = address
            fallbackDraft = fallback
        }
        // A typed address is kept on leaving its field, Return or not.
        .onChange(of: focus) { previous, _ in if let previous { save(previous) } }
        .onDisappear { saveDrafts() }
    }

    /// The address to reach: the one saved, or a valid one just typed.
    private var mainAddress: URL? { HomeLogic.validAddress(addressDraft) ?? home.address }

    private func draft(_ field: Field) -> Binding<String> { field == .address ? $addressDraft : $fallbackDraft }
    private func saved(_ field: Field) -> Binding<String> { field == .address ? $address : $fallback }

    /// Keeps a field's valid address (the fallback may also be emptied); an
    /// invalid one stays typed, with its caption saying why.
    private func save(_ field: Field) {
        let draft = draft(field), saved = saved(field)
        let typed = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty, field == .fallback {
            saved.wrappedValue = ""
        } else if let url = HomeLogic.validAddress(typed) {
            saved.wrappedValue = url.absoluteString
            draft.wrappedValue = url.absoluteString
        }
    }

    private func saveDrafts() {
        save(.address)
        save(.fallback)
    }

    private func addressRow(_ field: Field, text: ForkHomeStrings) -> some View {
        let main = field == .address
        let draft = draft(field), saved = saved(field)
        let typed = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = typed != saved.wrappedValue && (HomeLogic.validAddress(typed) != nil || (!main && typed.isEmpty))
        return VStack(alignment: .leading, spacing: 6) {
            ForkOptionRow(symbol: main ? "network" : "arrow.triangle.branch", title: main ? text.address : text.fallback,
                          caption: caption(typed, saved: saved.wrappedValue, normal: main ? text.addressCaption : text.fallbackCaption,
                                           text: text)) { EmptyView() }
            HStack(spacing: 6) {
                TextField(main ? "http://homeassistant.local:8123" : "https://…", text: draft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: field)
                    .onSubmit { save(field) }
                Button(text.save) { save(field) }
                    .fixedSize()
                    .disabled(!canSave)
            }
            .padding(.leading, fieldInset)
        }
    }

    private func caption(_ typed: String, saved: String, normal: String, text: ForkHomeStrings) -> String {
        guard !typed.isEmpty, typed != saved else { return normal }
        switch HomeLogic.address(typed) {
        case .success: return normal
        case .failure(.insecure): return text.insecureAddress
        case .failure: return text.invalidAddress
        }
    }

    @ViewBuilder
    private func tokenRow(_ text: ForkHomeStrings) -> some View {
        if home.hasToken {
            ForkOptionRow(symbol: "key.fill", title: text.token, caption: text.tokenCaption) {
                Button(text.forgetToken) { home.forgetToken() }.fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForkOptionRow(symbol: "key", title: text.token, caption: text.tokenCaption) { EmptyView() }
                HStack(spacing: 6) {
                    SecureField(text.token, text: $token).labelsHidden().textFieldStyle(.roundedBorder)
                        .onSubmit { if home.setToken(token) { token = "" } }
                    Button(text.save) { if home.setToken(token) { token = "" } }
                        .fixedSize()
                        .disabled(HomeLogic.cleanToken(token) == nil)
                    Button(text.createToken) {
                        saveDrafts()
                        if let base = mainAddress, let page = HomeLogic.tokensPage(base) { NSWorkspace.shared.open(page) }
                    }
                    .fixedSize()
                    .disabled(mainAddress == nil)
                }
                .padding(.leading, fieldInset)
            }
        }
    }

    private var statusSymbol: String {
        switch home.status {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .unauthorized, .unreachable: return "exclamationmark.triangle.fill"
        case .off, .needsSetup: return "circle.dashed"
        }
    }

    private func statusText(_ text: ForkHomeStrings) -> String {
        switch home.status {
        case .off: return text.off
        case .needsSetup:
            if home.address == nil { return home.hasToken ? text.needsAddress : text.needsSetup }
            return text.needsToken
        case .connecting: return text.connecting
        case .connected: return home.usingFallback ? text.connectedFallback : text.connected
        case .unauthorized: return text.unauthorized
        case .unreachable: return text.unreachable
        }
    }
}
