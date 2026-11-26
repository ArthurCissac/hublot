// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The AI page in Hublot's style: a widget per kind of information (rings
/// for the limits, a figure and its hours for spending, bars for the week,
/// a split bar for the models, a calendar for the activity, a banner for a
/// session waiting), on a grid sized to the island so nothing scrolls. Edit,
/// in the island's top row, shows or hides widgets in place. Cards the
/// style does not draw (added accounts, Codex resets) keep upstream's look.
/// Upstream's page is untouched; the switch is in the AI page's settings.
/// The layout is `ForkAgentLayoutLogic`.
final class ForkAgentEditing: ObservableObject {
    static let shared = ForkAgentEditing()
    @Published var agents = false
    @Published var explorer = false
}

struct ForkAgentGrid<Fallback: View>: View {
    typealias Logic = ForkAgentLayoutLogic
    let tiles: [NotchAgentTile]
    let size: CGSize
    let now: Date
    let period: AgentPeriod
    let display: NotchAgentLimitDisplay
    @ViewBuilder let fallback: (NotchAgentTile) -> Fallback
    @ObservedObject private var editing = ForkAgentEditing.shared
    @ObservedObject private var usage = AgentUsageService.shared

    var body: some View {
        Group {
            if editing.agents {
                ForkAgentCardPicker()
            } else {
                grid
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .notchBand(trailing: { ForkEditButton(on: $editing.agents) })
    }

    private var grid: some View {
        let shown = Logic.widgetTiles(tiles)
        let columns = Logic.columns(width: size.width)
        let rows = Logic.rows(Logic.items(shown, columns: columns), columns: columns)
        let heights = Logic.rowHeights(rows, available: size.height)
        let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let unit = (size.width - Logic.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return VStack(spacing: Logic.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: Logic.spacing) {
                    ForEach(row, id: \.id) { item in
                        if let tile = byID[item.id] {
                            widget(tile)
                                .frame(width: unit * CGFloat(item.span) + Logic.spacing * CGFloat(item.span - 1),
                                       height: heights[index])
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func widget(_ tile: NotchAgentTile) -> some View {
        let snapshot = usage.snapshot
        switch tile.card {
        case .limits where tile.accountID == nil && tile.provider != nil:
            ForkLimitsWidget(provider: tile.provider ?? .claude, snapshot: snapshot, now: now, display: display)
        case .spend: ForkSpendWidget(snapshot: snapshot, period: period)
        case .live: ForkLiveWidget(snapshot: snapshot, now: now)
        case .trend: ForkTrendWidget(snapshot: snapshot)
        case .models: ForkModelsWidget(snapshot: snapshot, period: period)
        case .activity: ForkActivityWidget(snapshot: snapshot)
        case .projects: ForkProjectsWidget(snapshot: snapshot, period: period)
        case .forkWaiting: ForkWaitingBanner()
        case .forkResume: ForkAgentCard(card: .forkResume, period: period, snapshot: snapshot)
        default: fallback(tile)
        }
    }
}

// MARK: - Editing

struct ForkEditButton: View {
    @Binding var on: Bool

    var body: some View {
        let text = ForkAgentWidgetStrings.current
        // The pencil alone; its name stays for the pointer's help and VoiceOver.
        Button { on.toggle() } label: {
            Image(systemName: on ? "checkmark" : "pencil")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(Circle().fill(Color.white.opacity(on ? 0.22 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(on ? text.done : text.edit)
        .accessibilityLabel(on ? text.done : text.edit)
    }
}

/// Every card of the page, lit when shown; a click shows or hides it.
private struct ForkAgentCardPicker: View {
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hidden = ""
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let hiddenSet = Set(hidden.split(separator: ",").map(String.init))
        VStack(alignment: .leading, spacing: 10) {
            Text(ForkAgentWidgetStrings.current.agentsHint).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            ForkChipGrid(items: NotchAgentSupport.orderedCards().map { card in
                ForkChip(id: card.rawValue, symbol: card.symbol, title: text.card(card), on: !hiddenSet.contains(card.rawValue))
            }) { id in
                var set = hiddenSet
                if set.contains(id) { set.remove(id) } else { set.insert(id) }
                hidden = NotchAgentCard.allCases.map(\.rawValue).filter(set.contains).joined(separator: ",")
            }
        }
        .padding(.top, 2)
        .onDisappear { ForkAgentEditing.shared.agents = false }
    }
}

/// Explorer's pages, lit when Explorer shows them; a click shows or hides one there.
struct ForkExplorerPicker: View {
    let modules: [NotchModule]
    @AppStorage(DefaultsKey.forkExplorerHidden) private var hidden = ""
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let set = ForkAgentLayoutLogic.hidden(hidden)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ForkAgentWidgetStrings.current.explorerHint).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 6)
                ForkEditButton(on: Binding(get: { ForkAgentEditing.shared.explorer }, set: { ForkAgentEditing.shared.explorer = $0 }))
            }
            ForkChipGrid(items: modules.map { module in
                ForkChip(id: module.rawValue, symbol: module.symbol, title: module.title(l10n.language), on: !set.contains(module.rawValue))
            }) { id in
                var next = set
                if next.contains(id) { next.remove(id) } else { next.insert(id) }
                hidden = ForkAgentLayoutLogic.stored(next)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear { ForkAgentEditing.shared.explorer = false }
    }
}

/// The pencil beside Explorer's tiles.
struct ForkExplorerEditButton: View {
    @ObservedObject private var editing = ForkAgentEditing.shared

    var body: some View {
        Button { editing.explorer = true } label: {
            Image(systemName: "pencil").font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.8))
        .help(ForkAgentWidgetStrings.current.edit)
        .accessibilityLabel(ForkAgentWidgetStrings.current.edit)
    }
}

struct ForkChip: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let on: Bool
}

private struct ForkChipGrid: View {
    let items: [ForkChip]
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 6)], spacing: 6) {
            ForEach(items) { chip in
                Button { toggle(chip.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: chip.symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14)
                        Text(chip.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: chip.on ? "eye" : "eye.slash").font(.system(size: 10))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white.opacity(chip.on ? 0.95 : 0.4))
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(chip.on ? 0.12 : 0.04)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chip.on ? .isSelected : [])
            }
        }
    }
}

