// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The simple menus (see `ForkPanelLook`), each piece wrapping upstream's
/// own view and falling back to it when the switch is off, inside the
/// Dynamic Island, or while a tab is being arranged: the tab bar names the
/// active tab, quick actions are tiles, Keep Awake opens on its state, and
/// the disk's health folds into one line. Upstream's actions, states and
/// preferences are used as they are; nothing here keeps a state of its own.

// MARK: - Tab bar

/// Icons for the other tabs and, for the active one, a pill with its name,
/// which slides along with a critically damped spring.
struct ForkPanelTabs<Original: View>: View {
    let sections: [PanelSectionID]
    let active: PanelSectionID
    let select: (PanelSectionID) -> Void
    @ViewBuilder let original: () -> Original
    @AppStorage(DefaultsKey.forkSimplePanels) private var simple = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var l10n = L10n.shared
    @Namespace private var pill

    var body: some View {
        if simple { tabs } else { original() }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(sections) { id in
                let isActive = id == active
                Button { select(id) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: id.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                        if isActive {
                            Text(ForkPanelStrings.current.tab(id) ?? id.title(l10n.s))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, isActive ? 10 : 0)
                    .frame(maxWidth: isActive ? nil : .infinity)
                    .frame(height: 30)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(colorScheme == .light ? Color.accentColor.opacity(0.13) : Color.accentColor.opacity(0.22))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.86))
                .layoutPriority(isActive ? 1 : 0)
                .accessibilityLabel(id.title(l10n.s))
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PanelSurface.cardFill(for: colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: active)
    }
}

/// The capitals over a section, gone when the tab bar already names it.
struct ForkSectionTitle<Original: View>: View {
    @ViewBuilder let original: () -> Original
    @AppStorage(DefaultsKey.forkSimplePanels) private var simple = true
    @Environment(\.notchPresentation) private var notch

    var body: some View {
        if !simple || notch { original() }
    }
}

// MARK: - Quick actions

/// The quick actions as tiles, three a row; arranging them happens on the
/// tiles themselves (`ForkQuickActionTiles(editing:)`).
struct ForkQuickActionsGrid<List: View>: View {
    let editing: Bool
    @ViewBuilder let list: () -> List
    @AppStorage(DefaultsKey.forkSimplePanels) private var simple = true
    @Environment(\.notchPresentation) private var notch

    var body: some View {
        if simple, !notch {
            ForkQuickActionTiles(editing: editing)
        } else {
            list()
        }
    }
}

/// One of the menu's tiles: the fork's or upstream's.
enum ForkMenuTile: Hashable {
    case fork(ForkQuickActionLogic.Action)
    case panel(QuickToggleAction)

    var key: String {
        switch self {
        case .fork(let action): return ForkTileLayoutLogic.forkKey(action.rawValue)
        case .panel(let item): return ForkTileLayoutLogic.panelKey(item.rawValue)
        }
    }

    init?(key: String) {
        if key.hasPrefix(ForkTileLayoutLogic.forkKey("")),
           let action = ForkQuickActionLogic.Action(rawValue: String(key.dropFirst(ForkTileLayoutLogic.forkKey("").count))) {
            self = .fork(action)
        } else if key.hasPrefix(ForkTileLayoutLogic.panelKey("")),
                  let item = QuickToggleAction(rawValue: String(key.dropFirst(ForkTileLayoutLogic.panelKey("").count))) {
            self = .panel(item)
        } else {
            return nil
        }
    }
}

