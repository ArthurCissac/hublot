// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Fork-only switches on the app identity.
///
/// They live outside `Core/AppInfo.swift` so a rebase on upstream never
/// conflicts here: upstream files only ever read these properties.
extension AppInfo {
    /// True for the Developer build, for a build not made by Fork/release.sh
    /// (one installed from a work branch) and for a build that does not know
    /// the fork's repository: those never download nor install anything.
    ///
    /// Otherwise upstream's in-app updater runs against the fork's own releases
    /// (`AppInfo.updateRepository`, from Fork/identity.sh). The identity pass
    /// makes its installer require a DMG and an app signed by the fork's team
    /// with the fork's bundle identifier, so an upstream release can never
    /// replace the fork. Every updater entry point is gated on this property
    /// instead of on `isDeveloperBuild`; `Fork/check.sh` counts those gates.
    static var neverSelfUpdates: Bool { isDeveloperBuild || !isForkRelease || updateRepository.isEmpty }

    /// The fork's own repository (`Fork/identity.sh`, stamped into the
    /// Info.plist by the build), where « View on GitHub » leads.
    static var forkRepositoryURL: URL { forkSourceURL ?? repositoryURL }
}
