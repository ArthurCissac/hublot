// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Today's tasks, the form and the done tasks, shared by the island's page
/// and the panel. Semantic colours only, so the island's dark and the
/// panel's material both read well. A click on a task unfolds its actions
/// (do it now, edit, delete, open in Todoist); the round ticks it.
struct ForkTodoistBoard: View {
    typealias Logic = ForkTodoistLogic
    enum Screen: Equatable { case list, form(ForkTodoistLogic.Item?), done }

    var compact = false
    var focusOnAppear = false
    let openInTodoist: (ForkTodoistLogic.Item) -> Void
    @ObservedObject private var model = ForkTodoist.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var screen = Screen.list
    @State private var quick = ""
    @State private var expanded: String?
    @FocusState private var quickFocused: Bool
    /// Ticked a moment ago: the round fills and the title is struck before it goes.
    @State private var ticking: Set<String> = []
    /// Just added: the row glows green a moment.
    @State private var fresh: Set<String> = []
    /// The tasks there were when an add was sent, to tell the new one.
    @State private var addedFrom: Set<String>?
    @State private var plusTurns = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1) }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch screen {
            case .list:
                list
            case .form(let task):
                ForkTodoistForm(task: task, seed: task == nil ? quick : "") { saved in
                    withAnimation(motion) { screen = .list }
                    if saved, task == nil { quick = "" }
                }
            case .done:
                doneList
            }
            if let deleted = model.deleted {
                undoBanner(deleted)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(motion, value: model.deleted?.id)
        .onAppear { if focusOnAppear { quickFocused = true } }
        .onChange(of: model.tasks.map(\.id)) { _, ids in glowAdded(ids) }
    }

    // MARK: - The list

    private var list: some View {
        let text = ForkTodoistStrings.current
        let board = ForkTodoistBoardStrings.current
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: addQuick) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.red)
                        .opacity(canAdd ? 1 : 0.55)
                        .rotationEffect(.degrees(Double(plusTurns) * 90))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .accessibilityLabel(board.add)
                TextField("", text: $quick, prompt: Text(text.addPlaceholder))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($quickFocused)
                    .onSubmit(addQuick)
                if model.adding { ProgressView().controlSize(.small) }
                iconButton("slider.horizontal.3", label: board.moreOptions) { withAnimation(motion) { screen = .form(nil) } }
                iconButton("clock.arrow.circlepath", label: board.doneTitle) { withAnimation(motion) { screen = .done } }
                Text(verbatim: "\(model.tasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                iconButton("arrow.clockwise", label: text.refresh, spinning: model.loading) { model.refresh() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
            .help(text.addHint)
            if let problem = model.problem {
                Label(text.problem(problem), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if model.tasks.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: model.loading ? "hourglass" : "checkmark.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(model.loading ? text.loading : text.nothing)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.tasks) { row($0) }
                    }
                    .animation(motion, value: model.tasks.map(\.id))
                    .padding(.bottom, model.deleted == nil ? 4 : 48)
                }
            }
        }
    }

    private var canAdd: Bool {
        !model.adding && !quick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addQuick() {
        let text = quick
        guard canAdd else { return }
        addedFrom = Set(model.tasks.map(\.id))
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6)) { plusTurns += 1 }
        model.add(text) { ok in
            if ok { quick = "" } else { addedFrom = nil }
        }
    }

    /// The task an add brought in glows a moment, then settles.
    private func glowAdded(_ ids: [String]) {
        guard let before = addedFrom else { return }
        let new = Set(ids).subtracting(before)
        guard !new.isEmpty else { return }
        addedFrom = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { fresh.formUnion(new) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeOut(duration: 0.6)) { fresh.subtract(new) }
        }
    }

    /// The round fills with a tick and the title is struck, then the row goes.
    private func tick(_ item: Logic.Item) {
        guard !ticking.contains(item.id) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        guard !reduceMotion else { return model.complete(item) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { _ = ticking.insert(item.id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(motion) { model.complete(item) }
            ticking.remove(item.id)
        }
    }

    private func row(_ item: Logic.Item) -> some View {
        let board = ForkTodoistBoardStrings.current
        let text = ForkTodoistStrings.current
        let active = model.activeID == item.id
        let open = expanded == item.id
        let tint = ForkTodoistPanelView.colour(item.level)
        let ticked = ticking.contains(item.id)
        let glowing = fresh.contains(item.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    tick(item)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(tint, lineWidth: 2)
                            .background(Circle().fill(ticked ? tint : tint.opacity(item.level < 4 ? 0.14 : 0)))
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .scaleEffect(ticked ? 1 : 0.2)
                            .opacity(ticked ? 1 : 0)
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(ticked)
                .accessibilityLabel(text.complete(item.content))
                VStack(alignment: .leading, spacing: 4) {
                    if active {
                        Label(board.inProgress, systemImage: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    Text(item.content)
                        .font(.system(size: compact ? 14.5 : 15, weight: .medium))
                        .strikethrough(ticked, color: .secondary)
                        .foregroundStyle(ticked ? .secondary : .primary)
                        .lineLimit(open ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    meta(item)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(motion) { expanded = open ? nil : item.id } }
            if open {
                if let notes = item.description, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 34)
                }
                HStack(spacing: 6) {
                    chip(active ? board.stopDoing : board.doing, active ? "pause.fill" : "play.fill", tint: .green) {
                        withAnimation(motion) {
                            model.setActive(active ? nil : item)
                            expanded = nil
                        }
                    }
                    chip(board.edit, "pencil") { withAnimation(motion) { screen = .form(item) } }
                    chip(board.delete, "trash", tint: .red) {
                        withAnimation(motion) {
                            model.delete(item)
                            expanded = nil
                        }
                    }
                    Spacer(minLength: 0)
                    iconButton("arrow.up.forward.app", label: board.openInTodoist) { openInTodoist(item) }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(glowing ? Color.green.opacity(0.24)
                : active ? Color.green.opacity(0.13) : Color.primary.opacity(open ? 0.08 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.green.opacity(glowing ? 0.6 : active ? 0.45 : 0)))
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)))
    }

    /// Urgency, lateness, time, repetition and project, under the title.
    @ViewBuilder
    private func meta(_ item: Logic.Item) -> some View {
        let board = ForkTodoistBoardStrings.current
        let late = Logic.isOverdue(item, today: Logic.dayString(Date()))
        let project = item.projectID.flatMap { id in model.projects.first { $0.id == id && !$0.isInbox }?.name }
        if item.level < 4 || late || item.due?.time != nil || item.due?.isRecurring == true || project != nil {
            HStack(spacing: 10) {
                if item.level < 4 {
                    Text(verbatim: "P\(item.level)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(ForkTodoistPanelView.colour(item.level))
                }
                if late, let day = item.due?.day {
                    Label("\(board.late) · \(shortDay(day))", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.red)
                }
                if let time = item.due?.time { Label(time, systemImage: "clock") }
                if item.due?.isRecurring == true { Label(item.due?.string ?? "", systemImage: "repeat").lineLimit(1) }
                if let project { Label(project, systemImage: "number").lineLimit(1) }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Done tasks

    private var doneList: some View {
        let board = ForkTodoistBoardStrings.current
        let groups = Logic.doneByDay(model.done)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { withAnimation(motion) { screen = .list } } label: {
                    Label(board.back, systemImage: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(board.doneTitle).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                if model.loadingDone { ProgressView().controlSize(.small) } else { iconButton("arrow.clockwise", label: board.doneTitle) { model.loadDone() } }
            }
            .padding(.horizontal, 4)
            if groups.isEmpty {
                Text(model.loadingDone ? ForkTodoistStrings.current.loading : board.doneEmpty)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(groups.indices, id: \.self) { index in
                            Text(dayTitle(groups[index].day))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, index == 0 ? 0 : 8)
                                .padding(.leading, 4)
                            ForEach(groups[index].tasks) { doneRow($0) }
                        }
                    }
                }
            }
        }
        .onAppear { model.loadDone() }
    }

    private func doneRow(_ item: Logic.Item) -> some View {
        let board = ForkTodoistBoardStrings.current
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(.system(size: 14))
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let at = doneTime(item) {
                    Text(at).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 6)
            chip(board.reopen, "arrow.uturn.backward") { withAnimation(motion) { model.reopen(item) } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Undo

    private func undoBanner(_ item: Logic.Item) -> some View {
        let board = ForkTodoistBoardStrings.current
        return HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text(board.deleted).font(.system(size: 13, weight: .semibold))
            Text(item.content).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Button(board.undo) { withAnimation(motion) { model.undoDelete() } }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    // MARK: - Pieces

    private func iconButton(_ symbol: String, label: String, spinning: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
                .animation(spinning && !reduceMotion ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func chip(_ title: String, _ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill((tint ?? Color.primary).opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var locale: Locale { Locale(identifier: l10n.language.rawValue) }

    /// « 21 nov. »
    private func shortDay(_ day: String) -> String {
        guard let date = Logic.dayDate(day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    /// Today, yesterday, or the day written out.
    private func dayTitle(_ day: String) -> String {
        let board = ForkTodoistBoardStrings.current
        let now = Date()
        if day == Logic.dayString(now) { return board.today }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now), day == Logic.dayString(yesterday) {
            return board.yesterday
        }
        guard let date = Logic.dayDate(day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date).capitalized(with: locale)
    }

    /// When a done task was ticked, in the Mac's zone.
    private func doneTime(_ item: Logic.Item) -> String? {
        guard let stamp = item.completedAt, stamp.count >= 19 else { return nil }
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime]
        guard let moment = reader.date(from: String(stamp.prefix(19)) + "Z") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter.string(from: moment)
    }
}

/// Making or changing a task: title, notes, urgency, day, time, repetition
/// and project, with chips rather than menus (a menu opens poorly in the
/// island's window).
struct ForkTodoistForm: View {
    typealias Logic = ForkTodoistLogic
    let task: ForkTodoistLogic.Item?
    let seed: String
    let close: (Bool) -> Void
    @ObservedObject private var model = ForkTodoist.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ForkTodoistLogic.Draft()
    @State private var ready = false
    @FocusState private var titleFocused: Bool

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today) ?? today }

    var body: some View {
        let board = ForkTodoistBoardStrings.current
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { close(false) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(board.cancel)
                Text(task == nil ? board.newTask : board.editTask)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                if model.saving { ProgressView().controlSize(.small) }
                Button(task == nil ? board.add : board.save, action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(!draft.isValid || model.saving)
            }
            if let problem = model.problem, !model.saving {
                Label(ForkTodoistStrings.current.problem(problem), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("", text: $draft.content, prompt: Text(board.titlePlaceholder))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .focused($titleFocused)
                        .onSubmit(save)
                        .padding(10)
                        .background(field)
                    TextField("", text: $draft.description, prompt: Text(board.notesPlaceholder), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(2...5)
                        .padding(10)
                        .background(field)
                    section(board.urgency) { urgency(board) }
                    section(board.date) { dates(board) }
                    section(board.time) { time }
                    section(board.repeatTitle) { repetition(board) }
                    if !model.projects.isEmpty { section(board.project) { projects(board) } }
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            model.loadProjects()
            guard !ready else { return }
            ready = true
            draft = task.map { Logic.draft(for: $0) } ?? Logic.Draft(content: seed)
            titleFocused = true
        }
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func urgency(_ board: ForkTodoistBoardStrings) -> some View {
        HStack(spacing: 6) {
            ForEach(1...4, id: \.self) { level in
                let chosen = draft.level == level
                let tint = ForkTodoistPanelView.colour(level)
                Button { draft.level = level } label: {
                    HStack(spacing: 5) {
                        Image(systemName: chosen ? "flag.fill" : "flag").foregroundStyle(tint)
                        Text(verbatim: "P\(level)").font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(chosen ? tint.opacity(0.22) : Color.primary.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(chosen ? tint.opacity(0.6) : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(board.urgencyNames[level - 1])
                .accessibilityLabel(board.urgencyNames[level - 1])
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    private func dates(_ board: ForkTodoistBoardStrings) -> some View {
        HStack(spacing: 6) {
            option(board.noDate, chosen: draft.day == nil) { setDay(nil) }
            option(board.today, chosen: draft.day.map { calendar.isDate($0, inSameDayAs: today) } ?? false) { setDay(today) }
            option(board.tomorrow, chosen: draft.day.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false) { setDay(tomorrow) }
            DatePicker("", selection: Binding(get: { draft.day ?? today }, set: { setDay($0) }), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .fixedSize()
        }
    }

    private var time: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { draft.minutes != nil }, set: { on in
                let hour = min(23, calendar.component(.hour, from: Date()) + 1)
                draft.minutes = on ? hour * 60 : nil
                if on, draft.day == nil { draft.day = today }
                draft.dueChanged = true
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            if draft.minutes != nil {
                DatePicker("", selection: Binding(get: {
                    calendar.date(byAdding: .minute, value: draft.minutes ?? 0, to: today) ?? today
                }, set: { value in
                    let parts = calendar.dateComponents([.hour, .minute], from: value)
                    draft.minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    draft.dueChanged = true
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .fixedSize()
            }
        }
    }

    private func repetition(_ board: ForkTodoistBoardStrings) -> some View {
        let choices: [Logic.Repeat] = [.never, .daily, .weekly(defaultDays), .monthly, .yearly]
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(choices.indices, id: \.self) { index in
                        option(board.repeatNames[index], chosen: same(draft.repeats, choices[index])) {
                            draft.repeats = choices[index]
                            draft.dueChanged = true
                        }
                    }
                }
            }
            if case .weekly(let days) = draft.repeats {
                HStack(spacing: 5) {
                    ForEach(Logic.Weekday.week, id: \.self) { day in
                        option(weekdayName(day), chosen: days.contains(day)) {
                            var next = days
                            if next.contains(day) { next.remove(day) } else { next.insert(day) }
                            if !next.isEmpty { draft.repeats = .weekly(next) }
                            draft.dueChanged = true
                        }
                    }
                }
            }
            if let task, task.due?.isRecurring == true, !draft.dueChanged, let wording = task.due?.string {
                Text(board.currentRepeat(wording)).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }

    private func projects(_ board: ForkTodoistBoardStrings) -> some View {
        let inbox = model.projects.first(where: \.isInbox)?.id
        let chosen = draft.projectID ?? inbox
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.projects) { project in
                    option(project.isInbox ? board.inbox : project.name, chosen: chosen == project.id) {
                        draft.projectID = project.id
                    }
                }
            }
        }
    }

    private func option(_ title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(chosen ? Color.red.opacity(0.85) : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The chosen day's weekday, for a weekly repetition just picked.
    private var defaultDays: Set<Logic.Weekday> {
        Set([Logic.Weekday(rawValue: calendar.component(.weekday, from: draft.day ?? today)) ?? .monday])
    }

    private func same(_ a: Logic.Repeat, _ b: Logic.Repeat) -> Bool {
        switch (a, b) {
        case (.weekly, .weekly): return true
        default: return a == b
        }
    }

    private func weekdayName(_ day: Logic.Weekday) -> String {
        var names = Calendar(identifier: .gregorian)
        names.locale = Locale(identifier: l10n.language.rawValue)
        let symbols = names.shortStandaloneWeekdaySymbols
        return symbols.indices.contains(day.rawValue - 1) ? symbols[day.rawValue - 1] : day.english
    }

    private func setDay(_ day: Date?) {
        draft.day = day.map { calendar.startOfDay(for: $0) }
        if day == nil { draft.minutes = nil }
        draft.dueChanged = true
    }

    private func save() {
        guard draft.isValid, !model.saving else { return }
        if let task {
            model.update(task, to: draft) { ok in if ok { close(true) } }
        } else {
            model.create(draft) { ok in if ok { close(true) } }
        }
    }
}
