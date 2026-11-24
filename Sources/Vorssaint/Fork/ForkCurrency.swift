// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The European Central Bank's reference rates, downloaded only once a
/// conversion is typed and then at most twice a day, kept in the app's
/// private folder. The request carries no cookie and no identifier.
final class ForkCurrencyRates {
    static let shared = ForkCurrencyRates()

    private let lock = NSLock()
    private var rates: ForkCurrencyLogic.Rates?
    private var saved: Date?
    private var lastAttempt: Date?
    private var loading = false
    private var loadedCache = false
    private static let fileName = "fork-ecb-rates.json"

    private var cacheURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// The rates on hand, the saved ones the first time; asks the bank for
    /// fresh ones when they are due.
    func current() -> ForkCurrencyLogic.Rates? {
        lock.lock()
        if !loadedCache {
            loadedCache = true
            if let url = cacheURL, let data = try? Data(contentsOf: url),
               let stored = try? JSONDecoder().decode(ForkCurrencyLogic.Rates.self, from: data) {
                rates = stored
                saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
        }
        let due = !loading && ForkCurrencyLogic.isDue(saved: saved, lastAttempt: lastAttempt, now: Date())
        if due {
            loading = true
            lastAttempt = Date()
        }
        let answer = rates
        lock.unlock()
        if due { download() }
        return answer
    }

    private func download() {
        ForkCurrencyDownload.start(ForkCurrencyLogic.remote, limit: ForkCurrencyLogic.maximumSize) { [weak self] data in
            guard let self else { return }
            let parsed = data.flatMap(ForkCurrencyLogic.parseECB)
            self.lock.lock()
            self.loading = false
            if let parsed {
                self.rates = parsed
                self.saved = Date()
            }
            self.lock.unlock()
            guard let parsed else { return }
            self.store(parsed)
            DispatchQueue.main.async { CommandBarService.shared.noteHubChange() }
        }
    }

    private func store(_ rates: ForkCurrencyLogic.Rates) {
        guard let container = PrivateFileStore.containerURL, let url = cacheURL,
              PrivateFileStore.createDirectory(at: container),
              let data = try? JSONEncoder().encode(rates) else { return }
        _ = PrivateFileStore.write(data, to: url)
    }
}

/// One bounded HTTPS request without cookies or cache, following no
/// redirect off its own host (the pattern of upstream's price list).
private final class ForkCurrencyDownload: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let host: String?
    private var data = Data()
    private var status = 0
    private let completion: (Data?) -> Void

    private init(limit: Int, host: String?, completion: @escaping (Data?) -> Void) {
        self.limit = limit
        self.host = host
        self.completion = completion
    }

    static func start(_ url: URL, limit: Int, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegate = ForkCurrencyDownload(limit: limit, host: url.host, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: request).resume()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == host ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(status == 200 ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        if data.count > limit { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && status == 200 && data.count <= limit ? data : nil)
    }
}

/// The command bar's answer row for a conversion: the converted amount,
/// the amount typed and the rates' date; Return copies the result.
enum ForkCurrencyAnswer {
    static func install() {
        ForkCurrencyLogic.commandBarAnswer = { entry(for: $0, bar: $1) }
    }

    static func entry(for query: String, bar: CommandBarFeatureStrings) -> CommandBarEntry? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.forkCurrencyEnabled) else { return nil }
        let target = defaults.string(forKey: DefaultsKey.forkCurrencyTarget) ?? "EUR"
        guard let asked = ForkCurrencyLogic.parse(query, defaultTarget: target) else { return nil }
        let strings = ForkCurrencyStrings.current
        guard let rates = ForkCurrencyRates.shared.current() else {
            return CommandBarEntry(id: "fork.currency.loading", title: strings.loading, subtitle: strings.source,
                                   icon: .symbol("dollarsign.arrow.circlepath"), isAnswer: true, countsUsage: false,
                                   keepsBarOpen: true, run: { _ in })
        }
        guard let value = ForkCurrencyLogic.convert(asked, rates: rates) else { return nil }
        let result = ForkCurrencyLogic.format(value, currency: asked.to)
        let typed = ForkCurrencyLogic.format(asked.amount, currency: asked.from)
        return CommandBarEntry(id: "fork.currency.result", title: result,
                               subtitle: "\(typed) · \(strings.rates(ForkCurrencyLogic.dayText(rates.day))) · \(bar.copyHint)",
                               icon: .symbol("dollarsign.arrow.circlepath"), isAnswer: true, countsUsage: false,
                               run: { _ in copy(result) })
    }

    private static func copy(_ value: String) {
        GeneralPasteboardAccess.shared.async({
            NSPasteboard.general.clearContents()
            NSPasteboard.general.declareVorssaintSource()
            return NSPasteboard.general.setString(value, forType: .string)
        }, then: { copied in
            QuickToolHUD.show(icon: copied ? "doc.on.doc" : "exclamationmark.circle",
                              message: copied ? value : FeatureStrings.commandBar(L10n.shared.language).copyFailed)
        })
    }
}

/// The switch and the default currency, among the command bar's sources.
struct ForkCurrencySettingsRows: View {
    @AppStorage(DefaultsKey.forkCurrencyEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkCurrencyTarget) private var target = "EUR"
    private let strings = ForkCurrencyStrings.current

    var body: some View {
        Toggle(isOn: $enabled) {
            Label(strings.toggle, systemImage: "dollarsign.arrow.circlepath")
        }
        if enabled {
            Picker(strings.target, selection: $target) {
                ForEach(["EUR"] + ForkCurrencyLogic.codes.subtracting(["EUR"]).sorted(), id: \.self) { code in
                    Text(verbatim: code).tag(code)
                }
            }
            .padding(.leading, 28)
        }
    }
}
