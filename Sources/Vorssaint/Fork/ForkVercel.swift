// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Security
import SwiftUI

/// Vercel's deployments in the island (see `ForkVercelLogic`). The user's
/// token lives in the Keychain only: never in preferences nor in a log.
/// Vercel is asked every minute, every five seconds while something
/// builds, and not at all while the switch is off or without a token.

// MARK: - The token

enum ForkVercelKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "agency.nexflow.hublot") + ".vercel" }
    private static let account = "token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - The service

final class ForkVercel: ObservableObject {
    typealias Logic = ForkVercelLogic

    static let shared = ForkVercel()

    enum Problem: Equatable { case unauthorized, offline, failed }

    @Published private(set) var building: Logic.Deployment?
    @Published private(set) var hasToken = false
    @Published private(set) var problem: Problem?
    @Published private(set) var lastChecked: Date?

    private var previous: [String: Logic.State]?
    private var lastFinished: Logic.Deployment?
    private var fetching = false
    private var timer: Timer?
    private var shown = false
    private var observer: NSObjectProtocol?

    var enabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkVercelEnabled) }
    private var scope: Logic.Scope {
        Logic.Scope(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.forkVercelScope) ?? "") ?? .all
    }

    func start() {
        Logic.islandActivityShown = { ForkVercel.shared.showsIsland }
        Logic.islandStripWing = { Logic.stripWing(name: ForkVercel.shared.building.map(Logic.islandName), in: $0) }
        Logic.islandReading = { ForkVercel.shared.building.map(Logic.islandName) }
        Logic.openFinished = { ForkVercel.shared.openFinished() }
        hasToken = ForkVercelKeychain.load() != nil
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.sync() }
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    var showsIsland: Bool { enabled && hasToken && building != nil && NotchSupport.isEnabled() }

    /// Asks again now, or stops everything when switched off.
    private func sync() {
        guard enabled, hasToken else {
            timer?.invalidate(); timer = nil
            previous = nil
            if building != nil { building = nil }
            islandChanged()
            return
        }
        if timer == nil { check() }
    }

    private func schedule() {
        timer?.invalidate()
        guard enabled, hasToken else { timer = nil; return }
        let timer = Timer(timeInterval: Logic.pollInterval(building: building != nil), repeats: false) { [weak self] _ in
            self?.check()
        }
        timer.tolerance = building != nil ? 1 : 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() {
        guard enabled, !fetching, let token = ForkVercelKeychain.load(), let url = Logic.deploymentsURL() else {
            hasToken = ForkVercelKeychain.load() != nil
            return schedule()
        }
        fetching = true
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = ForkSpotifyHTTP.send(request, maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            self.fetching = false
            defer { self.schedule() }
            guard (200...299).contains(status ?? 0), let all = Logic.deployments(from: data) else {
                self.problem = status == 401 || status == 403 ? .unauthorized : status == nil ? .offline : .failed
                return
            }
            self.problem = nil
            self.lastChecked = Date()
            let followed = Logic.followed(all, scope: self.scope)
            for done in Logic.finished(previous: self.previous, current: followed) { self.announce(done) }
            self.previous = Logic.snapshot(followed)
            let now = Logic.building(followed)
            if now != self.building { self.building = now }
            self.islandChanged()
        }
    }

    /// A build has ended: a short notice, green online, red on failure.
    private func announce(_ deployment: Logic.Deployment) {
        let success = deployment.state == .ready
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: success ? DefaultsKey.forkVercelNotifySuccess : DefaultsKey.forkVercelNotifyFailure),
              NotchSupport.isEnabled() else { return }
        lastFinished = deployment
        let text = ForkVercelStrings.current
        _ = NotchService.shared.show(NotchNotice(event: .download, title: success ? text.online : text.failed,
                                                 detail: Logic.islandName(deployment) + (deployment.isProduction ? " · " + text.production : ""),
                                                 symbol: success ? Logic.successSymbol : Logic.failureSymbol,
                                                 mascot: success ? .celebrate : .confused))
    }

    /// A click on the ended build's notice opens its page on Vercel.
    func openFinished() {
        guard let deployment = lastFinished else { return }
        if let url = deployment.state == .ready ? (Logic.inspectorURL(deployment) ?? Logic.siteURL(deployment))
            : Logic.inspectorURL(deployment) {
            NSWorkspace.shared.open(url)
        }
    }

    /// A click on the strip opens the build's page and its log.
    func openBuilding() {
        guard let building, let url = Logic.inspectorURL(building) else { return }
        NSWorkspace.shared.open(url)
    }

    private func islandChanged() {
        let shows = showsIsland
        objectWillChange.send()
        guard shows != shown || shows else { return }
        shown = shows
        NotchService.shared.refreshPresentation()
    }

    @discardableResult
    func setToken(_ raw: String) -> Bool {
        guard let token = Logic.cleanToken(raw), ForkVercelKeychain.save(token) else { return false }
        hasToken = true
        problem = nil
        previous = nil
        timer?.invalidate(); timer = nil
        sync()
        return true
    }

    func disconnect() {
        ForkVercelKeychain.delete()
        hasToken = false
        problem = nil
        sync()
    }
}

