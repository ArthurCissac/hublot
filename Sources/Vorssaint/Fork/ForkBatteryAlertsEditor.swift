// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// Lot 8, Juicy's alert editor: one list for the Mac's low alerts, one for
/// its charge alerts, one for the devices. Each alert is a row (its colour,
/// its threshold, where and how it shows) that opens to set its threshold,
/// colour, place, sound, halo and whether it waits for a click, with a button
/// to try it. Up to five alerts per list.
struct ForkBatteryAlertsEditor: View {
    typealias Rules = ForkBatteryAlertRules

    @AppStorage(DefaultsKey.forkBatteryAlertRules) private var stored = ""
    @State private var open: UUID?
    let text: ForkBatteryStrings

    var body: some View {
        let rules = Rules.decode(stored)
        VStack(alignment: .leading, spacing: 14) {
            list(text.lowAlerts, caption: text.lowAlertsCaption, symbol: "battery.25percent", tint: .red,
                 target: .mac, kinds: [.low], rules: rules)
            list(text.chargedAlerts, caption: text.chargedAlertsCaption, symbol: "battery.100percent.bolt", tint: .green,
                 target: .mac, kinds: [.charged], rules: rules)
            list(text.deviceAlerts, caption: text.deviceAlertsCaption, symbol: "iphone", tint: .blue,
                 target: .device, kinds: [.low, .charged], rules: rules)
        }
    }

