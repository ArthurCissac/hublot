// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The tasks' colour in the closed island: a soft coral, not Todoist's own;
/// green for the task being done, as in the list.
private let forkTodoistTint = Color(red: 0.98, green: 0.52, blue: 0.42)

private func forkTodoistMarkTint(doing: Bool) -> Color { doing ? .green : forkTodoistTint }

/// The words read out for the strip: what it is, then the task.
private func forkTodoistSpoken(_ todoist: ForkTodoist) -> String {
    let text = ForkTodoistStrings.current
    return [todoist.islandDoing ? text.doing : todoist.islandMark, todoist.islandReading]
        .compactMap { $0 }.joined(separator: ", ")
}

/// The closed island while a task is due there (`forkTodoistIslandActivity`):
/// the one being done, or one with a time near it. The list's mark and the
/// task's time left of the camera, its title on the right. A click opens the
/// tasks' page; the wings fit the wider side (`ForkTodoistLogic.stripWing`),
/// within the calendar's bounds.
struct ForkTodoistStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var todoist = ForkTodoist.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let text = ForkTodoistStrings.current
        Button { service.openActivity(NotchCompactActivity.tasks.module) } label: {
            // Each side keeps its width even when empty, as the timer's do.
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear
                    if wing >= 28 {
                        HStack(spacing: ForkTodoistLogic.markSpacing) {
                            Image(systemName: ForkTodoistLogic.islandSymbol)
                                .font(.system(size: iconSize * 0.78, weight: .semibold))
                                .frame(width: iconSize, height: iconSize)
                            if let time = todoist.islandMark {
                                Text(time)
                                    .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            }
                        }
                        .foregroundStyle(forkTodoistMarkTint(doing: todoist.islandDoing))
                        .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                    }
                }
                .frame(width: wing, height: height)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                ZStack(alignment: .trailing) {
                    Color.clear
                    if wing >= 42, let title = todoist.islandReading {
                        Text(title)
                            .font(.system(size: textSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1).truncationMode(.tail)
                            .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                    }
                }
                .frame(width: wing, height: height)
            }
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.title)
        .accessibilityValue(forkTodoistSpoken(todoist))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// The same in the island's capsule look: the mark and time, then the task.
struct ForkTodoistCapsuleStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var todoist = ForkTodoist.shared

    var body: some View {
        let geometry = displayGeometry ?? service.geometry
        let text = ForkTodoistStrings.current
        // The capsule's own row is private to upstream's file: the same
        // arrangement, centred in the size the service measured.
        HStack(spacing: 6) {
            Image(systemName: ForkTodoistLogic.islandSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(forkTodoistMarkTint(doing: todoist.islandDoing))
            if let time = todoist.islandMark {
                Text(time)
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(forkTodoistMarkTint(doing: todoist.islandDoing))
            }
            if let title = todoist.islandReading {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: size.width, height: geometry.stripHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.title)
        .accessibilityValue(forkTodoistSpoken(todoist))
    }
}
