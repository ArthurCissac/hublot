// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Currency conversion in the command bar: "1500 € en $", "100 usd eur",
/// "1 500,50 £", with the European Central Bank's reference rates, published
/// once a working day against the euro. Parsing, the bank's file, the
/// conversion and its formatting; the download lives in `ForkCurrencyRates`.
enum ForkCurrencyLogic {
    /// One day's rates: how many units of each currency one euro buys.
    struct Rates: Equatable, Codable {
        /// The bank's date for them, "2026-11-20".
        let day: String
        let perEuro: [String: Double]

        func rate(_ code: String) -> Double? { code == "EUR" ? 1 : perEuro[code] }
    }

    /// The bank's daily file: a few kilobytes.
    static let remote = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let maximumSize = 64 * 1024
    /// The bank publishes around 16:00 CET on working days.
    static let refreshInterval: TimeInterval = 12 * 3_600
    static let retryInterval: TimeInterval = 3_600

    /// Reads `<Cube time="…">` and its `<Cube currency="USD" rate="1.0845"/>` lines.
    static func parseECB(_ data: Data) -> Rates? {
        guard data.count <= maximumSize else { return nil }
        let reader = ECBReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let day = reader.day, !reader.rates.isEmpty else { return nil }
        return Rates(day: day, perEuro: reader.rates)
    }

