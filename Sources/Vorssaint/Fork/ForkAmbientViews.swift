// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

// MARK: - Shared pieces

/// A small wave of bars that moves while the sound plays, flat otherwise
/// (and still with Reduce Motion).
struct ForkAmbientWave: View {
    var active: Bool
    var bars = 5
    var color: Color = .white
    var height: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !active || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: ForkAmbientLogic.waveSpacing(height: height)) {
                ForEach(0..<bars, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: ForkAmbientLogic.waveBarWidth(height: height), height: barHeight(index, time: time))
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, time: Double) -> CGFloat {
        guard active, !reduceMotion else { return max(2, height * 0.22) }
        let phase = time * (2.2 + Double(index) * 0.37) + Double(index) * 1.3
        let level = 0.35 + 0.65 * abs(sin(phase) * cos(phase * 0.47))
        return max(2, height * CGFloat(level))
    }
}

private extension ForkAmbientStrings {
    /// What plays: a ready-made ambience, a favourite, or the user's own mix.
    func mixName(_ player: ForkAmbientPlayer) -> String {
        if let chosen = player.preset { return preset(chosen) }
        if let favorite = player.favorite { return favorite.name }
        return custom
    }

    /// The panel's and the window's status line.
    func status(_ player: ForkAmbientPlayer) -> String {
        if player.holding { return held }
        if let phase = player.phase, let remaining = player.remaining {
            return "\(self.phase(phase)) · \(ForkAmbientLogic.clock(remaining))"
        }
        if let remaining = player.remaining { return "\(mixName(player)) · \(ForkAmbientLogic.clock(remaining))" }
        return mixName(player)
    }
}

// MARK: - Window

/// Background sound's window, in the look of the cleaning tools.
final class ForkAmbientWindow {
    static let shared = ForkAmbientWindow()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = ForkCareWindow.make(title: ForkAmbientStrings.current.title,
                                         size: NSSize(width: 820, height: 760), minSize: NSSize(width: 700, height: 620),
                                         content: ForkAmbientView(player: .shared))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.window = nil
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct ForkAmbientView: View {
    typealias Logic = ForkAmbientLogic
    @ObservedObject var player: ForkAmbientPlayer
    @AppStorage(DefaultsKey.forkAmbientTimer) private var timer = 0
    @AppStorage(DefaultsKey.forkAmbientMode) private var modeRaw = Logic.Mode.timer.rawValue
    @AppStorage(DefaultsKey.forkAmbientPomodoroMinutes) private var pomodoroMinutes = 25
    @AppStorage(DefaultsKey.forkAmbientMenuBarIcon) private var menuBarIcon = true
    @AppStorage(DefaultsKey.forkAmbientIslandActivity) private var islandWave = true
    @AppStorage(DefaultsKey.forkAmbientScenes) private var islandScenes = true
    @AppStorage(DefaultsKey.forkAmbientPauseForCalls) private var pauseForCalls = true
    @AppStorage(DefaultsKey.forkAmbientPauseForMusic) private var pauseForMusic = true
    @AppStorage(DefaultsKey.forkAmbientShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.forkAmbientShortcut) private var shortcutRaw = ""
    @AppStorage(DefaultsKey.notchHiddenControls) private var hiddenControls = NotchControlItem.defaultHidden
    @ObservedObject private var l10n = L10n.shared
    @State private var shortcutError: String?
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""

    private var glow: Color { Color(care: ForkCareLogic.glow(.ambient)) }

    var body: some View {
        let text = ForkAmbientStrings.current
        ZStack {
            ForkCareBackground(tool: .ambient)
            ScrollView {
                VStack(spacing: 24) {
                    ForkCareHero(symbol: "waveform", title: text.title, subtitle: text.subtitle)
                        .padding(.top, 6)
                    ForkCareRoundButton(title: player.playing ? text.pause : text.play) { player.toggle() }
                    HStack(spacing: 8) {
                        ForkAmbientWave(active: player.audible, color: Color.careTint(.ambient), height: 14)
                        Text(text.status(player))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.careSecondary)
                    }
                    presets(text).forkCareAppear(index: 1)
                    favorites(text).forkCareAppear(index: 2)
                    ForEach(Array(Logic.Family.allCases.enumerated()), id: \.element) { index, family in
                        sounds(family, text).forkCareAppear(index: 3 + index)
                    }
                    session(text).forkCareAppear(index: 7)
                    options(text).forkCareAppear(index: 8)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.forkCareTool, .ambient)
    }

    private func sectionTitle(_ title: String, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.careSecondary)
                .textCase(.uppercase)
            if let note {
                Label(note, systemImage: "headphones")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.careSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func presets(_ text: ForkAmbientStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(text.presetsTitle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Logic.Preset.allCases) { preset in
                    ForkAmbientChoiceTile(symbol: preset.symbol, title: text.preset(preset),
                                          chosen: player.preset == preset) { player.apply(preset) }
                }
            }
        }
    }

    private func favorites(_ text: ForkAmbientStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(text.favoritesTitle)
            ForkCareCard {
                VStack(alignment: .leading, spacing: 10) {
                    if player.favorites.isEmpty {
                        Text(text.noFavorite).font(.system(size: 12)).foregroundStyle(Color.careSecondary)
                    }
                    ForEach(player.favorites) { favorite in favoriteRow(favorite, text) }
                    HStack(spacing: 8) {
                        TextField(text.favoriteName, text: $newName, prompt: Text(text.defaultFavoriteName))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        Button(text.saveFavorite, action: save)
                            .buttonStyle(.borderedProminent)
                            .tint(glow.opacity(0.7))
                            .disabled(player.mix.isEmpty || player.favorite != nil)
                    }
                }
                .padding(14)
            }
        }
    }

