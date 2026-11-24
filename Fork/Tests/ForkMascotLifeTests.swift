// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The livelier companion: which idle activity comes, how a visit is
/// reshaped without changing its ends, and how its mood follows petting.
enum ForkMascotLifeTests {
    typealias Logic = ForkMascotLifeLogic

    static func run(_ suite: TestSuite) {
        activities(suite)
        visits(suite)
        mood(suite)
    }

    private static func activities(_ suite: TestSuite) {
        suite.expect(Logic.nextActivity(now: 100, last: 80, recent: [], random: 0, pick: 0) == nil
            && Logic.nextActivity(now: 100, last: nil, recent: [], random: 0.9, pick: 0) == nil
            && Logic.nextActivity(now: 100, last: nil, recent: [], random: 0, pick: 0) == .stretch,
                     "an activity comes now and then, never within forty seconds of the last")
        let recent: [Logic.Activity] = [.stretch, .yawn, .whistle]
        var seen = Set<Logic.Activity>()
        for step in 0..<20 {
            if let next = Logic.nextActivity(now: 1000, last: nil, recent: recent, random: 0, pick: Double(step) / 20) {
                seen.insert(next)
            }
        }
        suite.expect(seen.isDisjoint(with: recent) && seen.count == Logic.Activity.allCases.count - recent.count,
                     "the last three activities are not played again soon; every other one can come")
        suite.expect(Logic.Activity.allCases.allSatisfy { $0.duration >= 1 && $0.duration <= 4 },
                     "each activity lasts a few seconds")
    }

    private static func path(count: Int = 61) -> NotchMascotPath {
        var path = NotchMascotPath()
        path.keyTimes = (0..<count).map { Double($0) / Double(count - 1) }
        path.x = path.keyTimes.map { CGFloat(20 + 100 * sin(Double.pi * $0)) }
        path.lift = Array(repeating: 0, count: count)
        path.squash = Array(repeating: 0, count: count)
        path.gaze = Array(repeating: 0, count: count)
        path.duration = 3.6
        return path
    }

    private static func visits(_ suite: TestSuite) {
        let base = path()
        var endsKept = true
        for style in Logic.VisitStyle.allCases {
            let shaped = Logic.reshape(base, style: style, size: 16, rest: 20)
            if shaped.duration != base.duration || shaped.keyTimes != base.keyTimes
                || abs((shaped.x.first ?? 0) - (base.x.first ?? 0)) > 0.01 || abs((shaped.x.last ?? 0) - (base.x.last ?? 0)) > 0.01
                || abs(shaped.lift.first ?? 1) > 0.01 || abs(shaped.lift.last ?? 1) > 0.01 {
                endsKept = false
            }
        }
        suite.expect(endsKept, "every way of visiting keeps the visit's length, start and end")
        let hops = Logic.reshape(base, style: .hops, size: 16, rest: 20)
        let peek = Logic.reshape(base, style: .peek, size: 16, rest: 20)
        suite.expect((hops.lift.max() ?? 0) > 3 && (peek.x.max() ?? 0) < (base.x.max() ?? 0) - 30,
                     "hops lift it up along the way; a peek goes only a little way out")
        suite.expect(Logic.dashTime(0) == 0 && abs(Logic.dashTime(1) - 1) < 0.000_001
            && Logic.dashTime(0.5) > 0.4 && Logic.dashTime(0.2) < 0.2,
                     "a dash waits, crosses fast, then slows down, from start to end")

        let id = UUID()
        suite.expect(Logic.visitStyle(id: id, roundTrip: true) == Logic.visitStyle(id: id, roundTrip: true)
            && (0..<40).allSatisfy { _ in Logic.visitStyle(id: UUID(), roundTrip: false) != .peek },
                     "one visit always takes the same way; only a round trip can be a peek")
        let styles = Set((0..<200).map { _ in Logic.visitStyle(id: UUID(), roundTrip: true) })
        suite.expect(styles.count == Logic.VisitStyle.allCases.count, "visits vary between every way")
    }

    private static func mood(_ suite: TestSuite) {
        let now = Date()
        suite.expect(Logic.affection(80, since: now.addingTimeInterval(-10 * 3600), now: now) == 50
            && Logic.affection(10, since: now.addingTimeInterval(-24 * 3600), now: now) == 0
            && Logic.affection(42, since: nil, now: now) == 50
            && Logic.petted(95) == 100,
                     "petting raises its affection, time alone lowers it, within 0 and 100")
        suite.expect(Logic.restingMood(base: .idle, affection: 90) == .happy
            && Logic.restingMood(base: .idle, affection: 5) == .searching
            && Logic.restingMood(base: .idle, affection: 50) == .idle
            && Logic.restingMood(base: .alert, affection: 90) == .alert,
                     "petted a lot it rests glad, left alone it looks for you; the island's own faces stay")
        suite.expect(Logic.actsIn(.idle) && Logic.actsIn(.happy) && !Logic.actsIn(.sleepy) && !Logic.actsIn(.alert),
                     "activities come only at rest, glad or not")
        suite.expect(Logic.follows(distance: 200) && !Logic.follows(distance: 400)
            && Logic.startles(distance: 50, approachSpeed: 3000) && !Logic.startles(distance: 50, approachSpeed: 500)
            && !Logic.startles(distance: 150, approachSpeed: 3000),
                     "the eyes follow the pointer around the island; only a pointer rushing at it close by makes it jump")
    }
}
