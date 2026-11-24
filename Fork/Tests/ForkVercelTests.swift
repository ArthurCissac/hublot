// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Vercel in the island: the address asked, the answer read, what changed
/// between two looks, how often it asks, and what the island says.
enum ForkVercelTests {
    typealias Logic = ForkVercelLogic

    private static let sample = """
    {"deployments": [
      {"uid": "dpl_new", "name": "site-pily", "url": "site-pily-abc.vercel.app", "state": "BUILDING",
       "target": "production", "created": 1800000000000, "buildingAt": 1800000005000,
       "inspectorUrl": "https://vercel.com/arthur/site-pily/abc"},
      {"uid": "dpl_preview", "name": "nexflow", "url": "nexflow-git-x.vercel.app", "readyState": "READY",
       "target": null, "created": 1799999000000, "inspectorUrl": "vercel.com/arthur/nexflow/def"},
      {"uid": "dpl_odd", "name": "barflow", "state": "SOMETHING_NEW", "created": 1799990000000}
    ], "pagination": {"count": 3}}
    """

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.deploymentsURL()?.absoluteString == "https://api.vercel.com/v6/deployments?limit=12"
            && Logic.deploymentsURL(limit: 500)?.absoluteString.hasSuffix("limit=50") == true,
                     "the latest deployments are asked of Vercel's API, a bounded number")
        let all = Logic.deployments(from: Data(sample.utf8)) ?? []
        suite.expect(all.count == 3 && all[0].state == .building && all[1].state == .ready && all[2].state == .unknown
            && all[0].isProduction && !all[1].isProduction,
                     "deployments are read, state or readyState alike; an unknown state is not a failure")
        suite.expect(Logic.deployments(from: Data("{}".utf8)) == nil
            && Logic.deployments(from: Data(repeating: 32, count: Logic.maximumSize + 1)) == nil,
                     "anything else, or too large, is refused")
        suite.expect(Logic.followed(all, scope: .production).map(\.uid) == ["dpl_new"] && Logic.followed(all, scope: .all).count == 3,
                     "production only, or every deployment")
        suite.expect(Logic.building(all)?.uid == "dpl_new" && Logic.building(Array(all.dropFirst())) == nil,
                     "the newest one still building is the one shown")

        let before: [String: Logic.State] = ["dpl_new": .building, "dpl_preview": .building, "dpl_odd": .queued]
        let after = [
            Logic.Deployment(uid: "dpl_new", name: "site-pily", url: nil, state: .ready, target: "production", created: 1),
            Logic.Deployment(uid: "dpl_preview", name: "nexflow", url: nil, state: .error, target: nil, created: 1),
            Logic.Deployment(uid: "dpl_odd", name: "barflow", url: nil, state: .canceled, target: nil, created: 1),
            Logic.Deployment(uid: "dpl_old", name: "old", url: nil, state: .ready, target: nil, created: 1),
        ]
        suite.expect(Logic.finished(previous: before, current: after).map(\.uid) == ["dpl_new", "dpl_preview"]
            && Logic.finished(previous: nil, current: after).isEmpty,
                     "a build that ended online or failed is told once; a cancelled one, an old one or the first look say nothing")
        suite.expect(Logic.snapshot(all)["dpl_new"] == .building,
                     "each look keeps where every deployment stood")
        suite.expect(Logic.pollInterval(building: true) == 5 && Logic.pollInterval(building: false) == 60,
                     "every five seconds during a build, every minute otherwise")

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        suite.expect(Logic.elapsed(since: start, now: start.addingTimeInterval(42)) == "0:42"
            && Logic.elapsed(since: start, now: start.addingTimeInterval(72)) == "1:12"
            && Logic.elapsed(since: start, now: start.addingTimeInterval(723)) == "12:03"
            && Logic.elapsed(since: start, now: start.addingTimeInterval(-5)) == "0:00",
                     "the time building reads as minutes and seconds")
        suite.expect(all[0].started == Date(timeIntervalSince1970: 1_800_000_005) && all[2].started == Date(timeIntervalSince1970: 1_799_990_000),
                     "the time runs from the build's start, or from its creation")
        let long = Logic.Deployment(uid: "x", name: String(repeating: "a", count: 40), url: nil, state: .building, target: nil, created: 0)
        suite.expect(Logic.islandName(all[0]) == "site-pily" && Logic.islandName(long).count == Logic.nameLimit
            && Logic.islandName(long).hasSuffix("…"),
                     "long project names are shortened for the strip")

        suite.expect(Logic.inspectorURL(all[0])?.absoluteString == "https://vercel.com/arthur/site-pily/abc"
            && Logic.inspectorURL(all[1])?.absoluteString == "https://vercel.com/arthur/nexflow/def"
            && Logic.inspectorURL(Logic.Deployment(uid: "y", name: "n", url: nil, state: .ready, target: nil, created: 0,
                                                   inspectorUrl: "https://evil.example/vercel.com")) == nil,
                     "a click opens the deployment's page, only ever on vercel.com")
        suite.expect(Logic.siteURL(all[0])?.absoluteString == "https://site-pily-abc.vercel.app"
            && Logic.siteURL(Logic.Deployment(uid: "z", name: "n", url: "a/b", state: .ready, target: nil, created: 0)) == nil,
                     "the site's own address is https")
        suite.expect(Logic.cleanToken("  abcdefGHIJ1234567890  ") == "abcdefGHIJ1234567890"
            && Logic.cleanToken("vcp_AbC123def456GHI789-x.y") == "vcp_AbC123def456GHI789-x.y"
            && Logic.cleanToken("short") == nil && Logic.cleanToken("has spaces in the middle 123") == nil
            && Logic.cleanToken("abcdefGHIJ1234567890é") == nil && Logic.cleanToken("abcdefGHIJ12345678/90") == nil
            && Logic.cleanToken(String(repeating: "a", count: 300)) == nil,
                     "a pasted token is trimmed; anything that cannot be one is refused")
        suite.expect(Logic.isNotice(symbol: Logic.successSymbol) && Logic.isNotice(symbol: Logic.failureSymbol)
            && !Logic.isNotice(symbol: Logic.islandSymbol),
                     "only the ended build's notices open Vercel")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkVercelEnabled] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkVercelScope] as? String == Logic.Scope.all.rawValue,
                     "on, for every deployment, once a token is given")
    }
}