/// The tiles in the order arranged by hand (`forkTileOrder`), the fork's and
/// upstream's mixed. Arranging (the panel's edit button) shows every tile:
/// those shown with a « − », the hidden ones below with a « + »; a tile held
/// and dragged takes another's place, or crosses to the other part to hide
/// or come back. Each tile's showing stays in its own setting.
struct ForkQuickActionTiles: View {
    var editing = false
    @ObservedObject private var toggles = QuickTogglesService.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @ObservedObject private var presentation = ForkPresentationMode.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DefaultsKey.panelToggleOrder) private var orderRaw = ""
    @AppStorage(DefaultsKey.forkQuickActionsHidden) private var forkHiddenRaw = ""
    @AppStorage(DefaultsKey.forkTileOrder) private var tileOrderRaw = ""
    /// Upstream's switches are not watched one by one: a change here redraws.
    @State private var revision = 0
    @State private var dragging: ForkMenuTile?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let _ = (forkHiddenRaw, orderRaw, tileOrderRaw, revision)
        let parts = arrangement
        Group {
            if editing {
                editor(parts)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(parts.shown, id: \.self) { tile($0) }
                }
            }
        }
        .panelCard()
        .onAppear {
            toggles.refreshPermissionStates()
            brightness.refreshKeyboardLight()
        }
        .onChange(of: editing) { _, now in
            dragging = nil
            if now { presentation.lookUpShortcuts() }
        }
    }

    // MARK: - Order and showing

    /// Every tile in the default order: the fork's, then upstream's as its list had them.
    private var known: [ForkMenuTile] {
        ForkQuickActionLogic.Action.allCases.map(ForkMenuTile.fork)
            + PanelLayout.itemOrder(QuickToggleAction.self, key: DefaultsKey.panelToggleOrder).map(ForkMenuTile.panel)
    }

    /// The whole order, tiles whose tool is off included, so they keep their place.
    private var order: [String] {
        ForkTileLayoutLogic.ordered(stored: ForkTileLayoutLogic.parse(tileOrderRaw), known: known.map(\.key))
    }

    private var arrangement: (shown: [ForkMenuTile], hidden: [ForkMenuTile]) {
        let forkHidden = ForkQuickActions.hidden()
        let tiles = order.compactMap(ForkMenuTile.init(key:)).filter(isAvailable)
        let parts = ForkTileLayoutLogic.split(tiles.map(\.key)) { key in
            ForkMenuTile(key: key).map { isHidden($0, forkHidden: forkHidden) } ?? true
        }
        return (parts.shown.compactMap(ForkMenuTile.init(key:)), parts.hidden.compactMap(ForkMenuTile.init(key:)))
    }

    private func isAvailable(_ tile: ForkMenuTile) -> Bool {
        switch tile {
        case .fork(let action): return ForkQuickActions.isAvailable(action)
        case .panel(let item):
            return item.feature.isAvailable && (item != .keyboardLight || brightness.keyboardLightEnabled != nil)
        }
    }

    private func isHidden(_ tile: ForkMenuTile, forkHidden: Set<ForkQuickActionLogic.Action>) -> Bool {
        switch tile {
        case .fork(let action): return forkHidden.contains(action)
        case .panel(let item): return !UserDefaults.standard.bool(forKey: Self.visibilityKey(item))
        }
    }

    private func setHidden(_ tile: ForkMenuTile, _ hide: Bool) {
        switch tile {
        case .fork(let action): ForkQuickActions.setHidden(action, hide)
        case .panel(let item): UserDefaults.standard.set(!hide, forKey: Self.visibilityKey(item))
        }
        revision += 1
    }

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1) }

    /// `tile` dragged onto `target`, in the part `hidden` says.
    private func move(_ tile: ForkMenuTile, onto target: ForkMenuTile, hidden: Bool) {
        withAnimation(motion) {
            if isHidden(tile, forkHidden: ForkQuickActions.hidden()) != hidden { setHidden(tile, hidden) }
            tileOrderRaw = ForkTileLayoutLogic.encode(ForkTileLayoutLogic.move(tile.key, onto: target.key, in: order))
        }
    }

    /// `tile` dropped on a part's free space: it goes last, shown or hidden.
    private func place(_ tile: ForkMenuTile, hidden: Bool) {
        withAnimation(motion) {
            if isHidden(tile, forkHidden: ForkQuickActions.hidden()) != hidden { setHidden(tile, hidden) }
            tileOrderRaw = ForkTileLayoutLogic.encode(ForkTileLayoutLogic.moveToEnd(tile.key, in: order))
        }
    }

    // MARK: - Arranging

    private func editor(_ parts: (shown: [ForkMenuTile], hidden: [ForkMenuTile])) -> some View {
        let text = ForkQuickActionStrings.current
        return VStack(alignment: .leading, spacing: 10) {
            Text(text.editHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            section(parts.shown, hidden: false)
            Text(text.hiddenSection)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if parts.hidden.isEmpty {
                Text(text.hiddenEmpty)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .onDrop(of: [UTType.text], delegate: ForkTileAreaDrop(hidden: true, dragging: $dragging, place: place))
            } else {
                section(parts.hidden, hidden: true)
            }
            if isAvailable(.fork(.presentation)) {
                Text(presentation.hasFocusShortcuts == true ? text.focusReady : text.focusMissing)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section(_ tiles: [ForkMenuTile], hidden: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.element) { index, tile in
                editable(tile, hidden: hidden, index: index)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // Free space in a part takes a tile to its end.
        .onDrop(of: [UTType.text], delegate: ForkTileAreaDrop(hidden: hidden, dragging: $dragging, place: place))
    }

    private func editable(_ tile: ForkMenuTile, hidden: Bool, index: Int) -> some View {
        let text = ForkQuickActionStrings.current
        let name = title(of: tile)
        return ZStack(alignment: .topLeading) {
            self.tile(tile)
                .allowsHitTesting(false)
                .opacity(hidden ? 0.45 : 1)
            Button {
                withAnimation(motion) { setHidden(tile, !hidden) }
            } label: {
                Image(systemName: hidden ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, hidden ? Color.green : Color.gray)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -4, y: -4)
            .accessibilityLabel(hidden ? text.show(name) : text.hide(name))
        }
        .contentShape(Rectangle())
        .modifier(ForkJiggle(active: !reduceMotion, delay: ForkTileLayoutLogic.jiggleDelay(index: index)))
        .onDrag {
            dragging = tile
            return NSItemProvider(object: tile.key as NSString)
        }
        .onDrop(of: [UTType.text], delegate: ForkTileDrop(target: tile, hidden: hidden, dragging: $dragging, move: move))
        .accessibilityElement(children: .contain)
    }

    private func title(of tile: ForkMenuTile) -> String {
        switch tile {
        case .fork(let action): return ForkQuickActionStrings.current.title(action)
        case .panel(let item): return panelTitle(item)
        }
    }

    @ViewBuilder
    private func tile(_ tile: ForkMenuTile) -> some View {
        switch tile {
        case .fork(let action): ForkQuickActionTile(action: action)
        case .panel(let item): panelTile(item)
        }
    }

    private func panelTitle(_ item: QuickToggleAction) -> String {
        let text = ForkPanelStrings.current
        switch item {
        case .darkMode: return text.darkMode
        case .keyboardLight: return text.keyboardLight
        case .micMute: return text.micMuted
        case .emptyTrash: return text.emptyTrash
        case .quitAllApps: return text.quitAll
        case .ejectDisks: return text.eject
        case .hiddenFiles: return text.hiddenFiles
        case .desktopIcons: return text.desktopIcons
        case .lockScreen: return text.lock
        case .displayOff: return text.displayOff
        case .screenSaver: return text.screenSaver
        }
    }

    static func visibilityKey(_ item: QuickToggleAction) -> String {
        switch item {
        case .darkMode: return DefaultsKey.panelToggleDarkMode
        case .keyboardLight: return DefaultsKey.panelToggleKeyboardLight
        case .micMute: return DefaultsKey.panelToggleMicMute
        case .emptyTrash: return DefaultsKey.panelToggleEmptyTrash
        case .quitAllApps: return DefaultsKey.panelToggleQuitAllApps
        case .ejectDisks: return DefaultsKey.panelToggleEjectDisks
        case .hiddenFiles: return DefaultsKey.panelToggleHiddenFiles
        case .desktopIcons: return DefaultsKey.panelToggleDesktopIcons
        case .lockScreen: return DefaultsKey.panelToggleLockScreen
        case .displayOff: return DefaultsKey.panelToggleDisplayOff
        case .screenSaver: return DefaultsKey.panelToggleScreenSaver
        }
    }

    /// Actions that take the screen close the panel first, as upstream's rows do.
    private func afterClosing(_ action: @escaping () -> Void) {
        appDelegate()?.closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
    }

    private func panelTile(_ item: QuickToggleAction) -> some View {
        let text = ForkPanelStrings.current
        let state = toggles.state(for: item)
        let service = QuickTogglesService.shared
        var title = "", symbol = "", on = false, tint = Color.accentColor, enabled = true
        var action: () -> Void = {}
        switch item {
        case .darkMode:
            (title, symbol, on) = (text.darkMode, "moon.fill", colorScheme == .dark)
            action = { service.toggleDarkMode() }
        case .keyboardLight:
            let lit = brightness.keyboardLightEnabled ?? false
            (title, symbol, on) = (text.keyboardLight, "light.max", lit)
            action = { brightness.setKeyboardLightEnabled(!lit) }
        case .micMute:
            (title, symbol, on, tint) = (text.micMuted, micMute.isMuted ? "mic.slash.fill" : "mic.fill", micMute.isMuted, Color.red)
            action = { MicMuteService.shared.toggle() }
        case .emptyTrash:
            (title, symbol) = (text.emptyTrash, "trash")
            action = state == .needsPermission ? { Permissions.shared.openAutomationSettings() } : { service.emptyTrash() }
        case .quitAllApps:
            (title, symbol) = (text.quitAll, "xmark.app")
            action = { service.showQuitApps() }
        case .ejectDisks:
            (title, symbol, enabled) = (text.eject, "eject.fill", toggles.ejectableVolumeCount() > 0 || state == .running)
            action = { service.ejectAllDisks() }
        case .hiddenFiles:
            (title, symbol, on) = (text.hiddenFiles, toggles.hiddenFilesShown ? "eye" : "eye.slash", toggles.hiddenFilesShown)
            action = { service.toggleHiddenFiles() }
        case .desktopIcons:
            (title, symbol, on) = (text.desktopIcons, "desktopcomputer", toggles.desktopIconsShown)
            action = { service.toggleDesktopIcons() }
        case .lockScreen:
            (title, symbol) = (text.lock, "lock.fill")
            action = { afterClosing { service.lockScreen() } }
        case .displayOff:
            (title, symbol) = (text.displayOff, "display")
            action = { afterClosing { service.turnDisplayOff() } }
        case .screenSaver:
            (title, symbol) = (text.screenSaver, "sparkles.tv")
            action = { afterClosing { service.startScreenSaver() } }
        }
        let badge: ForkTile.Badge? = state == .failed ? .failed : (state == .needsPermission ? .permission : nil)
        return ForkTile(title: title, symbol: symbol, on: on, tint: tint, badge: badge,
                        busy: state == .running, enabled: enabled, action: action)
    }
}

/// A tile held over another takes its place, live; dropped, the drag ends.
private struct ForkTileDrop: DropDelegate {
    let target: ForkMenuTile
    let hidden: Bool
    @Binding var dragging: ForkMenuTile?
    let move: (ForkMenuTile, ForkMenuTile, Bool) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        move(dragging, target, hidden)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// A tile dropped on a part's free space goes to its end, shown or hidden.
private struct ForkTileAreaDrop: DropDelegate {
    let hidden: Bool
    @Binding var dragging: ForkMenuTile?
    let place: (ForkMenuTile, Bool) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let dragging { place(dragging, hidden) }
        dragging = nil
        return true
    }
}

/// While arranging, each tile swings a little, as on the iPhone; still with
/// Reduce Motion.
private struct ForkJiggle: ViewModifier {
    let active: Bool
    let delay: Double
    @State private var swing = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (swing ? 1 : -1) * ForkTileLayoutLogic.jiggleAngle : 0))
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: ForkTileLayoutLogic.jiggleDuration)
                    .repeatForever(autoreverses: true).delay(delay)) { swing = true }
            }
    }
}