    private func list(_ title: String, caption: String, symbol: String, tint: Color, target: Rules.Target,
                      kinds: [Rules.Kind], rules: [Rules.Rule]) -> some View {
        let mine = rules.filter { $0.target == target && kinds.contains($0.kind) }
            .sorted { $0.kind == $1.kind ? ($0.kind == .low ? $0.percent > $1.percent : $0.percent < $1.percent) : $0.kind == .low }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                ForEach(kinds, id: \.self) { kind in
                    if rules.filter({ $0.target == target && $0.kind == kind }).count < Rules.maxRulesPerList {
                        Button {
                            let rule = Rules.newRule(target: target, kind: kind, after: rules)
                            save(rules + [rule])
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open = rule.id }
                        } label: {
                            Label(kinds.count > 1 ? text.kindName(kind) : text.addAlert, systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(mine.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Divider() }
                    row(rule, rules: rules)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    private func row(_ rule: Rules.Rule, rules: [Rules.Rule]) -> some View {
        let isOpen = open == rule.id
        let tint = ForkBatteryTintPalette.color(rule.tint)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForkBatteryPillIcon(icon: rule.kind == .charged ? .bolt : .battery(percent: rule.percent), tint: tint, scale: 0.6)
                Text("\(rule.percent) %")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.18)))
                    .foregroundStyle(tint)
                Text(summary(rule)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Toggle("", isOn: binding(rule, rules: rules, \.enabled)).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open = isOpen ? nil : rule.id }
            }
            if isOpen {
                details(rule, rules: rules, tint: tint)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .opacity(rule.enabled ? 1 : 0.55)
    }

    private func details(_ rule: Rules.Rule, rules: [Rules.Rule], tint: Color) -> some View {
        let range = Rules.range(for: rule.kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.level).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { Double(rule.percent) },
                                      set: { value in update(rule, rules: rules) { $0.percent = Int(value.rounded()) } }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .tint(tint)
            }
            HStack {
                Text(text.colorLabel).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                ForEach(Rules.Tint.allCases, id: \.self) { option in
                    Button {
                        update(rule, rules: rules) { $0.tint = option }
                    } label: {
                        Circle()
                            .fill(ForkBatteryTintPalette.color(option))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(rule.tint == option ? 0.9 : 0), lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(text.tintName(option))
                }
                Spacer()
            }
            HStack {
                Text(text.position).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Picker("", selection: binding(rule, rules: rules, \.position)) {
                    ForEach(Rules.Position.allCases, id: \.self) { Text(text.positionName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Text(text.sound).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                ForkSoundPicker(selection: binding(rule, rules: rules, \.sound),
                                fallback: rule.kind == .charged ? .hublot(.charged) : .hublot(.low), text: text)
            }
            Toggle(text.glow, isOn: binding(rule, rules: rules, \.glow)).font(.caption)
            Toggle(text.sticky, isOn: binding(rule, rules: rules, \.sticky)).font(.caption)
            HStack {
                Button {
                    ForkBatteryAlerts.shared.preview(rule)
                } label: {
                    Label(text.test, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.small)
                Spacer()
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        save(rules.filter { $0.id != rule.id })
                        open = nil
                    }
                } label: {
                    Label(text.delete, systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.leading, 4)
    }

    private func summary(_ rule: Rules.Rule) -> String {
        var parts: [String] = []
        if rule.target == .device { parts.append(text.kindName(rule.kind)) }
        parts.append(text.positionName(rule.position))
        if rule.glow { parts.append(text.glowShort) }
        parts.append(rule.sound == "none" ? text.soundOff : text.sound)
        if rule.sticky { parts.append(text.stickyShort) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saving

    private func save(_ rules: [Rules.Rule]) {
        stored = Rules.encode(rules)
    }

    private func update(_ rule: Rules.Rule, rules: [Rules.Rule], _ change: (inout Rules.Rule) -> Void) {
        save(rules.map { candidate in
            guard candidate.id == rule.id else { return candidate }
            var next = candidate
            change(&next)
            return Rules.clamped(next)
        })
    }

    private func binding<Value>(_ rule: Rules.Rule, rules: [Rules.Rule],
                                _ keyPath: WritableKeyPath<Rules.Rule, Value>) -> Binding<Value> {
        Binding(get: { rule[keyPath: keyPath] }, set: { value in update(rule, rules: rules) { $0[keyPath: keyPath] = value } })
    }
}

/// A sound to choose: nothing, one of Hublot's, a macOS alert sound or an
/// imported one, with a button to hear it and one to import a file.
struct ForkSoundPicker: View {
    typealias Panel = ForkBatteryPanelLogic

    @Binding var selection: String
    let fallback: Panel.SoundChoice
    let text: ForkBatteryStrings
    @ObservedObject private var sounds = ForkBatterySounds.shared
    @State private var refused = false

    var body: some View {
        let choice = sounds.choice(selection, fallback: fallback)
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { choice.stored }, set: { selection = $0 })) {
                Text(text.soundNone).tag(Panel.SoundChoice.none.stored)
                Section(text.soundHublot) {
                    ForEach(ForkBatteryLogic.Sound.allCases, id: \.self) { sound in
                        Text(text.hublotSoundName(sound)).tag(Panel.SoundChoice.hublot(sound).stored)
                    }
                }
                if !sounds.importedNames.isEmpty {
                    Section(text.mySounds) {
                        ForEach(sounds.importedNames, id: \.self) { name in
                            Text((name as NSString).deletingPathExtension).tag(Panel.SoundChoice.file(name).stored)
                        }
                    }
                }
                Section(text.soundMacOS) {
                    ForEach(AlertSoundStrings.sortedNames(sounds.systemNames, language: L10n.shared.language), id: \.self) { name in
                        Text(AlertSoundStrings.displayName(for: name, language: L10n.shared.language))
                            .tag(Panel.SoundChoice.system(name).stored)
                    }
                }
            }
            .labelsHidden()
            Button {
                sounds.play(choice)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .disabled(choice == .none)
            .help(text.listen)
            Button {
                var wasRefused = false
                if let imported = sounds.importSound(refused: &wasRefused) { selection = imported }
                refused = wasRefused
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help(text.importSound)
        }
        .alert(text.importRefused, isPresented: $refused) {
            Button("OK", role: .cancel) {}
        }
    }
}
