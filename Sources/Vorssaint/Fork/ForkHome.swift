// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Security
import SwiftUI

/// Home Assistant in the island and the menu (see `ForkHomeLogic`). One
/// WebSocket stays open while the Home page is on, a token is saved and the
/// Mac is awake: Home Assistant pushes each favourite's changes, so a tile
/// follows a cover closed from the phone at once. Switched off, asleep or
/// without a token, nothing is open and nothing is asked.
///
/// Security: the long-lived token lives in the Keychain only. It is read
/// when the connection authenticates and never kept in memory, preferences,
/// settings backups nor logs; it goes to the configured address only, over
/// a session without cookies, cache or redirects. Plain http is accepted on
/// the local network only (ForkHomeLogic.address), and only the services of
/// ForkHomeLogic.allowedServices can ever be called.

// MARK: - The token

enum ForkHomeKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "agency.nexflow.hublot") + ".home-assistant" }
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

    static func exists() -> Bool {
        var search = query
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(search as CFDictionary, nil) == errSecSuccess
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

final class ForkHome: NSObject, ObservableObject {
    typealias Logic = ForkHomeLogic

    static let shared = ForkHome()

    enum Status: Equatable { case off, needsSetup, connecting, connected, unauthorized, unreachable }

    @Published private(set) var status: Status = .off {
        didSet { if (status == .connected) != (oldValue == .connected) { islandResized() } }
    }
    @Published private(set) var hasToken = false
    /// Connected through the fallback address.
    @Published private(set) var usingFallback = false
    /// The favourites Home Assistant has sent a state for, in their order.
    @Published private(set) var favorites: [Logic.Entity] = []
    @Published private(set) var rooms = Logic.Rooms()
    /// Every device that can be chosen, read when the list is shown.
    @Published private(set) var choices: [Logic.Entity] = []
    @Published private(set) var loadingChoices = false
    /// Devices with a request on its way, and those whose last one failed.
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var failed: Set<String> = []
    /// The camera shown in the island, its latest picture, and whether the last one failed.
    @Published private(set) var viewing: String? {
        didSet { if viewing != oldValue { islandResized() } }
    }
    @Published private(set) var picture: NSImage?
    /// The 3D printer shown in the Home page (ForkBambu), in place of the favourites.
    @Published private(set) var viewingPrinter = false {
        didSet { if viewingPrinter != oldValue { islandResized() } }
    }
    @Published private(set) var pictureFailed = false

    private var live: [String: Logic.Raw] = [:]
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var nextID = 1
    private var replies: [Int: (Bool, Any?) -> Void] = [:]
    private var subscription: Int?
    private var subscribed: [String] = []
    private var attempt = 0
    private var candidate = 0
    private var retryTimer: Timer?
    private var pingTimer: Timer?
    private var awaitingPong = false
    private var asleep = false
    private var signature = ""
    /// The address the open connection reached: pictures are asked there too.
    private var connectedBase: URL?
    private var pictureTimer: Timer?
    private var fetchingPicture = false
    private var observers: [NSObjectProtocol] = []
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }

    private var defaults: UserDefaults { .standard }
    var enabled: Bool { defaults.bool(forKey: DefaultsKey.forkHomeEnabled) }
    var favoriteIDs: [String] { Logic.favorites(defaults.string(forKey: DefaultsKey.forkHomeFavorites)) }
    var menuTileIDs: [String] {
        Logic.menuTiles(defaults.string(forKey: DefaultsKey.forkHomeMenuTiles), favorites: favoriteIDs)
    }
    private var candidates: [URL] {
        Logic.candidates(main: defaults.string(forKey: DefaultsKey.forkHomeURL),
                         fallback: defaults.string(forKey: DefaultsKey.forkHomeFallbackURL))
    }
    /// The main address, for the page that makes tokens.
    var address: URL? { candidates.first }

    func start() {
        Logic.contentHeight = { width in ForkHome.shared.pageHeight(width: width) }
        hasToken = ForkHomeKeychain.exists()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.resync.schedule() })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true
            self?.sync()
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The network takes a moment to come back after waking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.asleep = false
                self?.signature = ""
                self?.sync()
            }
        })
        resync.schedule()
    }

    /// Connects, reconnects after a change of address or token, follows the
    /// favourites chosen, or closes everything.
    private func sync() {
        let urls = candidates
        guard enabled, hasToken, !urls.isEmpty, !asleep else {
            disconnect()
            signature = ""
            live = [:]
            if !favorites.isEmpty { favorites = [] }
            let next: Status = enabled && !asleep ? .needsSetup : .off
            if status != next { status = next }
            return
        }
        let wanted = urls.map(\.absoluteString).joined(separator: " ")
        if wanted != signature {
            signature = wanted
            reconnect()
        } else if status == .connected, favoriteIDs != subscribed {
            subscribe()
        }
    }

    /// Tries again now, from the main address.
    func reconnect() {
        attempt = 0
        candidate = 0
        connect()
    }

    private func connect() {
        disconnect()
        let urls = candidates
        guard enabled, hasToken, !asleep, !urls.isEmpty else { return }
        let index = candidate % urls.count
        guard let url = Logic.webSocketURL(urls[index]) else { return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = Logic.maximumMessageSize
        self.session = session
        self.socket = socket
        connectedBase = urls[index]
        usingFallback = index > 0
        status = .connecting
        socket.resume()
        receive(on: socket)
    }

    private func disconnect() {
        pingTimer?.invalidate(); pingTimer = nil
        if viewing != nil { stopViewing() }
        retryTimer?.invalidate(); retryTimer = nil
        let waiting = replies
        replies = [:]
        subscription = nil
        subscribed = []
        awaitingPong = false
        if let socket {
            self.socket = nil
            socket.cancel(with: .normalClosure, reason: nil)
        }
        session?.invalidateAndCancel()
        session = nil
        if !pending.isEmpty { pending = [] }
        for reply in waiting.values { reply(false, nil) }
    }

    /// The connection dropped or never opened: try again a little later,
    /// the other address first when there is one.
    private func lost() {
        guard socket != nil else { return }
        disconnect()
        status = .unreachable
        let delay = Logic.retryDelay(attempt: attempt)
        attempt += 1
        candidate += 1
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.connect() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    /// Refused: no retry until the token or the address changes.
    private func refused() {
        disconnect()
        status = .unauthorized
    }

    // MARK: Messages

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, socket === self.socket else { return }
                switch result {
                case .failure:
                    self.lost()
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                    @unknown default: break
                    }
                    if socket === self.socket { self.receive(on: socket) }
                }
            }
        }
    }

    private func handle(_ text: String) {
        for message in Logic.incoming(text) {
            switch message {
            case .authRequired:
                guard let token = ForkHomeKeychain.load(), let auth = Logic.authMessage(token: token) else { return refused() }
                socket?.send(.string(auth)) { [weak self] error in
                    if error != nil { DispatchQueue.main.async { self?.lost() } }
                }
            case .authOK:
                status = .connected
                attempt = 0
                subscribe()
                loadRooms()
                startPing()
            case .authInvalid:
                return refused()
            case .result(let id, let success, let value):
                replies.removeValue(forKey: id)?(success, value)
            case .event(let id, let value):
                guard id == subscription else { continue }
                live = Logic.applying(value, to: live)
                refreshFavorites()
            case .pong:
                awaitingPong = false
            case .other:
                break
            }
        }
    }

    /// Sends a command built with its id; `reply` gets the result, or a
    /// failure when the connection goes first.
    @discardableResult
    private func request(_ make: (Int) -> String?, reply: ((Bool, Any?) -> Void)? = nil) -> Int? {
        let id = nextID
        guard let socket, let text = make(id) else { reply?(false, nil); return nil }
        nextID += 1
        if let reply { replies[id] = reply }
        socket.send(.string(text)) { [weak self] error in
            if error != nil { DispatchQueue.main.async { self?.lost() } }
        }
        return id
    }

    private func startPing() {
        pingTimer?.invalidate()
        awaitingPong = false
        let timer = Timer(timeInterval: Logic.pingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.awaitingPong { return self.lost() }
            self.awaitingPong = true
            self.request { Logic.command(id: $0, type: "ping") }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    // MARK: Favourites' states

    private func subscribe() {
        guard status == .connected else { return }
        if let old = subscription {
            request { Logic.command(id: $0, type: "unsubscribe_events", ["subscription": old]) }
        }
        subscription = nil
        let ids = favoriteIDs
        subscribed = ids
        live = live.filter { ids.contains($0.key) }
        refreshFavorites()
        guard !ids.isEmpty else { return }
        subscription = request { Logic.subscribeEntities(id: $0, entityIDs: ids) }
    }

    private func refreshFavorites() {
        let next = favoriteIDs.compactMap { id in live[id].flatMap { Logic.entity(id: id, raw: $0) } }
        guard next != favorites else { return }
        let reshaped = next.map(\.id) != favorites.map(\.id)
        followCovers(from: favorites, to: next)
        favorites = next
        if reshaped { islandResized() }
    }

    private func loadRooms(then done: (() -> Void)? = nil) {
        var areas: Any?, devices: Any?, entities: Any?
        var left = 3
        let finish = { [weak self] in
            left -= 1
            guard left == 0, let self else { return }
            let next = Logic.rooms(areas: areas, devices: devices, entities: entities)
            if next != self.rooms {
                self.rooms = next
                self.replaceSwitchesByCovers()
                self.islandResized()
            }
            done?()
        }
        request({ Logic.command(id: $0, type: "config/area_registry/list") }) { _, value in areas = value; finish() }
        request({ Logic.command(id: $0, type: "config/device_registry/list") }) { _, value in devices = value; finish() }
        request({ Logic.command(id: $0, type: "config/entity_registry/list") }) { _, value in entities = value; finish() }
    }

    /// The island is as tall as the page: it measures again when the page changes shape.
    private func islandResized() {
        guard NotchSupport.isEnabled() else { return }
        NotchService.shared.objectWillChange.send()
        NotchService.shared.refreshPresentation()
    }

    func entity(_ id: String) -> Logic.Entity? { favorites.first { $0.id == id } }

    /// The page's rooms with their favourites.
    func groups(other: String) -> [Logic.Group] {
        Logic.groups(favorites, areas: rooms.areaOfEntity, other: other)
    }

    private func pageHeight(width: CGFloat) -> CGFloat? {
        guard status == .connected, !favorites.isEmpty else { return nil }
        if viewingPrinter { return ForkBambuLogic.pageHeight(width: width) + Logic.printerBar }
        if viewing != nil { return Logic.viewerHeight(width: width) }
        let groups = groups(other: "")
        var counts = groups.map { (titled: $0.title != nil, count: $0.entities.count) }
        if showsPrinterTile { counts = Logic.adding(printerPlacement(groups, other: ""), to: counts) }
        return Logic.pageHeight(counts, width: width)
    }

    // MARK: The 3D printer

    /// A 3D printer tile while the Printer page is on (and not hidden from Home).
    var showsPrinterTile: Bool {
        defaults.bool(forKey: DefaultsKey.forkHomeShowsPrinter) && ForkBambuLogic.pageAvailable(in: defaults)
    }

    func printerPlacement(_ groups: [Logic.Group], other: String) -> Logic.ExtraPlacement {
        Logic.extraPlacement(groups.map { (titled: $0.title != nil, count: $0.entities.count) },
                             lastIsOther: groups.last?.title == other)
    }

    func showPrinter() {
        stopViewing()
        viewingPrinter = true
    }

    func hidePrinter() { viewingPrinter = false }

    // MARK: Choosing devices

    /// Reads every device and its room, for the list to choose from.
    func loadChoices() {
        guard status == .connected, !loadingChoices else { return }
        loadingChoices = true
        request({ Logic.command(id: $0, type: "get_states") }) { [weak self] success, value in
            guard let self else { return }
            let states = success ? Logic.raws(fromStates: value) : [:]
            self.loadRooms {
                self.loadingChoices = false
                self.choices = Logic.pickable(states, rooms: self.rooms)
            }
        }
    }

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }
    func isMenuTile(_ id: String) -> Bool { menuTileIDs.contains(id) }

    func toggleFavorite(_ id: String) {
        let next = Logic.toggling(id, in: favoriteIDs)
        defaults.set(Logic.stored(next), forKey: DefaultsKey.forkHomeFavorites)
        if !next.contains(id), isMenuTile(id) { toggleMenuTile(id) }
    }

    /// A favourite gets a menu tile of its own, or loses it.
    func toggleMenuTile(_ id: String) {
        let current = Logic.favorites(defaults.string(forKey: DefaultsKey.forkHomeMenuTiles))
        let next = current.contains(id) ? current.filter { $0 != id } : (isFavorite(id) ? current + [id] : current)
        defaults.set(Logic.stored(next), forKey: DefaultsKey.forkHomeMenuTiles)
    }

    // MARK: Actions

    /// `confirmed`: a gate's or garage door's second click, or a menu item chosen.
    func perform(_ command: Logic.Command, on entity: Logic.Entity, confirmed: Bool = false) {
        guard status == .connected, let call = Logic.call(command, for: entity, confirmed: confirmed) else { return }
        pending.insert(entity.id)
        failed.remove(entity.id)
        request({ Logic.callService(id: $0, call) }) { [weak self] success, _ in
            guard let self else { return }
            self.pending.remove(entity.id)
            guard !success else { return }
            self.failed.insert(entity.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.failed.remove(entity.id) }
        }
    }

    // MARK: Shutters' single button

    /// The way each shutter last went, asked by a click or seen in Home
    /// Assistant (a press on the wall included), while Hublot runs.
    @Published private(set) var coverRuns: [String: Logic.CoverRun] = [:]

    func coverDirection(_ entity: Logic.Entity) -> Logic.Direction {
        Logic.coverDirection(entity, last: coverRuns[entity.id], now: Date())
    }

    func coverText(_ entity: Logic.Entity, french: Bool) -> String {
        Logic.coverText(entity, last: coverRuns[entity.id], now: Date(), french: french)
    }

    /// The single button: does what its arrow shows, then offers the other way at once.
    func pressCover(_ entity: Logic.Entity) {
        guard status == .connected, entity.available, entity.kind == .cover, !entity.needsConfirmation else { return }
        let direction = coverDirection(entity)
        coverRuns[entity.id] = Logic.CoverRun(direction: direction, at: Date())
        coverActions[entity.id] = Date()
        perform(Logic.command(for: direction), on: entity)
        // Home Assistant's word again once the click has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + Logic.coverSettle + 0.2) { [weak self] in self?.objectWillChange.send() }
    }

    /// The ■ beside the arrow: the arrow then offers the other way from the run stopped.
    func stopCover(_ entity: Logic.Entity) {
        guard status == .connected, entity.available, entity.kind == .cover, entity.canStop else { return }
        coverRuns[entity.id] = Logic.stopped(coverRuns[entity.id])
        coverActions[entity.id] = Date()
        perform(.stop, on: entity, confirmed: true)
    }

    /// When Hublot last asked each shutter something.
    private var coverActions: [String: Date] = [:]

    /// Runs Home Assistant reports on its own (a press on the wall), echoes of Hublot's own aside.
    private func followCovers(from old: [Logic.Entity], to new: [Logic.Entity]) {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entity in new where entity.kind == .cover {
            guard Logic.follows(lastAction: coverActions[entity.id], now: Date()),
                  let previous = before[entity.id], let direction = Logic.movement(from: previous, to: entity) else { continue }
            coverRuns[entity.id] = Logic.CoverRun(direction: direction, at: .distantPast)
        }
    }

    /// Favourites, menu tiles and the menu's order naming a switch that
    /// doubles a shutter name the shutter instead, in the same place.
    private func replaceSwitchesByCovers() {
        let doubles = rooms.coverOfSwitch
        guard !doubles.isEmpty else { return }
        for key in [DefaultsKey.forkHomeFavorites, DefaultsKey.forkHomeMenuTiles] {
            let ids = Logic.favorites(defaults.string(forKey: key))
            let replaced = Logic.replacingSwitches(ids, rooms: rooms)
            if replaced != ids { defaults.set(Logic.stored(replaced), forKey: key) }
        }
        let order = ForkTileLayoutLogic.parse(defaults.string(forKey: DefaultsKey.forkTileOrder))
        let renamed = order.map { key in
            doubles.first { ForkTileLayoutLogic.homeKey($0.key) == key }.map { ForkTileLayoutLogic.homeKey($0.value) } ?? key
        }
        if renamed != order {
            defaults.set(ForkTileLayoutLogic.encode(ForkTileLayoutLogic.parse(renamed.joined(separator: ","))),
                         forKey: DefaultsKey.forkTileOrder)
        }
    }

    // MARK: Cameras

    /// Shows a camera in the island: a picture now, then one every
    /// moment while it stays open. Nothing is asked once it closes.
    func startViewing(_ id: String) {
        guard entity(id)?.kind == .camera else { return }
        if viewing != id { picture = nil }
        viewing = id
        pictureFailed = false
        fetchPicture()
        pictureTimer?.invalidate()
        let timer = Timer(timeInterval: Logic.pictureInterval, repeats: true) { [weak self] _ in self?.fetchPicture() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pictureTimer = timer
    }

    func stopViewing() {
        pictureTimer?.invalidate()
        pictureTimer = nil
        viewing = nil
        picture = nil
        pictureFailed = false
    }

    private func fetchPicture() {
        guard !fetchingPicture, status == .connected, let id = viewing, let entity = entity(id),
              let base = connectedBase, let url = Logic.pictureURL(base: base, entity: entity),
              let token = ForkHomeKeychain.load() else { return }
        fetchingPicture = true
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        _ = ForkSpotifyHTTP.send(request, maximumBytes: Logic.maximumPictureSize) { [weak self] status, data in
            guard let self else { return }
            self.fetchingPicture = false
            guard self.viewing == id else { return }
            if (200...299).contains(status ?? 0), let data, let image = NSImage(data: data) {
                self.picture = image
                self.pictureFailed = false
            } else {
                self.pictureFailed = true
            }
        }
    }

    // MARK: The token

    @discardableResult
    func setToken(_ raw: String) -> Bool {
        guard let token = Logic.cleanToken(raw), ForkHomeKeychain.save(token) else { return false }
        hasToken = true
        signature = ""
        sync()
        return true
    }

    func forgetToken() {
        ForkHomeKeychain.delete()
        hasToken = false
        sync()
    }
}

extension ForkHome: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { if webSocketTask === self.socket { self.lost() } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { if task === self.socket { self.lost() } }
    }

    /// The token goes to the address typed and nowhere else.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
