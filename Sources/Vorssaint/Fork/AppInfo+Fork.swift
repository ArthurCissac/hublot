// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Fork-only switches on the app identity.
///
/// They live outside `Core/AppInfo.swift` so a rebase on upstream never
/// conflicts here: upstream files only ever read these properties.
extension AppInfo {
    /// Always true in this fork: it is built locally from its own repository
    /// and must never download or install an upstream release.
    ///
    /// Upstream's in-app updater fetches the official DMG, verifies it against
    /// the official bundle id and team, then removes the running bundle when
    /// its name differs. In a fork that would replace the fork with the
    /// official app, so every updater entry point is gated on this property
    /// instead of on `isDeveloperBuild`. `Fork/check.sh` counts those gates.
    static var neverSelfUpdates: Bool { true }

    /// The fork's own repository (`Fork/identity.sh`, stamped into the
    /// Info.plist by the build), where « View on GitHub » leads.
    static var forkRepositoryURL: URL { forkSourceURL ?? repositoryURL }
}