// MARK: - The widgets

private let forkClay = AgentProvider.claude.tint

private struct ForkWidgetHeader: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(tint).frame(width: 12)
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// Rings for the session and the longer window, filled with what is used
/// or left as the page shows limits, a tick where even spending would be.
private struct ForkLimitsWidget: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    @Environment(\.locale) private var locale
    @ObservedObject private var l10n = L10n.shared

    private var windows: [AgentLimitWindow] {
        let all = (snapshot.limits[provider]?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session }.max { $0.usedPercent < $1.usedPercent }
        return [session, longer].compactMap { $0 }
    }

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 4) {
                ForkWidgetHeader(title: provider.displayName + (snapshot.plans[provider].map { " · " + $0.name } ?? ""),
                                 symbol: NotchAgentCard.limits.symbol, tint: provider.tint)
                if windows.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    GeometryReader { proxy in
                        let side = max(20, min(proxy.size.height - 13, proxy.size.width / CGFloat(windows.count) - 8))
                        HStack(spacing: 0) {
                            ForEach(windows) { window in
                                VStack(spacing: 2) {
                                    ring(window, side: side)
                                    Text(caption(window, text: text)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }

    private func ring(_ window: AgentLimitWindow, side: CGFloat) -> some View {
        let used = display == .used
        let fraction = used ? window.usedFraction : window.remainingFraction
        let pace = AgentLimitSupport.pace(for: window, now: now).map { used ? $0.elapsed : 1 - $0.elapsed }
        let tint = agentLimitTint(provider, usedFraction: window.usedFraction)
        let line = max(3, side / 9)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: line)
            Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let pace, pace > 0.02, pace < 0.98 {
                Capsule().fill(Color.white.opacity(0.9))
                    .frame(width: 1.5, height: line + 3)
                    .offset(y: -side / 2)
                    .rotationEffect(.degrees(pace * 360))
            }
            Text(AgentFormat.percent(fraction)).font(.system(size: max(9, side / 4.2), weight: .semibold)).monospacedDigit()
        }
        .frame(width: side, height: side)
    }

    private func caption(_ window: AgentLimitWindow, text: NotchAgentStrings) -> String {
        let name = window.kind == .session ? text.session : text.weekly
        guard let reset = AgentLimitSupport.displayedReset(window, now: now) else { return name }
        let seconds = reset.timeIntervalSince(now)
        return name + " · " + AgentFormat.duration(max(60, seconds), locale: locale, units: 1)
    }
}

/// The period's figure, and its hours or days as small bars.
private struct ForkSpendWidget: View {
    let snapshot: AgentUsageSnapshot
    let period: AgentPeriod
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let total = snapshot.usage(period).total
        let buckets = period == .today ? snapshot.hours : Array(snapshot.days.suffix(period.days))
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 3) {
                ForkWidgetHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol)
                Text(AgentFormat.cost(total.cost)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                ForkBars(values: buckets.map { $0.total.cost }, highlightLast: true)
            }
        }
    }
}

