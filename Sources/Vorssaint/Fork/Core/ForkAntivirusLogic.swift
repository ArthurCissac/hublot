// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9, the antivirus: ClamAV run as its own programs (`clamscan`,
/// `freshclam`), never linked, its GPLv2 licence kept apart. Installed with
/// Homebrew when first needed. Pure: paths, dates and ClamAV's output come
/// in, what to run and show goes out.
enum ForkAntivirusLogic {
    /// Where Homebrew puts things, Apple silicon first.
    static let prefixes = ["/opt/homebrew", "/usr/local"]

    static func brew(existing: (String) -> Bool) -> String? {
        prefixes.map { "\($0)/bin/brew" }.first(where: existing)
    }

    static func tool(_ name: String, existing: (String) -> Bool) -> String? {
        prefixes.map { "\($0)/bin/\(name)" }.first(where: existing)
    }

    /// ClamAV's signatures, under the prefix its tools came from.
    static func databaseDirectory(forTool path: String) -> String {
        let prefix = prefixes.first { path.hasPrefix($0 + "/") } ?? prefixes[0]
        return prefix + "/var/lib/clamav"
    }

    static func configDirectory(forTool path: String) -> String {
        let prefix = prefixes.first { path.hasPrefix($0 + "/") } ?? prefixes[0]
        return prefix + "/etc/clamav"
    }

    /// Homebrew ships `freshclam.conf.sample` with an `Example` line that
    /// stops `freshclam`; the working file is the sample without it.
    static func freshclamConfig(fromSample sample: String) -> String {
        sample.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) != "Example" }
            .joined(separator: "\n")
    }

    /// Signatures older than a day are refreshed before a scan.
    static func signaturesAreStale(updated: Date?, now: Date) -> Bool {
        guard let updated else { return true }
        return now.timeIntervalSince(updated) > 24 * 3600
    }

    /// One line of `clamscan --stdout`: a file found clean, a threat with its
    /// name, or something else (errors, the summary).
    enum ScanLine: Equatable {
        case clean(path: String)
        case threat(path: String, signature: String)
        case other
    }

    static func parse(_ line: String) -> ScanLine {
        if line.hasSuffix(": OK") { return .clean(path: String(line.dropLast(4))) }
        guard line.hasSuffix(" FOUND"), let separator = line.range(of: ": ", options: .backwards) else { return .other }
        let path = String(line[..<separator.lowerBound])
        let signature = String(line[separator.upperBound...].dropLast(" FOUND".count))
        guard !path.isEmpty, !signature.isEmpty else { return .other }
        return .threat(path: path, signature: signature)
    }

    /// The quick scan: where downloads land and what starts by itself, plus
    /// the apps added lately.
    static func quickTargets(home: String, recentApps: [String]) -> [String] {
        ["\(home)/Downloads", "\(home)/Desktop", "\(home)/Documents", "\(home)/Library/LaunchAgents",
         "/Library/LaunchAgents", "/Library/LaunchDaemons"] + recentApps
    }

    /// Apps added within the last 30 days, from their dates of addition.
    static func recentApps(_ apps: [(path: String, added: Date)], now: Date) -> [String] {
        apps.filter { now.timeIntervalSince($0.added) <= 30 * 24 * 3600 }.map(\.path).sorted()
    }

    /// A file set aside: where it was, where it is now, what was found.
    struct QuarantineItem: Codable, Equatable, Identifiable {
        let id: UUID
        let originalPath: String
        let storedPath: String
        let signature: String
        let date: Date
    }

    /// Where a file goes in quarantine: a folder of its own, so two files
    /// with the same name never meet.
    static func quarantinePath(for original: String, id: UUID, in folder: String) -> String {
        "\(folder)/\(id.uuidString)/\((original as NSString).lastPathComponent)"
    }
}
