// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Currencies in the command bar: what reads as a conversion, the bank's
/// file, the arithmetic, the formatting and when to download again.
enum ForkCurrencyTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        numbers(suite)
        rates(suite)
    }

    private typealias Logic = ForkCurrencyLogic

    private static func parsing(_ suite: TestSuite) {
        func parse(_ text: String, _ decimal: String = ",") -> Logic.Query? {
            Logic.parse(text, defaultTarget: "EUR", decimalSeparator: decimal)
        }
        suite.expect(parse("1500 € en $") == .init(amount: 1500, from: "EUR", to: "USD")
            && parse("1500€ en $") == .init(amount: 1500, from: "EUR", to: "USD")
            && parse("1500 eur to usd") == .init(amount: 1500, from: "EUR", to: "USD"),
                     "symbols, codes and connectors, with or without spaces")
        suite.expect(parse("100 usd eur") == .init(amount: 100, from: "USD", to: "EUR")
            && parse("$20 to euros", ".") == .init(amount: 20, from: "USD", to: "EUR")
            && parse("50 francs suisses en dollars") == .init(amount: 50, from: "CHF", to: "USD")
            && parse("100 US$ en £") == .init(amount: 100, from: "USD", to: "GBP"),
                     "two currencies side by side, the amount after the symbol, names in French and English")
        suite.expect(parse("1 500,50 £") == .init(amount: 1500.5, from: "GBP", to: "EUR")
            && parse("1500 $") == .init(amount: 1500, from: "USD", to: "EUR"),
                     "without a target the amount becomes the default currency")
        suite.expect(parse("1500 €") == nil && parse("1500") == nil && parse("3 + 4") == nil
            && parse("100 km en miles") == nil && parse("en $") == nil && parse("dollars en euros") == nil
            && parse("100 xyz en eur") == nil,
                     "an amount already in the default currency, plain sums, units and unknown codes are left alone")
    }

    private static func numbers(_ suite: TestSuite) {
        suite.expect(Logic.number("1500", decimalSeparator: ",") == 1500
            && Logic.number("1.500", decimalSeparator: ",") == 1500
            && Logic.number("12,5", decimalSeparator: ",") == 12.5
            && Logic.number("1,500", decimalSeparator: ".") == 1500
            && Logic.number("12.5", decimalSeparator: ".") == 12.5
            && Logic.number("1,500.50", decimalSeparator: ",") == 1500.5
            && Logic.number("1.500,50", decimalSeparator: ".") == 1500.5
            && Logic.number("1.500.000", decimalSeparator: ",") == 1_500_000
            && Logic.number("1.2.3", decimalSeparator: ",") == nil
            && Logic.number("12a", decimalSeparator: ",") == nil,
                     "thousands and decimals read as the Mac writes them, both marks resolved by the last one")
    }

    private static let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
      <gesmes:subject>Reference rates</gesmes:subject>
      <Cube><Cube time="2026-11-20">
        <Cube currency="USD" rate="1.08"/><Cube currency="JPY" rate="162.5"/>
        <Cube currency="GBP" rate="0.86"/><Cube currency="bad1" rate="2"/><Cube currency="CHF" rate="-1"/>
      </Cube></Cube>
    </gesmes:Envelope>
    """

    private static func rates(_ suite: TestSuite) {
        let parsed = Logic.parseECB(Data(sample.utf8))
        suite.expect(parsed?.day == "2026-11-20" && parsed?.perEuro == ["USD": 1.08, "JPY": 162.5, "GBP": 0.86]
            && Logic.parseECB(Data("<Cube><Cube time='2026-11-20'><Cube currency='USD' rate='1.0990'/></Cube></Cube>".utf8))?
                .perEuro == ["USD": 1.099]
            && Logic.parseECB(Data("not xml".utf8)) == nil
            && Logic.parseECB(Data(repeating: 32, count: Logic.maximumSize + 1)) == nil,
                     "the bank's file gives its day and its rates; broken lines, other files and oversized data are refused")

        guard let rates = parsed else { return }
        let toPounds = Logic.convert(.init(amount: 100, from: "USD", to: "GBP"), rates: rates) ?? 0
        suite.expect(abs(toPounds - 100 / 1.08 * 0.86) < 0.000_001
            && Logic.convert(.init(amount: 10, from: "EUR", to: "JPY"), rates: rates) == 1625
            && Logic.convert(.init(amount: 10, from: "EUR", to: "CHF"), rates: rates) == nil,
                     "conversions cross through the euro; a currency the day lacks gives no answer")

        let french = Locale(identifier: "fr_FR")
        let spaced = Logic.format(1627.35, currency: "USD", locale: french)
            .replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        suite.expect(spaced.contains("1 627,35") && spaced.contains("$")
            && Logic.format(1234.6, currency: "JPY", locale: Locale(identifier: "en_US")) == "¥1,235"
            && Logic.dayText("2026-11-20", locale: french) == "20/11/2026",
                     "amounts and the rates' day are written the Mac's way; the yen has no cents")

        let now = Date()
        suite.expect(Logic.isDue(saved: nil, lastAttempt: nil, now: now)
            && !Logic.isDue(saved: now.addingTimeInterval(-3_600), lastAttempt: nil, now: now)
            && Logic.isDue(saved: now.addingTimeInterval(-13 * 3_600), lastAttempt: nil, now: now)
            && !Logic.isDue(saved: nil, lastAttempt: now.addingTimeInterval(-600), now: now),
                     "rates are fetched when missing or half a day old, never again within an hour of a failure")
    }
}