private struct ForkBars: View {
    let values: [Double]
    var highlightLast = false

    var body: some View {
        let peak = max(values.max() ?? 0, .leastNonzeroMagnitude)
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: values.count > 14 ? 1 : 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(highlightLast && index == values.count - 1 ? forkClay : forkClay.opacity(0.55))
                        .frame(height: max(2, proxy.size.height * value / peak))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Each turn at work: its agent, project, time and cost. A click opens its session.
private struct ForkLiveWidget: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ForkWidgetHeader(title: text.liveCard, symbol: NotchAgentCard.live.symbol)
                    if !snapshot.live.isEmpty { NotchAgentPulse(tint: forkClay, size: 5) }
                }
                if snapshot.live.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.live.prefix(2)) { turn in
                        Button { ForkClaudeSessions.shared.open(turn) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    NotchAgentMark(provider: turn.provider, size: 11, tint: turn.provider.tint)
                                    Text(turn.project.isEmpty ? turn.provider.displayName : turn.project)
                                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 2)
                                    Text(elapsed(turn)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(forkClay)
                                }
                                Text([turn.model, AgentFormat.cost(turn.cost)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(ForkAgentCardsStrings.current.openSession(turn.project))
                    }
                }
            }
        }
    }

    private func elapsed(_ turn: AgentLiveSession) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(turn.started)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The last seven days as bars, today lit, and the daily average.
private struct ForkTrendWidget: View {
    let snapshot: AgentUsageSnapshot
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let week = Array(snapshot.days.suffix(7)).map { $0.total.cost }
        let average = week.isEmpty ? 0 : week.reduce(0, +) / Double(week.count)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 4) {
                ForkWidgetHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol)
                ForkBars(values: week, highlightLast: true)
                Text(ForkAgentWidgetStrings.current.perDay(AgentFormat.cost(average)))
                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// The models' shares as one split bar, the first ones named.