    private final class ECBReader: NSObject, XMLParserDelegate {
        var day: String?
        var rates: [String: Double] = [:]

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard element == "Cube" else { return }
            if let time = attributes["time"] { day = time }
            if let code = attributes["currency"], code.count == 3, code.allSatisfy(\.isLetter),
               let text = attributes["rate"], let rate = Double(text), rate.isFinite, rate > 0 {
                rates[code.uppercased()] = rate
            }
        }
    }

    // MARK: - What was typed

    struct Query: Equatable {
        let amount: Double
        let from: String
        let to: String
    }

    /// The currencies the bank publishes, and the euro.
    static let codes: Set<String> = ["EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK",
                                     "CHF", "ISK", "NOK", "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS",
                                     "INR", "KRW", "MXN", "MYR", "NZD", "PHP", "SGD", "THB", "ZAR"]

    /// Symbols and names, in French and English. "$" is the US dollar.
    static let names: [String: String] = [
        "€": "EUR", "euro": "EUR", "euros": "EUR",
        "$": "USD", "dollar": "USD", "dollars": "USD", "dollar us": "USD", "dollars us": "USD",
        "£": "GBP", "livre": "GBP", "livres": "GBP", "livre sterling": "GBP", "livres sterling": "GBP",
        "pound": "GBP", "pounds": "GBP",
        "¥": "JPY", "yen": "JPY", "yens": "JPY", "yuan": "CNY", "yuans": "CNY",
        "franc suisse": "CHF", "francs suisses": "CHF", "swiss franc": "CHF", "swiss francs": "CHF",
        "dollar canadien": "CAD", "dollars canadiens": "CAD", "canadian dollar": "CAD", "canadian dollars": "CAD",
        "dollar australien": "AUD", "dollars australiens": "AUD", "australian dollar": "AUD",
        "australian dollars": "AUD", "real": "BRL", "reais": "BRL", "roupie": "INR", "roupies": "INR",
        "rupee": "INR", "rupees": "INR", "won": "KRW", "zloty": "PLN", "zlotys": "PLN",
        "couronne suédoise": "SEK", "couronnes suédoises": "SEK", "couronne danoise": "DKK",
        "couronnes danoises": "DKK", "couronne norvégienne": "NOK", "couronnes norvégiennes": "NOK",
        "livre turque": "TRY", "livres turques": "TRY", "lira": "TRY", "rand": "ZAR",
    ]

    /// Words that separate the amount from the currency it becomes.
    static let connectors: Set<String> = ["en", "to", "in", "into", "vers", "as", "=", "→", "->"]

    static func currency(_ words: ArraySlice<String>) -> String? {
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        if let named = names[joined] { return named }
        let code = joined.uppercased()
        return words.count == 1 && codes.contains(code) ? code : nil
    }

    /// The conversion asked for, or nil when the text is not one. Without a
    /// target currency the amount becomes `defaultTarget`; an amount already
    /// in it is no question at all.
    static func parse(_ input: String, defaultTarget: String = "EUR",
                      decimalSeparator: String = Locale.current.decimalSeparator ?? ",") -> Query? {
        var text = input.lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "us$", with: " usd ")
        for mark in ["€", "$", "£", "¥", "→", "->", "="] {
            text = text.replacingOccurrences(of: mark, with: " \(mark) ")
        }
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (2...8).contains(tokens.count) else { return nil }

        var source = tokens[...]
        var target: ArraySlice<String> = []
        if let split = tokens.lastIndex(where: connectors.contains), split > 0, split < tokens.count - 1 {
            source = tokens[..<split]
            target = tokens[(split + 1)...]
        }
        // The amount sits before or after the currency, in one block: "1 500,50 €", "€ 20".
        let isNumber: (String) -> Bool = { $0.first?.isNumber == true }
        guard let first = source.firstIndex(where: isNumber),
              let last = source.lastIndex(where: isNumber),
              source[first...last].allSatisfy(isNumber),
              let amount = number(source[first...last].joined(), decimalSeparator: decimalSeparator) else { return nil }
        let words = source[..<first] + source[(last + 1)...]

        let from: String
        let to: String
        if !target.isEmpty {
            guard let named = currency(words[...]), let wanted = currency(target) else { return nil }
            from = named
            to = wanted
        } else if let named = currency(words[...]) {
            from = named
            to = defaultTarget
        } else {
            // "100 usd eur": two currencies side by side.
            let list = Array(words)
            guard let pair = (1..<max(1, list.count)).lazy.compactMap({ cut -> (String, String)? in
                guard let a = currency(list[..<cut]), let b = currency(list[cut...]) else { return nil }
                return (a, b)
            }).first else { return nil }
            (from, to) = pair
        }
        guard from != to, amount.isFinite, amount >= 0 else { return nil }
        return Query(amount: amount, from: from, to: to)
    }

    /// Reads "1500", "1 500,50" (spaces already joined), "1,500.50",
    /// "1.500,50", "12,5". One kind of separator followed by exactly three
    /// digits, other than the Mac's decimal mark, groups thousands.
    static func number(_ text: String, decimalSeparator: String) -> Double? {
        var digits = text.filter { !"'’ ".contains($0) }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }
        let hasDot = digits.contains("."), hasComma = digits.contains(",")
        if hasDot && hasComma {
            let decimal: Character = digits.lastIndex(of: ".")! > digits.lastIndex(of: ",")! ? "." : ","
            digits = digits.filter { $0 != (decimal == "." ? "," : ".") }
            digits = digits.replacingOccurrences(of: String(decimal), with: ".")
        } else if hasDot || hasComma {
            let mark: Character = hasDot ? "." : ","
            let parts = digits.split(separator: mark, omittingEmptySubsequences: false)
            if parts.count > 2 {
                // Several marks only ever group thousands: "1.500.000".
                guard (1...3).contains(parts[0].count), parts.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
                digits = digits.filter { $0 != mark }
            } else {
                let grouped = String(mark) != decimalSeparator && parts[1].count == 3
                digits = grouped ? digits.filter { $0 != mark } : digits.replacingOccurrences(of: String(mark), with: ".")
            }
        }
        guard digits.filter({ $0 == "." }).count <= 1 else { return nil }
        return Double(digits)
    }

    // MARK: - The answer

    static func convert(_ query: Query, rates: Rates) -> Double? {
        guard let from = rates.rate(query.from), let to = rates.rate(query.to) else { return nil }
        let value = query.amount / from * to
        return value.isFinite ? value : nil
    }

    /// "1 627,35 $US" on a French Mac, "$1,627.35" on an American one; the
    /// yen and the won without cents, as their currencies have none.
    static func format(_ amount: Double, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        let whole = ["JPY", "KRW", "HUF", "ISK", "IDR"].contains(currency)
        formatter.minimumFractionDigits = whole ? 0 : 2
        formatter.maximumFractionDigits = whole ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f %@", locale: locale, amount, currency)
    }

    /// The bank's date written the Mac's way, "20/11/2026".
    static func dayText(_ day: String, locale: Locale = .current) -> String {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.timeZone = TimeZone(identifier: "Europe/Berlin")
        reader.dateFormat = "yyyy-MM-dd"
        guard let date = reader.date(from: day) else { return day }
        let writer = DateFormatter()
        writer.locale = locale
        writer.timeZone = reader.timeZone
        writer.dateStyle = .short
        writer.timeStyle = .none
        return writer.string(from: date)
    }

    /// Whether rates saved at `saved` are due for a new download.
    static func isDue(saved: Date?, lastAttempt: Date?, now: Date) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retryInterval { return false }
        guard let saved else { return true }
        return now.timeIntervalSince(saved) >= refreshInterval
    }
}

extension ForkCurrencyLogic {
    /// Set by the fork at launch, read by upstream's command bar (which the
    /// tests compile without the download): the answer row for a conversion.
    static var commandBarAnswer: (String, CommandBarFeatureStrings) -> CommandBarEntry? = { _, _ in nil }
}