/// One tile: a round glyph, lit in its colour while on, over a short name.
/// It answers the press at once and follows the pointer.
struct ForkTile: View {
    enum Badge: Equatable { case failed, permission, count(String) }

    let title: String
    let symbol: String
    let on: Bool
    let tint: Color
    let badge: Badge?
    let busy: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(on ? tint : Color.primary.opacity(0.09))
                        .frame(width: 34, height: 34)
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if case .count(let count) = badge {
                        Text(count)
                            .font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 5, y: -4)
                    } else if let badge {
                        Image(systemName: badge == .failed ? "exclamationmark.circle.fill" : "lock.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white, badge == .failed ? Color.red : Color.orange)
                            .offset(x: 4, y: -3)
                    }
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(hovered && enabled ? 0.08 : 0.035)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ForkPressStyle())
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.easeOut(duration: 0.2), value: on)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Shrinks a touch the moment it is pressed, back on release.
struct ForkPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 1), value: configuration.isPressed)
    }
}

// MARK: - Keep Awake

/// The top of the Keep Awake card: its state first, the durations on one
/// row; the island keeps upstream's version.
struct ForkKeepAwakeTop<Original: View>: View {
    @ViewBuilder let original: () -> Original
    @AppStorage(DefaultsKey.forkSimplePanels) private var simple = true
    @Environment(\.notchPresentation) private var notch