    private func save() {
        player.saveFavorite(named: newName)
        newName = ""
    }

    private func favoriteRow(_ favorite: Logic.Favorite, _ text: ForkAmbientStrings) -> some View {
        let current = player.favorite?.id == favorite.id
        return HStack(spacing: 10) {
            Image(systemName: current ? "star.fill" : "star")
                .foregroundStyle(current ? Color.careTint(.ambient) : Color.careSecondary)
                .accessibilityHidden(true)
            if renaming == favorite.id {
                TextField(text.favoriteName, text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        player.rename(favorite, to: renameText)
                        renaming = nil
                    }
            } else {
                Button { player.apply(favorite) } label: {
                    Text(favorite.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.carePrimary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Text(favorite.sounds.keys.sorted { $0.rawValue < $1.rawValue }.map { text.sound($0) }.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(Color.careSecondary)
                .lineLimit(1)
            Button {
                renaming = favorite.id
                renameText = favorite.name
            } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .foregroundStyle(Color.careSecondary)
                .accessibilityLabel(text.rename)
            Button { player.delete(favorite) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(Color.careSecondary)
                .accessibilityLabel(text.delete)
        }
    }

    private func sounds(_ family: Logic.Family, _ text: ForkAmbientStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(text.family(family), note: family == .binaural ? text.headphones : nil)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(Logic.Sound.allCases.filter { $0.family == family }) { sound in tile(sound, text) }
            }
        }
    }

    private func tile(_ sound: Logic.Sound, _ text: ForkAmbientStrings) -> some View {
        let level = player.mix[sound]
        let on = level != nil
        return ForkCareCard(hoverable: true) {
            VStack(alignment: .leading, spacing: 10) {
                Button { player.toggleSound(sound) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sound.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? Color.carePrimary : Color.careSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(on ? glow.opacity(0.45) : Color.careVeil(0.08)))
                            .accessibilityHidden(true)
                        Text(text.sound(sound))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.carePrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if on { ForkAmbientWave(active: player.audible, bars: 3, color: Color.careTint(.ambient), height: 12) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                Slider(value: Binding(get: { level ?? 0 }, set: { player.setLevel($0, for: sound) }), in: 0...1)
                    .controlSize(.small)
                    .tint(Color.careTint(.ambient))
                    .accessibilityLabel(text.sound(sound))
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(glow.opacity(on ? 0.6 : 0), lineWidth: 1.5))
        }
    }

    private func session(_ text: ForkAmbientStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(text.modeTitle)
            ForkCareCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(text.modeTitle, selection: Binding(get: { Logic.Mode(rawValue: modeRaw) ?? .timer },
                                                              set: { player.setMode($0) })) {
                        Text(text.timerMode).tag(Logic.Mode.timer)
                        Text(text.pomodoroMode).tag(Logic.Mode.pomodoro)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if Logic.Mode(rawValue: modeRaw) == .pomodoro {
                        HStack {
                            Text(text.workLength).foregroundStyle(Color.carePrimary)
                            Spacer()
                            Picker(text.workLength, selection: Binding(get: { pomodoroMinutes },
                                                                       set: { player.setPomodoro(minutes: $0) })) {
                                ForEach(Logic.pomodoroChoices, id: \.self) { Text(text.minutes($0)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        if player.phase != nil {
                            Text(text.round(player.completedWork % Logic.roundsBeforeLongBreak + 1, Logic.roundsBeforeLongBreak))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.careSecondary)
                        }
                    } else {
                        HStack {
                            Text(text.timer).foregroundStyle(Color.carePrimary)
                            Spacer()
                            Picker(text.timer, selection: Binding(get: { timer }, set: { player.setTimer(minutes: $0) })) {
                                ForEach(Logic.timerChoices, id: \.self) { minutes in
                                    Text(minutes == 0 ? text.never : text.minutes(minutes)).tag(minutes)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 320)
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").foregroundStyle(Color.careSecondary)
                        Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1)
                            .tint(Color.careTint(.ambient))
                            .accessibilityLabel(text.volume)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(Color.careSecondary)
                    }
                }
                .padding(16)
            }
        }
    }

    private func options(_ text: ForkAmbientStrings) -> some View {
        let shortcut = GlobalShortcut(storageValue: shortcutRaw) ?? Logic.defaultShortcut
        let island = Binding(get: { Logic.isShownInIsland(hiddenControls) },
                             set: { hiddenControls = Logic.hiddenControls(hiddenControls, showing: $0) })
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(text.optionsTitle)
            ForkCareCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(text.pauseForCalls, isOn: $pauseForCalls)
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(text.pauseForMusic, isOn: $pauseForMusic)
                        Text(text.pauseForMusicCaption).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                    }
                    Divider().overlay(Color.careVeil(0.1))
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(text.inIsland, isOn: island)
                        Text(text.inIslandCaption).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle(text.islandWave, isOn: $islandWave)
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(text.islandScenes, isOn: $islandScenes)
                        Text(text.islandScenesCaption).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .disabled(!islandWave)
                    Toggle(text.menuBarIcon, isOn: $menuBarIcon)
                    HStack {
                        Toggle(text.shortcut, isOn: $shortcutEnabled)
                        Spacer()
                        ShortcutRecorderButton(shortcut: shortcut,
                                               isEnabled: shortcutEnabled,
                                               waitingTitle: l10n.s.shortcutPressKeys,
                                               invalidAction: { shortcutError = l10n.s.shortcutInvalid },
                                               captureAction: { captured in
                                                   shortcutRaw = captured.storageValue
                                                   shortcutError = nil
                                               })
                            .frame(width: 140, height: 24)
                    }
                    if let shortcutError { ForkCareNotice(text: shortcutError) }
                    if player.shortcutTaken { ForkCareNotice(text: text.shortcutTaken) }
                    Text(text.pausesOnLock).font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .foregroundStyle(Color.carePrimary)
                .padding(16)
            }
        }
    }
}

/// An ambience or favourite to pick: its symbol and name, lit when it plays.
struct ForkAmbientChoiceTile: View {
    let symbol: String
    let title: String
    let chosen: Bool
    var compact = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        let glow = Color(care: ForkCareLogic.glow(.ambient))
        Button(action: action) {
            VStack(spacing: compact ? 6 : 8) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 15 : 18, weight: .semibold))
                    .foregroundStyle(chosen ? Color.carePrimary : Color.careTint(.ambient))
                    .frame(width: compact ? 32 : 40, height: compact ? 32 : 40)
                    .background(Circle().fill(chosen ? glow.opacity(0.5) : glow.opacity(0.14)))
                Text(title)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(Color.carePrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, compact ? 10 : 14)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Color.careFill(chosen ? 0.16 : (hovered ? 0.11 : 0.07)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(chosen ? glow.opacity(0.9) : Color.careVeil(0.1), lineWidth: chosen ? 1.5 : 1))
            .scaleEffect(hovered ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.easeOut(duration: 0.2), value: chosen)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// MARK: - Panel under the menu bar

/// The dark panel the menu bar icon opens: play and pause with a breathing
/// button, the ambiences and favourites as tiles, every sound one click away,
/// the volume, the timer or Pomodoro, and the way to the window.
struct ForkAmbientPanelView: View {
    typealias Logic = ForkAmbientLogic
    @ObservedObject var player: ForkAmbientPlayer
    @AppStorage(DefaultsKey.forkAmbientTimer) private var timer = 0
    @AppStorage(DefaultsKey.forkAmbientMode) private var modeRaw = Logic.Mode.timer.rawValue
    @AppStorage(DefaultsKey.forkAmbientPomodoroMinutes) private var pomodoroMinutes = 25

    @Environment(\.colorScheme) private var scheme
    private var glow: Color { Color(care: ForkCareLogic.glow(.ambient)) }

    var body: some View {
        let text = ForkAmbientStrings.current
        let stops = scheme == .dark ? ForkCareLogic.gradient(.ambient) : ForkCareLogic.lightGradient(.ambient)
        VStack(alignment: .leading, spacing: 14) {
            header(text)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Logic.Preset.allCases) { preset in
                    ForkAmbientChoiceTile(symbol: preset.symbol, title: text.preset(preset),
                                          chosen: player.preset == preset, compact: true) { player.apply(preset) }
                }
            }
            if !player.favorites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(player.favorites) { favorite in
                            let chosen = player.favorite?.id == favorite.id
                            Button { player.apply(favorite) } label: {
                                Label(favorite.name, systemImage: chosen ? "star.fill" : "star")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.carePrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.careFill(chosen ? 0.2 : 0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            sounds(text)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(Color.careSecondary)
                Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1)
                    .controlSize(.small)
                    .tint(Color.careTint(.ambient))
                    .accessibilityLabel(text.volume)
            }
            session(text)
            Button { player.openWindow() } label: {
                HStack {
                    Text(text.open).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                }
                .foregroundStyle(Color.careSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: ForkAmbientPanel.size.width, height: ForkAmbientPanel.size.height, alignment: .top)
        .background(
            LinearGradient(colors: [Color(care: stops.top), Color(care: stops.bottom)], startPoint: .top, endPoint: .bottom)
                .overlay(RadialGradient(colors: [glow.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 260))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.careVeil(0.14), lineWidth: 1))
        .environment(\.forkCareTool, .ambient)
    }

    private func header(_ text: ForkAmbientStrings) -> some View {
        HStack(spacing: 14) {
            ForkCareRoundButton(title: player.playing ? text.pause : text.play, diameter: 76) { player.toggle() }
            VStack(alignment: .leading, spacing: 4) {
                Text(text.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.carePrimary)
                HStack(spacing: 6) {
                    ForkAmbientWave(active: player.audible, color: Color.careTint(.ambient), height: 12)
                    Text(text.status(player))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.careSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sounds(_ text: ForkAmbientStrings) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(Logic.Sound.allCases) { sound in
                let on = player.mix[sound] != nil
                Button { player.toggleSound(sound) } label: {
                    Image(systemName: sound.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.carePrimary : Color.careSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? glow.opacity(0.5) : Color.careVeil(0.08)))
                        .overlay(Circle().stroke(on ? glow.opacity(0.9) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text.sound(sound))
                .accessibilityAddTraits(on ? .isSelected : [])
                .screenshotSafeHelp(text.sound(sound))
            }
        }
    }

    private func session(_ text: ForkAmbientStrings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(text.modeTitle, selection: Binding(get: { Logic.Mode(rawValue: modeRaw) ?? .timer },
                                                      set: { player.setMode($0) })) {
                Text(text.timerMode).tag(Logic.Mode.timer)
                Text(text.pomodoroMode).tag(Logic.Mode.pomodoro)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            if Logic.Mode(rawValue: modeRaw) == .pomodoro {
                Picker(text.workLength, selection: Binding(get: { pomodoroMinutes }, set: { player.setPomodoro(minutes: $0) })) {
                    ForEach(Logic.pomodoroChoices, id: \.self) { Text("\(text.workLength) \(text.minutes($0))").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            } else {
                Picker(text.timer, selection: Binding(get: { timer }, set: { player.setTimer(minutes: $0) })) {
                    ForEach(Logic.timerChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? text.never : text.minutes(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
        }
    }
}

// MARK: - The island

/// The island's control: a click plays and pauses, a long press opens the
/// window; a wave moves on it while the sound plays. Drawn like upstream's
/// tiles, placed by one line in its island controls.
struct ForkAmbientIslandTile: View {
    let service: NotchService
    @ObservedObject private var player = ForkAmbientPlayer.shared

    var body: some View {
        let text = ForkAmbientStrings.current
        let glow = Color(care: ForkCareLogic.glow(.ambient))
        let reading = player.remaining.map(ForkAmbientLogic.clock)
        Button { service.select(.ambient) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(player.playing ? glow.opacity(0.45) : Color.white.opacity(0.075))
                    if player.playing {
                        ForkAmbientWave(active: player.audible, bars: 4, color: .white, height: 16)
                    } else {
                        Image(systemName: ForkAmbientLogic.islandSymbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 40, height: 40)
                VStack(spacing: 1) {
                    if let reading {
                        Text(reading).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                    }
                    Text(text.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(reading == nil ? 1 : 0.7))
                        .lineLimit(reading == nil ? 2 : 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28, alignment: .top)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.shortcutHeight)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            service.perform { ForkAmbientWindow.shared.show() }
        })
        .accessibilityLabel(text.title)
        .accessibilityValue(text.status(player))
        .accessibilityAddTraits(player.playing ? .isSelected : [])
    }
}

/// What the closed island reads on its right: the time left, when there is one.
enum ForkAmbientIsland {
    static func reading(language: AppLanguage, now: Date = Date()) -> String? {
        ForkAmbientPlayer.shared.endDate.map {
            NotchKeepAwakeSupport.compactText(until: $0, now: now, locale: Locale(identifier: language.rawValue))
        }
    }
}

/// The closed island while the sound plays: the moving wave left of the
/// camera, against the island's edge, and the time left on the right. The
/// wings fit the wider side (`ForkAmbientLogic.stripWing`), so without a time
/// limit the island narrows to the wave; both sides open the island's
/// controls, where the tile is.
struct ForkAmbientStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var player = ForkAmbientPlayer.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.forkAmbientScenes) private var scenes = true

    var body: some View {
        NotchStripHold(player.endDate, shows: player.playing) { end in
            TimelineView(.periodic(from: Date(), by: 30)) { context in strip(end: end, now: context.date) }
        }
        // A scene is wider than the wave: the wings follow.
        .onChange(of: scenes) { _, _ in DispatchQueue.main.async { service.refreshPresentation() } }
    }

    private func strip(end: Date?, now: Date) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let glow = Color(care: ForkCareLogic.glow(.ambient))
        return Button { service.openActivity(NotchCompactActivity.ambient.module) } label: {
            // Each side keeps its width even when empty: a modifier on an empty
            // Group draws nothing, which centred the wave alone in the island.
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear
                    if wing >= 28 {
                        ForkAmbientMark(color: glow, height: iconSize)
                            .padding(.leading, geometry.compactActivityEdgeInset(
                                boxHeight: iconSize, radius: ForkAmbientLogic.markRadius(height: iconSize, scenes: scenes)))
                    }
                }
                .frame(width: wing, height: height)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                ZStack(alignment: .trailing) {
                    Color.clear
                    if wing >= 42, let end {
                        let text = NotchKeepAwakeSupport.compactText(until: end, now: now,
                                                                     locale: Locale(identifier: l10n.language.rawValue))
                        Text(text)
                            .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                                DispatchQueue.main.async { service.refreshPresentation() }
                            }
                    }
                }
                .frame(width: wing, height: height)
            }
            .foregroundStyle(glow)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ForkAmbientStrings.current.title)
        .accessibilityValue(ForkAmbientStrings.current.status(player))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// The same in the island's capsule look.
struct ForkAmbientCapsuleStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var player = ForkAmbientPlayer.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NotchStripHold(player.endDate, shows: player.playing) { end in
            TimelineView(.periodic(from: Date(), by: 30)) { context in row(end: end, now: context.date) }
        }
    }

    private func row(end: Date?, now: Date) -> some View {
        let glow = Color(care: ForkCareLogic.glow(.ambient))
        let geometry = displayGeometry ?? service.geometry
        // The capsule's own row is private to upstream's file: the same
        // arrangement, centred in the size the service measured.
        return HStack(spacing: 6) {
            ForkAmbientMark(color: glow, height: 13)
            if let end {
                Text(NotchKeepAwakeSupport.compactText(until: end, now: now, locale: Locale(identifier: l10n.language.rawValue)))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(glow)
                    .lineLimit(1).fixedSize()
            }
        }
        .frame(width: size.width, height: geometry.stripHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ForkAmbientStrings.current.title)
        .accessibilityValue(ForkAmbientStrings.current.status(player))
    }
}

/// The background sound's own page in the island: play and the volume at
/// the top, the ambiences, then each sound playing with its own level and
/// the others a tap away. The full window keeps favourites and options.
struct ForkAmbientIslandPage: View {
    typealias Logic = ForkAmbientLogic
    let size: CGSize
    @ObservedObject private var player = ForkAmbientPlayer.shared

    private var glow: Color { Color(care: ForkCareLogic.glow(.ambient)) }

    var body: some View {
        let text = ForkAmbientStrings.current
        let active = Logic.Sound.allCases.filter { player.mix[$0] != nil }
        let others = Logic.Sound.allCases.filter { player.mix[$0] == nil }
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header(text)
                presets(text)
                if !active.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 8) {
                        ForEach(active) { level($0, text) }
                    }
                }
                if !others.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(others) { sound in
                                Button { player.toggleSound(sound) } label: {
                                    Label(text.sound(sound), systemImage: sound.symbol)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: size.width, height: size.height)
    }

    private func header(_ text: ForkAmbientStrings) -> some View {
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(glow.opacity(player.playing ? 0.55 : 0.25)))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 19))
            .accessibilityLabel(player.playing ? text.pause : text.play)
            VStack(alignment: .leading, spacing: 3) {
                Text(Logic.preset(for: player.mix).map(text.preset) ?? text.custom)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForkAmbientMark(color: glow, height: 13)
                    Text(text.status(player))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            NotchLevelSlider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }),
                             label: text.volume, tint: glow)
                .frame(width: 130, height: 22)
            Button { player.openWindow() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 13))
            .accessibilityLabel(text.open)
        }
    }

    private func presets(_ text: ForkAmbientStrings) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Logic.Preset.allCases) { preset in
                    let chosen = Logic.preset(for: player.mix) == preset
                    Button { player.apply(preset) } label: {
                        Label(text.preset(preset), systemImage: preset.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(chosen ? Color.white : Color.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(chosen ? glow.opacity(0.5) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func level(_ sound: Logic.Sound, _ text: ForkAmbientStrings) -> some View {
        HStack(spacing: 8) {
            Image(systemName: sound.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(glow)
                .frame(width: 16)
            Text(text.sound(sound))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            NotchLevelSlider(value: Binding(get: { player.mix[sound] ?? 0 }, set: { player.setLevel($0, for: sound) }),
                             label: text.sound(sound), tint: glow)
                .frame(height: 20)
            Button { player.toggleSound(sound) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text.sound(sound))
        }
    }
}
