// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Hublot's updates: the repository read from the fork's address, Hublot's own
/// version numbers against its release tags, and a changelog section for the
/// version about to be built.
enum ForkUpdateTests {
    private static func candidate(_ tag: String, pre: Bool = false) -> UpdateServiceSupport.ReleaseCandidate {
        UpdateServiceSupport.ReleaseCandidate(tagName: tag, isPrerelease: pre, isDraft: false,
                                              dmgURL: URL(string: "https://github.com/ArthurCissac/hublot/releases/download/\(tag)/Hublot.dmg"),
                                              dmgExpectedBytes: 1, body: "notes")
    }

    static func run(_ suite: TestSuite) {
        suite.expect(ForkUpdate.repository(from: "https://github.com/ArthurCissac/hublot") == "ArthurCissac/hublot"
            && ForkUpdate.repository(from: "https://github.com/ArthurCissac/hublot.git") == "ArthurCissac/hublot",
                     "the fork's repository is read from its address")
        suite.expect(ForkUpdate.repository(from: nil) == nil && ForkUpdate.repository(from: "http://github.com/a/b") == nil
            && ForkUpdate.repository(from: "https://gitlab.com/a/b") == nil
            && ForkUpdate.repository(from: "https://github.com/a/b/releases") == nil
            && ForkUpdate.repository(from: "https://github.com/a b/c") == nil,
                     "anything but a plain github.com repository over https gives none")

        let releases = [candidate("v0.1.0"), candidate("v0.2.0"), candidate("v0.3.0-beta.1", pre: true)]
        let stable = UpdateServiceSupport.selectUpdate(from: releases, currentVersion: "0.1.0", includeBetas: false)
        let beta = UpdateServiceSupport.selectUpdate(from: releases, currentVersion: "0.2.0", includeBetas: true)
        suite.expect(stable?.tagName == "v0.2.0" && beta?.tagName == "v0.3.0-beta.1"
            && UpdateServiceSupport.selectUpdate(from: releases, currentVersion: "0.2.0", includeBetas: false) == nil,
                     "Hublot's own numbers pick the next release; a beta only on the beta channel")

        // The files the build reads, from the repository this test sits in.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let identity = (try? String(contentsOf: root.appendingPathComponent("Fork/identity.sh"), encoding: .utf8)) ?? ""
        let version = identity.split(separator: "\n")
            .first { $0.hasPrefix("FORK_VERSION=\"") }
            .map { String($0.dropFirst("FORK_VERSION=\"".count).dropLast()) } ?? ""
        let changelog = (try? String(contentsOf: root.appendingPathComponent("Fork/CHANGELOG.md"), encoding: .utf8)) ?? ""
        suite.expect(UpdateServiceSupport.SemanticVersion(raw: version) != nil && changelog.contains("## [\(version)] - "),
                     "the version in Fork/identity.sh is a version number with its section in Fork/CHANGELOG.md")
        suite.expect(!ReleaseNotes.rawNotes(for: version, changelog: changelog).isEmpty,
                     "the app reads that section as this version's notes")
    }
}