    var body: some View {
        if simple, !notch { ForkKeepAwakeHero() } else { original() }
    }
}

struct ForkKeepAwakeHero: View {
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared
    /// The last started end time, which the end-time chip opens on (upstream's key).
    @AppStorage(DefaultsKey.keepAwakeUntilTime) private var savedUntilTime = 0.0
    @State private var untilDraft: Date?

    private var manual: Bool { awake.isActive && awake.sessionTrigger != .automation }

    var body: some View {
        let text = ForkPanelStrings.current
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(awake.isActive ? Color.orange : Color.primary.opacity(0.09))
                        .frame(width: 34, height: 34)
                    Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "moon.zzz.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(awake.isActive ? Color.white : Color.secondary)
                }
                .animation(.easeOut(duration: 0.2), value: awake.isActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(awake.isActive ? text.awake : text.sleeps)
                        .font(.system(size: 14, weight: .semibold))
                    status
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Toggle(l10n.s.keepAwakeTitle, isOn: Binding(
                    get: { awake.isActive },
                    set: { on in
                        if on { awake.startLastPick() } else if awake.isActive { awake.toggle() }
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if manual, awake.endDate != nil {
                HStack(spacing: 6) {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("+" + DurationPicker.shortTitle(for: minutes, l10n.s, l10n.language)) {
                            awake.extend(minutes: minutes)
                        }
                        .buttonStyle(ForkChipStyle())
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
            ViewThatFits(in: .horizontal) {
                durations(ForkPanelLook.durations)
                durations(ForkPanelLook.shortDurations)
            }
            if let percent = awake.batteryProtectionPercent() {
                Label(text.batteryNote(percent), systemImage: "battery.25percent")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: manual && awake.endDate != nil)
    }

    @ViewBuilder
    private var status: some View {
        if awake.isActive {
            if awake.sessionTrigger == .automation {
                Text(FeatureStrings.keepAwakeAutomation(l10n.language).activeStatus(for: awake.activeAutomationConditions))
            } else if let end = awake.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ForkPanelStrings.current.remaining(KeepAwakeCard.countdownText(until: end),
                                                            end.formatted(date: .omitted, time: .shortened)))
                        .monospacedDigit()
                }
            } else {
                Text(l10n.s.keepAwakeUntilDisabled)
            }
        } else {
            Text(l10n.s.keepAwakeNormalRules)
        }
    }

    private func durations(_ choices: [Int]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element) { index, minutes in
                if index > 0 { Spacer(minLength: 4) }
                let selected = manual && awake.sessionMinutes == minutes
                Button(DurationPicker.shortTitle(for: minutes, l10n.s, l10n.language)) {
                    if selected { awake.toggle() } else { awake.activate(minutes: minutes) }
                }
                .buttonStyle(ForkChipStyle(isSelected: selected))
                .accessibilityLabel(DurationPicker.title(for: minutes, l10n.s))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 4)
            KeepAwakeEndTimePicker(selection: untilTime,
                                   activeEnd: manual && awake.sessionMinutes == nil ? awake.endDate : nil,
                                   onStop: { awake.toggle() }) {
                awake.activate(until: KeepAwakeAutomationSupport.resolvedUntilDate(picked: untilTime.wrappedValue, now: Date()))
                untilDraft = nil
            }
        }
    }

