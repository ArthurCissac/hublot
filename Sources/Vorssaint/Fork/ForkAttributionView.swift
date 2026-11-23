// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

extension AppInfo {
    /// Where this fork's source lives. build.sh stamps it into Info.plist from
    /// Fork/identity.sh; nil in the bare binary (`--selftest`).
    static var forkSourceURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "ForkSourceURL") as? String).flatMap(URL.init(string:))
    }
}

/// The About pane's notice that this build is a fork.
///
/// The GPL asks a modified version to say so and to tell where its source is;
/// upstream's trademark policy asks a fork not to pass for the original. This
/// states both, under upstream's own copyright line, which stays untouched.
struct ForkAttributionView: View {
    @ObservedObject private var l10n = L10n.shared

    /// Upstream's name. Files under Fork/ are copied verbatim by the identity
    /// pass, so this literal is not renamed.
    private static let upstreamName = "Vorssaint"

    var body: some View {
        let text = ForkStrings.current
        VStack(spacing: 5) {
            Text(text.attribution(AppInfo.name, Self.upstreamName))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let source = AppInfo.forkSourceURL {
                    Link(text.forkSource, destination: source)
                }
                Link(text.upstreamProject(Self.upstreamName), destination: AppInfo.repositoryURL)
            }
            .font(.caption2)
        }
        .padding(.top, 2)
    }
}
