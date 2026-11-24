// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Lot 9: the disk map's layout and the antivirus's reading of ClamAV.
enum ForkDiskToolsTests {
    static func run(_ suite: TestSuite) {
        diskMap(suite)
        antivirus(suite)
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkCleanerTools] as? Bool == true,
                     "the disk map and the antivirus are offered by default")
    }

    private static func diskMap(_ suite: TestSuite) {
        typealias Logic = ForkDiskMapLogic
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Logic.squarify(sizes, in: rect)
        let total = sizes.reduce(0, +)
        var areasMatch = true
        for (size, frame) in zip(sizes, rects) where abs(Double(frame.width * frame.height) - size / total * 240_000) > 1 {
            areasMatch = false
        }
        suite.expect(rects.count == sizes.count && areasMatch, "each rectangle's area is its share of the whole")
        suite.expect(rects.allSatisfy { rect.insetBy(dx: -0.5, dy: -0.5).contains($0) }, "all inside the map")
        var overlaps = false
        for i in rects.indices { for j in rects.indices where i < j && rects[i].insetBy(dx: 0.5, dy: 0.5).intersects(rects[j].insetBy(dx: 0.5, dy: 0.5)) { overlaps = true } }
        suite.expect(!overlaps, "and none on top of another")
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? .infinity
        suite.expect(worst < 3, "squarish shapes, easy to compare")
        suite.expect(Logic.squarify([], in: rect).isEmpty && Logic.squarify([0, 0], in: rect) == [.zero, .zero],
                     "nothing to lay out, nothing drawn")

        let shown = Logic.shown(sizes: [10, 500, 1, 300, 2], limit: 2)
        suite.expect(shown.indices == [1, 3] && shown.rest == 13,
                     "a folder shows its largest items, the rest gathered as one")
        let tiny = Logic.shown(sizes: [10_000, 1], limit: 60, minimumShare: 0.01)
        suite.expect(tiny.indices == [0] && tiny.rest == 1, "items too small to see join the rest")
    }

    private static func antivirus(_ suite: TestSuite) {
        typealias Logic = ForkAntivirusLogic
        suite.expect(Logic.parse("/Users/a/Downloads/eicar.com: Win.Test.EICAR_HDB-1 FOUND")
            == .threat(path: "/Users/a/Downloads/eicar.com", signature: "Win.Test.EICAR_HDB-1"),
                     "a threat is read with its file and its name")
        suite.expect(Logic.parse("/Users/a/Documents/a: b.txt: OK") == .clean(path: "/Users/a/Documents/a: b.txt")
            && Logic.parse("/Users/a/x: Some.Sig FOUND") == .threat(path: "/Users/a/x", signature: "Some.Sig"),
                     "a colon in a file name does not confuse it")
        suite.expect(Logic.parse("----------- SCAN SUMMARY -----------") == .other
            && Logic.parse("/Users/a/locked: Permission denied. ERROR") == .other,
                     "the summary and errors are neither clean nor threats")

        let exists: (String) -> Bool = { $0 == "/opt/homebrew/bin/brew" || $0 == "/usr/local/bin/clamscan" }
        suite.expect(Logic.brew(existing: exists) == "/opt/homebrew/bin/brew"
            && Logic.tool("clamscan", existing: exists) == "/usr/local/bin/clamscan"
            && Logic.tool("freshclam", existing: exists) == nil,
                     "Homebrew and ClamAV are found where Homebrew puts them")
        suite.expect(Logic.databaseDirectory(forTool: "/usr/local/bin/clamscan") == "/usr/local/var/lib/clamav"
            && Logic.configDirectory(forTool: "/opt/homebrew/bin/freshclam") == "/opt/homebrew/etc/clamav",
                     "signatures and settings sit under the same prefix as the tools")
        suite.expect(Logic.freshclamConfig(fromSample: "# comment\nExample\nDatabaseMirror database.clamav.net\n")
            == "# comment\nDatabaseMirror database.clamav.net\n",
                     "the working freshclam settings are the sample without its Example line")

        let now = Date(timeIntervalSince1970: 1_000_000)
        suite.expect(Logic.signaturesAreStale(updated: nil, now: now)
            && Logic.signaturesAreStale(updated: now.addingTimeInterval(-90_000), now: now)
            && !Logic.signaturesAreStale(updated: now.addingTimeInterval(-3_600), now: now),
                     "signatures older than a day are refreshed before a scan")

        let recent = Logic.recentApps([("/Applications/New.app", now.addingTimeInterval(-86_400)),
                                       ("/Applications/Old.app", now.addingTimeInterval(-40 * 86_400))], now: now)
        let targets = Logic.quickTargets(home: "/Users/a", recentApps: recent)
        suite.expect(recent == ["/Applications/New.app"] && targets.contains("/Users/a/Downloads")
            && targets.contains("/Library/LaunchDaemons") && targets.last == "/Applications/New.app",
                     "the quick scan covers downloads, what starts by itself, and apps added this month")

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        suite.expect(Logic.quarantinePath(for: "/Users/a/Downloads/bad.dmg", id: id, in: "/Q")
            == "/Q/00000000-0000-0000-0000-000000000001/bad.dmg",
                     "each file set aside gets a folder of its own")
    }
}