    /// Only the hour and minute matter, as in upstream's card.
    private var untilTime: Binding<Date> {
        Binding(get: {
            untilDraft ?? (savedUntilTime > 0 ? Date(timeIntervalSinceReferenceDate: savedUntilTime)
                : Date().addingTimeInterval(3600))
        }, set: { untilDraft = $0 })
    }
}

/// Upstream's chip look, as wide as its label rather than the row.
struct ForkChipStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(Capsule().fill(isSelected
                ? Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)
                : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// MARK: - Disks

/// The disk's health in one line, its details one click further.
struct ForkDiskHealthFold<Original: View>: View {
    let disk: DiskDeviceReading
    let editing: Bool
    @ViewBuilder let original: () -> Original
    @AppStorage(DefaultsKey.forkSimplePanels) private var simple = true
    @AppStorage(DefaultsKey.monitorDiskSMART) private var smartVisible = true
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @Environment(\.notchPresentation) private var notch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var l10n = L10n.shared
    @State private var expanded = false

    var body: some View {
        if !simple || editing || notch || !smartVisible {
            original()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colour)
                        Text(summary)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(expanded ? ForkPanelStrings.current.expanded : ForkPanelStrings.current.collapsed)
                if expanded { original().transition(.opacity) }
            }
        }
    }

    private var health: ForkPanelLook.Health { ForkPanelLook.health(percent: disk.smart?.healthPercent) }

    private var symbol: String {
        switch health {
        case .good: return "checkmark.shield.fill"
        case .worn: return "exclamationmark.shield.fill"
        case .failing: return "xmark.shield.fill"
        case .unknown: return "shield"
        }
    }

    private var colour: Color {
        switch health {
        case .good: return .green
        case .worn: return .orange
        case .failing: return .red
        case .unknown: return .secondary
        }
    }

    private var summary: String {
        guard let smart = disk.smart else { return l10n.s.diskSMARTUnavailable }
        var parts: [String] = []
        if let percent = smart.healthPercent { parts.append("\(l10n.s.diskHealth) \(percent) %") }
        if let celsius = smart.temperatureCelsius {
            parts.append(MetricFormat.temperature(celsius, unit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius))
        }
        if parts.isEmpty, let status = smart.status { parts.append(status) }
        return parts.isEmpty ? l10n.s.monitorItemDiskSMART : parts.joined(separator: " · ")
    }
}

