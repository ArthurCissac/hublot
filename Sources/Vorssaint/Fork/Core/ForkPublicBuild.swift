// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

extension AppInfo {
    /// False in this fork: upstream's donation page, its post-update showcase
    /// (whose media comes from upstream's releases) and its support step lead
    /// to the official project, which a redistributed fork must not suggest.
    /// In Core so upstream's settings directory, which the tests compile, can read it.
    static var showsUpstreamPromotion: Bool { false }
}
