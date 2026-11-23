// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Where Hublot looks for its updates: the releases of its own repository
/// (`FORK_SOURCE_URL` in Fork/identity.sh, stamped into the Info.plist as
/// ForkSourceURL). Upstream's updater, installer and checks are used as they
/// are; the identity pass already makes the installer require a DMG and an app
/// signed by the fork's team, with the fork's bundle identifier.
enum ForkUpdate {
    /// « owner/name » of a github.com repository address, or nil.
    static func repository(from address: String?) -> String? {
        guard let address, let url = URL(string: address), url.scheme == "https",
              url.host == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }) else { return nil }
        let name = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        return "\(parts[0])/\(name)"
    }
}

extension AppInfo {
    /// The fork's repository for updates; empty in the bare binary, where
    /// nothing is checked.
    static var updateRepository: String {
        ForkUpdate.repository(from: Bundle.main.object(forInfoDictionaryKey: "ForkSourceURL") as? String) ?? ""
    }

    /// Built by Fork/release.sh for download. A build installed from a work
    /// branch is not, and never updates itself.
    static var isForkRelease: Bool {
        Bundle.main.object(forInfoDictionaryKey: "ForkReleaseBuild") as? Bool == true
    }

    /// The upstream version this build of the fork is based on.
    static var forkBaseVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "ForkBaseVersion") as? String
    }
}