// MARK: - The switch

/// On the menu's settings page, under the tabs' editor.
struct ForkSimplePanelsRow: View {
    @AppStorage(DefaultsKey.forkSimplePanels) private var simple = true

    var body: some View {
        let text = ForkPanelStrings.current
        Divider()
        ForkOptionRow(symbol: "rectangle.grid.2x2", title: text.toggle, caption: text.caption) {
            Toggle(text.toggle, isOn: $simple)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: - Values not there yet

/// A value, or while it is not there yet a quiet bar where it will be, in
/// place of upstream's « - » or « Measuring… ».
struct ForkPanelValueText: View {
    let text: String?
    let fallback: String
    var width: CGFloat = 30

    var body: some View {
        if let text {
            Text(text)
        } else if ForkPanelLook.showsPlaceholder(present: false) {
            ForkPanelPlaceholderBar(width: width)
        } else {
            Text(fallback)
        }
    }
}

/// A soft capsule that breathes while a reading is awaited.
struct ForkPanelPlaceholderBar: View {
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(dim ? 0.1 : 0.22))
            .frame(width: width, height: 9)
            .padding(.vertical, 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityElement()
            .accessibilityLabel(ForkPanelStrings.current.waiting)
    }
}

/// Three placeholder rows while a list of apps is being filled.
struct ForkPanelLoadingRows: View {
    var leading: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 14, height: 14)
                    ForkPanelPlaceholderBar(width: [96, 72, 116][index])
                    Spacer(minLength: 0)
                    ForkPanelPlaceholderBar(width: 30)
                }
            }
        }
        .padding(.leading, leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ForkPanelStrings.current.waiting)
    }
}