private struct ForkModelsWidget: View {
    let snapshot: AgentUsageSnapshot
    let period: AgentPeriod
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let usage = snapshot.usage(period)
        let shares = Array(usage.models.prefix(4))
        let weights = shares.map { $0.totals.weight(byCost: usage.fullyPriced) }
        let total = max(weights.reduce(0, +), .leastNonzeroMagnitude)
        let shades: [Double] = [1, 0.7, 0.45, 0.28]
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                ForkWidgetHeader(title: text.modelsCard, symbol: NotchAgentCard.models.symbol)
                if shares.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    GeometryReader { proxy in
                        HStack(spacing: 1.5) {
                            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                                Rectangle().fill(forkClay.opacity(shades[index]))
                                    .frame(width: max(2, proxy.size.width * weight / total))
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(shares.prefix(2).enumerated()), id: \.offset) { index, share in
                            HStack(spacing: 4) {
                                Circle().fill(forkClay.opacity(shades[index])).frame(width: 6, height: 6)
                                Text(share.name).font(.system(size: 10)).lineLimit(1)
                                Spacer(minLength: 2)
                                Text(AgentFormat.percent(weights[index] / total)).font(.system(size: 10)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The last thirteen weeks, a square a day, darker for a busier day.
private struct ForkActivityWidget: View {
    let snapshot: AgentUsageSnapshot
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let days = Array(snapshot.days.suffix(91)).map { $0.total.cost }
        let peak = max(days.max() ?? 0, .leastNonzeroMagnitude)
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 4) {
                ForkWidgetHeader(title: text.activityCard, symbol: NotchAgentCard.activity.symbol)
                GeometryReader { proxy in
                    let cell = max(3, min((proxy.size.width - CGFloat(max(0, weeks.count - 1)) * 2) / CGFloat(max(1, weeks.count)),
                                          (proxy.size.height - 12) / 7))
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 2) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, value in
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(value <= 0 ? Color.white.opacity(0.07) : forkClay.opacity(0.25 + 0.75 * value / peak))
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Time and cost per project in the period: one widget for both.
private struct ForkProjectsWidget: View {
    let snapshot: AgentUsageSnapshot
    let period: AgentPeriod
    @ObservedObject private var time = ForkAgentTime.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let times = Dictionary((time.periods[period] ?? []).map { ($0.project, $0.seconds) }, uniquingKeysWith: +)
        let costs = Dictionary(snapshot.usage(period).projects.map { ($0.name, $0.totals.cost) }, uniquingKeysWith: +)
        let names = Set(times.keys).union(costs.keys).sorted {
            let left = times[$0] ?? 0, right = times[$1] ?? 0
            return left != right ? left > right : (costs[$0] ?? 0) > (costs[$1] ?? 0)
        }
        let shown = Array(names.prefix(3))
        let peak = max(shown.map { times[$0] ?? 0 }.max() ?? 0, 1)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 4) {
                ForkWidgetHeader(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol)
                if shown.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    ForEach(shown, id: \.self) { name in
                        // A click opens the project's most recent Claude Code session.
                        Button { ForkClaudeSessions.shared.openProject(named: name) } label: { HStack(spacing: 8) {
                            Text(name).font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                .frame(width: 92, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(Color.white.opacity(0.1))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(forkClay).frame(width: max(3, proxy.size.width * (times[name] ?? 0) / peak))
                                    }
                            }
                            .frame(height: 4)
                            Text(ForkClaudeSessionsLogic.duration(times[name] ?? 0)).font(.system(size: 10, weight: .semibold))
                                .monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                            Text(AgentFormat.cost(costs[name] ?? 0)).font(.system(size: 10)).monospacedDigit()
                                .foregroundStyle(.secondary).frame(minWidth: 46, alignment: .trailing)
                        }
                        .frame(height: 14)
                        .contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .help(ForkAgentCardsStrings.current.openLatest(name))
                    }
                }
            }
        }
    }
}

/// A session waiting for an answer, across the page; a click opens it.
private struct ForkWaitingBanner: View {
    @ObservedObject private var sessions = ForkClaudeSessions.shared

    var body: some View {
        let text = ForkAgentCardsStrings.current
        let first = sessions.waiting.first
        Button { if let first { sessions.goTo(first) } } label: {
            HStack(spacing: 7) {
                Image(systemName: ForkClaudeSessionsLogic.noticeSymbol).font(.system(size: 11, weight: .semibold))
                Text(first.map { [text.waitingTitle, $0.name, text.reason(ForkClaudeSessionsLogic.wait($0.waitingFor))]
                    .joined(separator: " · ") } ?? text.nobodyWaits)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                if sessions.waiting.count > 1 {
                    Text("+\(sessions.waiting.count - 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange.opacity(0.8))
                }
                Spacer(minLength: 4)
                Text(ForkAgentWidgetStrings.current.goThere)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.23, green: 0.14, blue: 0.03))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
            }
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.16)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

/// The style's switch and Explorer's, with the AI page's cards.
struct ForkAgentStyleRows: View {
    @AppStorage(DefaultsKey.forkAgentsHublotStyle) private var style = true
    @AppStorage(DefaultsKey.forkExplorerFitsAll) private var explorer = true

    var body: some View {
        let text = ForkAgentWidgetStrings.current
        VStack(alignment: .leading, spacing: 8) {
            ForkOptionRow(symbol: "square.grid.3x2", title: text.styleTitle, caption: text.styleCaption) {
                Toggle(text.styleTitle, isOn: $style).labelsHidden().toggleStyle(.switch)
            }
            ForkOptionRow(symbol: "square.grid.2x2", title: text.explorerTitle, caption: text.explorerCaption) {
                Toggle(text.explorerTitle, isOn: $explorer).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