/// The ended build's notice wears green or red rather than white.
enum ForkVercelNotice {
    static func tint(for symbol: String) -> Color? {
        switch symbol {
        case ForkVercelLogic.successSymbol: return .green
        case ForkVercelLogic.failureSymbol: return .red
        default: return nil
        }
    }
}

// MARK: - In the closed island

private let forkVercelTint = Color(red: 0.62, green: 0.72, blue: 1.0)

/// While a deployment builds: the hammer and the time left of the camera,
/// the project on the right. A click opens its page on Vercel.
struct ForkVercelStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var vercel = ForkVercel.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let text = ForkVercelStrings.current
        Button { vercel.openBuilding() } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        Color.clear
                        if wing >= 28, let building = vercel.building {
                            HStack(spacing: ForkVercelLogic.markSpacing) {
                                Image(systemName: ForkVercelLogic.islandSymbol)
                                    .font(.system(size: iconSize * 0.74, weight: .semibold))
                                    .frame(width: iconSize, height: iconSize)
                                    .symbolEffect(.pulse, options: .repeating)
                                Text(ForkVercelLogic.elapsed(since: building.started, now: context.date))
                                    .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            }
                            .foregroundStyle(forkVercelTint)
                            .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                        }
                    }
                    .frame(width: wing, height: height)
                    Color.clear.frame(width: geometry.compactActivityCameraGap)
                    ZStack(alignment: .trailing) {
                        Color.clear
                        if wing >= 42, let building = vercel.building {
                            Text(ForkVercelLogic.islandName(building))
                                .font(.system(size: textSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1).truncationMode(.tail)
                                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                        }
                    }
                    .frame(width: wing, height: height)
                }
                .frame(height: height)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.building)
        .accessibilityValue(vercel.building.map(ForkVercelLogic.islandName) ?? "")
        .accessibilityHint(text.openHint)
    }
}

/// The same in the island's capsule look.
struct ForkVercelCapsuleStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var vercel = ForkVercel.shared

    var body: some View {
        let geometry = displayGeometry ?? service.geometry
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Image(systemName: ForkVercelLogic.islandSymbol)
                    .font(.system(size: 12, weight: .semibold))
                if let building = vercel.building {
                    Text(ForkVercelLogic.elapsed(since: building.started, now: context.date))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Text(ForkVercelLogic.islandName(building))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .foregroundStyle(forkVercelTint)
            .padding(.horizontal, 10)
            .frame(width: size.width, height: geometry.stripHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture { vercel.openBuilding() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ForkVercelStrings.current.building)
        .accessibilityValue(vercel.building.map(ForkVercelLogic.islandName) ?? "")
    }
}

// MARK: - Settings

/// Vercel's card in Dynamic Island settings, next to Todoist's.
struct ForkVercelSettingsSection: View {
    @AppStorage(DefaultsKey.forkVercelEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkVercelScope) private var scope = ForkVercelLogic.Scope.all.rawValue
    @AppStorage(DefaultsKey.forkVercelNotifySuccess) private var notifySuccess = true
    @AppStorage(DefaultsKey.forkVercelNotifyFailure) private var notifyFailure = true
    @ObservedObject private var vercel = ForkVercel.shared
    @State private var token = ""

    var body: some View {
        let text = ForkVercelStrings.current
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.headline)
            ForkOptionRow(symbol: ForkVercelLogic.islandSymbol, title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                if vercel.hasToken {
                    ForkOptionRow(symbol: "person.crop.circle", title: text.account, caption: caption(text)) {
                        Button(text.disconnect) { vercel.disconnect() }
                    }
                } else {
                    ForkOptionRow(symbol: "key", title: text.token, caption: text.tokenCaption) {
                        HStack(spacing: 6) {
                            SecureField(text.token, text: $token).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 200)
                            Button(text.save) { if vercel.setToken(token) { token = "" } }
                                .disabled(ForkVercelLogic.cleanToken(token) == nil)
                            Button(text.getToken) { NSWorkspace.shared.open(ForkVercelLogic.tokensPage) }
                        }
                    }
                }
                ForkOptionRow(symbol: "line.3.horizontal.decrease.circle", title: text.scope, caption: text.scopeCaption) {
                    Picker(text.scope, selection: $scope) {
                        Text(text.scopeAll).tag(ForkVercelLogic.Scope.all.rawValue)
                        Text(text.scopeProduction).tag(ForkVercelLogic.Scope.production.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                ForkOptionRow(symbol: ForkVercelLogic.successSymbol, title: text.notifySuccess, caption: text.notifySuccessCaption) {
                    Toggle(text.notifySuccess, isOn: $notifySuccess).labelsHidden().toggleStyle(.switch)
                }
                ForkOptionRow(symbol: ForkVercelLogic.failureSymbol, title: text.notifyFailure, caption: text.notifyFailureCaption) {
                    Toggle(text.notifyFailure, isOn: $notifyFailure).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private func caption(_ text: ForkVercelStrings) -> String {
        switch vercel.problem {
        case .unauthorized?: return text.unauthorized
        case .offline?: return text.offline
        case .failed?: return text.failedCheck
        case nil: return text.connected
        }
    }
}
