// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Foundation

/// Vercel's deployments in the island (`forkVercelEnabled`): while one
/// builds, its project and how long it has run in the closed island; once
/// done, a notice, green when it is online, red when it failed. Read only,
/// from Vercel's REST API with the user's own token (kept in the Keychain).
/// Pure: the address asked, the answer read, what changed between two
/// looks, and what the island says.
enum ForkVercelLogic {
    static let base = URL(string: "https://api.vercel.com")!
    /// Answers larger than this are refused.
    static let maximumSize = 1 << 20

    /// The latest deployments of the token's team.
    static func deploymentsURL(limit: Int = 12) -> URL? {
        var parts = URLComponents(url: base.appendingPathComponent("v6/deployments"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "limit", value: String(max(1, min(limit, 50))))]
        return parts?.url
    }

    /// Where the user makes a token.
    static let tokensPage = URL(string: "https://vercel.com/account/tokens")!

    // MARK: - Deployments

    enum State: String, Decodable {
        case queued = "QUEUED", initializing = "INITIALIZING", building = "BUILDING"
        case ready = "READY", error = "ERROR", canceled = "CANCELED", unknown

        init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        var running: Bool { self == .queued || self == .initializing || self == .building }
    }

    struct Deployment: Decodable, Equatable, Identifiable {
        let uid: String
        let name: String
        let url: String?
        let state: State
        let target: String?
        /// Milliseconds since 1970, as Vercel gives them.
        let created: Double
        let buildingAt: Double?
        let inspectorUrl: String?

        var id: String { uid }
        var isProduction: Bool { target == "production" }

        private enum Keys: String, CodingKey {
            case uid, name, url, state, readyState, target, created, createdAt, buildingAt, inspectorUrl
        }

        init(uid: String, name: String, url: String?, state: State, target: String?, created: Double,
             buildingAt: Double? = nil, inspectorUrl: String? = nil) {
            self.uid = uid
            self.name = name
            self.url = url
            self.state = state
            self.target = target
            self.created = created
            self.buildingAt = buildingAt
            self.inspectorUrl = inspectorUrl
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            uid = try values.decode(String.self, forKey: .uid)
            name = try values.decode(String.self, forKey: .name)
            url = try values.decodeIfPresent(String.self, forKey: .url)
            // Older answers say readyState, newer ones state.
            state = try values.decodeIfPresent(State.self, forKey: .state)
                ?? values.decodeIfPresent(State.self, forKey: .readyState) ?? .unknown
            target = try values.decodeIfPresent(String.self, forKey: .target)
            created = try values.decodeIfPresent(Double.self, forKey: .created)
                ?? values.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
            buildingAt = try values.decodeIfPresent(Double.self, forKey: .buildingAt)
            inspectorUrl = try values.decodeIfPresent(String.self, forKey: .inspectorUrl)
        }

        /// When it began building, or was created.
        var started: Date { Date(timeIntervalSince1970: (buildingAt ?? created) / 1000) }
    }

    static func deployments(from data: Data?) -> [Deployment]? {
        struct Page: Decodable { let deployments: [Deployment] }
        guard let data, data.count <= maximumSize else { return nil }
        return (try? JSONDecoder().decode(Page.self, from: data))?.deployments
    }

    enum Scope: String, CaseIterable {
        case all, production
    }

    static func followed(_ deployments: [Deployment], scope: Scope) -> [Deployment] {
        scope == .production ? deployments.filter(\.isProduction) : deployments
    }

    /// The newest one still building, if any.
    static func building(_ deployments: [Deployment]) -> Deployment? {
        deployments.filter(\.state.running).max { $0.created < $1.created }
    }

    /// Those that were building at the last look and have now ended online
    /// or in failure. A cancelled build says nothing; the first look neither.
    static func finished(previous: [String: State]?, current: [Deployment]) -> [Deployment] {
        guard let previous else { return [] }
        return current.filter { deployment in
            (deployment.state == .ready || deployment.state == .error) && previous[deployment.uid]?.running == true
        }
    }

    static func snapshot(_ deployments: [Deployment]) -> [String: State] {
        Dictionary(deployments.map { ($0.uid, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every five seconds while something builds, every minute otherwise.
    static func pollInterval(building: Bool) -> TimeInterval { building ? 5 : 60 }

    // MARK: - What the island says

    static let islandSymbol = "hammer.fill"
    static let successSymbol = "checkmark.icloud.fill"
    static let failureSymbol = "xmark.icloud.fill"

    static func isNotice(symbol: String) -> Bool { symbol == successSymbol || symbol == failureSymbol }

    static func title(french: Bool) -> String { french ? "Déploiement" : "Deployment" }

    /// The project's name, shortened for the strip.
    static let nameLimit = 24

    static func islandName(_ deployment: Deployment) -> String {
        let name = deployment.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.count > nameLimit ? String(name.prefix(nameLimit - 1)) + "…" : name
    }

    /// « 0:42 », « 1:12 », « 12:03 »: how long it has been building.
    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", locale: Locale(identifier: "en_US_POSIX"), seconds / 60, seconds % 60)
    }

    /// The deployment's page on Vercel, its build log included; only ever on vercel.com.
    static func inspectorURL(_ deployment: Deployment) -> URL? {
        guard let raw = deployment.inspectorUrl else { return nil }
        let address = raw.hasPrefix("https://") ? raw : "https://" + raw
        guard let url = URL(string: address), url.scheme == "https",
              let host = url.host, host == "vercel.com" || host.hasSuffix(".vercel.com") else { return nil }
        return url
    }

    /// The deployed site itself.
    static func siteURL(_ deployment: Deployment) -> URL? {
        guard let raw = deployment.url, !raw.isEmpty, !raw.contains("/"), !raw.contains(" ") else { return nil }
        return URL(string: "https://" + raw)
    }

    /// A pasted token: ASCII letters, digits, « _ », « - » and « . » (newer
    /// tokens carry a prefix such as « vcp_ »), of a token's length.
    static func cleanToken(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...256).contains(token.count),
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) }) else { return nil }
        return token
    }

    /// The wider side, the mark with the time or the project's name, drawn
    /// as the strip draws them; the calendar's wings bound it.
    static func stripWing(name: String?, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactCalendarGeometry(wing: NotchGeometry.calendarWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let font = NSFont.systemFont(ofSize: textSize, weight: .medium)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }
        let left = iconSize + markSpacing + width("00:00")
            + provisional.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
        let words = name.map { width($0) + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) } ?? 0
        return max(left, words) + NotchTimerSupport.stripCameraGap
    }

    static let markSpacing: CGFloat = 4

    /// Set by the service at launch, read by upstream's island code (which
    /// the tests compile without the service). Until then, nothing shows.
    static var islandActivityShown: () -> Bool = { false }
    static var islandStripWing: (NotchGeometry) -> CGFloat = { stripWing(name: nil, in: $0) }
    static var islandReading: () -> String? = { nil }
    /// A click on the ended build's notice.
    static var openFinished: () -> Void = {}
}
