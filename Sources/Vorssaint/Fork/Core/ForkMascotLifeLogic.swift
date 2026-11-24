// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// A livelier companion (`forkMascotLively`): now and then at rest it does
/// something (stretches, yawns, whistles, blows a bubble, reads, does
/// push-ups, looks around), its visits take one of several ways through the
/// island, and its mood follows how often it is petted. Pure: which activity
/// comes, how a visit's path is reshaped, where the mood stands.
enum ForkMascotLifeLogic {
    // MARK: - Idle activities

    enum Activity: String, CaseIterable {
        case stretch, yawn, whistle, bubble, book, pushUps, lookAround

        /// How long it lasts; blinks wait meanwhile.
        var duration: TimeInterval {
            switch self {
            case .stretch: return 1.6
            case .yawn: return 1.4
            case .whistle: return 2.2
            case .bubble: return 2.0
            case .book: return 3.6
            case .pushUps: return 2.4
            case .lookAround: return 2.0
            }
        }
    }

    /// At most one activity this often, so it stays a surprise.
    static let spacing: TimeInterval = 40
    /// After a blink, the chance that an activity comes, once spacing allows.
    static let chance = 0.16
    /// The last activities played are not played again soon.
    static let memory = 3

    /// The activity to play after a blink at rest, or nil. `random` draws
    /// whether one comes, `pick` which of those allowed.
    static func nextActivity(now: TimeInterval, last: TimeInterval?, recent: [Activity],
                             random: Double, pick: Double) -> Activity? {
        if let last, now - last < spacing { return nil }
        guard random < chance else { return nil }
        let allowed = Activity.allCases.filter { !recent.suffix(memory).contains($0) }
        guard !allowed.isEmpty else { return nil }
        let index = min(allowed.count - 1, Int(pick * Double(allowed.count)))
        return allowed[max(0, index)]
    }

    // MARK: - Visits

    enum VisitStyle: String, CaseIterable {
        /// Upstream's own stroll, kept in the rotation.
        case stroll
        /// Little hops all the way.
        case hops
        /// It waits, dashes across, then slows down.
        case dash
        /// Out only a little way to peek, then back (a round trip only).
        case peek
        /// A bouncy zigzag, eyes going left and right.
        case zigzag
    }

    /// The way a visit goes, the same for every drawing of one visit.
    static func visitStyle(id: UUID, roundTrip: Bool) -> VisitStyle {
        let styles = VisitStyle.allCases.filter { roundTrip || $0 != .peek }
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let seed = bytes.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        return styles[seed % styles.count]
    }

    /// The path reshaped for `style`, keeping its length, its start and its
    /// end, so the island's timing and hiding stay as they were. `rest` is
    /// where it rests, for a peek; `size` is the companion's.
    static func reshape(_ path: NotchMascotPath, style: VisitStyle, size: CGFloat, rest: CGFloat) -> NotchMascotPath {
        guard path.keyTimes.count == path.x.count, path.x.count > 2,
              path.lift.count == path.x.count, path.gaze.count == path.x.count else { return path }
        var out = path
        let times = path.keyTimes
        // Only the middle moves differently: the ends stay where the island expects them.
        func inner(_ t: Double) -> Double { min(1, max(0, (t - 0.06) / 0.88)) }
        switch style {
        case .stroll:
            return path
        case .hops:
            for i in out.lift.indices {
                let t = inner(times[i])
                let hop = abs(sin(Double.pi * 7 * t))
                out.lift[i] += CGFloat(hop * (t > 0 && t < 1 ? 1 : 0)) * size * 0.3
            }
        case .zigzag:
            for i in out.lift.indices {
                let t = inner(times[i])
                let wave = (1 - cos(2 * Double.pi * 4 * t)) / 2
                out.lift[i] += CGFloat(wave) * size * 0.14
                out.gaze[i] += CGFloat(sin(2 * Double.pi * 3 * t)) * 0.12
            }
        case .peek:
            for i in out.x.indices { out.x[i] = rest + (path.x[i] - rest) * 0.4 }
        case .dash:
            for i in out.x.indices {
                let warped = dashTime(times[i])
                out.x[i] = sample(path.x, at: warped, times: times)
                out.lift[i] = sample(path.lift, at: warped, times: times)
            }
        }
        return out
    }

    /// Slow out, fast across, slow in: 0 → 0 and 1 → 1, never going back.
    static func dashTime(_ t: Double) -> Double {
        if t < 0.3 { return 0.5 * t }
        if t < 0.7 { return 0.15 + (t - 0.3) * 1.75 }
        return 0.85 + (t - 0.7) * 0.5
    }

    static func sample(_ values: [CGFloat], at t: Double, times: [Double]) -> CGFloat {
        guard let first = values.first else { return 0 }
        guard t > (times.first ?? 0) else { return first }
        for i in 1..<min(values.count, times.count) where times[i] >= t {
            let span = times[i] - times[i - 1]
            let share = span > 0 ? (t - times[i - 1]) / span : 1
            return values[i - 1] + (values[i] - values[i - 1]) * CGFloat(share)
        }
        return values.last ?? first
    }

    // MARK: - Mood

    /// How much it has been petted lately, from 0 to 100. A pat adds, time
    /// without one takes away.
    static let pat: Double = 14
    static let decayPerHour: Double = 3

    static func affection(_ stored: Double, since updated: Date?, now: Date) -> Double {
        guard let updated else { return 50 }
        let hours = max(0, now.timeIntervalSince(updated) / 3600)
        return min(100, max(0, stored - hours * decayPerHour))
    }

    static func petted(_ affection: Double) -> Double { min(100, affection + pat) }

    /// The face it keeps at rest: glad when petted a lot, looking around for
    /// you when left alone a long while; otherwise the island's own.
    static func restingMood(base: NotchMascotMood, affection: Double) -> NotchMascotMood {
        guard base == .idle else { return base }
        if affection >= 75 { return .happy }
        if affection <= 15 { return .searching }
        return .idle
    }

    /// Activities come at rest, glad or not.
    static func actsIn(_ mood: NotchMascotMood) -> Bool { mood == .idle || mood == .happy }

    // MARK: - Eyes on the pointer

    /// How far around the island the eyes follow the pointer, in points.
    static let gazeReach: CGFloat = 260
    /// Faster than this toward it, within startle reach, and it jumps.
    static let startleSpeed: CGFloat = 2400
    static let startleReach: CGFloat = 70

    static func follows(distance: CGFloat) -> Bool { distance <= gazeReach }

    static func startles(distance: CGFloat, approachSpeed: CGFloat) -> Bool {
        distance <= startleReach && approachSpeed >= startleSpeed
    }
}
