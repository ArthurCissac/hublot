// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation
import NaturalLanguage

/// Translation of the selected text (ForkTranslate): which text, from and to
/// which language, and how tall the fallback panel gets. The translation
/// itself is macOS's own, on the Mac, without network; it shows in the
/// island's Translation page.
enum ForkTranslateLogic {
    /// Longer texts are cut: the page is for a sentence or a paragraph, not a book.
    static let maxCharacters = 5_000

    enum Source: Equatable {
        case selection, clipboard, typed
    }

    struct Request: Equatable {
        let text: String
        let source: Source
        let truncated: Bool
    }

    /// The selection when it holds words, otherwise the clipboard's text;
    /// nil when neither does. Spaces around the text are dropped.
    static func request(selection: String?, clipboard: String?) -> Request? {
        for (raw, source) in [(selection, Source.selection), (clipboard, Source.clipboard)] {
            if let request = request(raw, source: source) { return request }
        }
        return nil
    }

    /// A text typed or pasted in the page itself.
    static func request(typed: String) -> Request? {
        request(typed, source: .typed)
    }

    private static func request(_ raw: String?, source: Source) -> Request? {
        guard let raw else { return nil }
        let trimmed = cleaned(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return nil }
        let truncated = trimmed.count > maxCharacters
        return Request(text: truncated ? String(trimmed.prefix(maxCharacters)) : trimmed,
                       source: source, truncated: truncated)
    }

    /// Apps built on Chrome hand highlighted words over wrapped in what a
    /// screen reader says around them; those words are not the text.
    private static let highlightMarker = try? NSRegularExpression(
        pattern: #"\[(?:(?:Début|Fin) de la mise en surbrillance|(?:Start|End) of highlight)\]"#,
        options: [.caseInsensitive])

    static func cleaned(_ text: String) -> String {
        guard let highlightMarker else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return highlightMarker.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// The text's language as a code such as "fr" or "en", or nil when unclear.
    static func detectedLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    // MARK: - Where it goes

    /// The stored value for "French into English, every other language into French".
    static let automatic = "auto"

    /// The languages macOS's translator handles, in the order the menu lists them.
    static let languages = ["fr", "en", "es", "de", "it", "pt-BR", "nl", "pl", "tr", "ru", "uk",
                            "ar", "hi", "id", "th", "vi", "ja", "ko", "zh-Hans", "zh-Hant"]

    /// The language chosen in the menu, or nil for the automatic direction
    /// (also for a value this version does not know).
    static func preferred(stored: String?) -> String? {
        guard let stored, stored != automatic else { return nil }
        return languages.first { $0 == stored }
    }

    /// Automatic: French text goes to English; any other language, or an
    /// unclear one, to French.
    static func target(forDetected code: String?) -> String {
        guard let code else { return "fr" }
        return sameLanguage(code, "fr") ? "en" : "fr"
    }

    /// With a language chosen, everything goes to it; a text already in it
    /// goes to French, or to English when French is the one chosen.
    static func target(forDetected code: String?, preferred: String?) -> String {
        guard let preferred else { return target(forDetected: code) }
        guard let code, sameLanguage(code, preferred) else { return preferred }
        return sameLanguage(preferred, "fr") ? "en" : "fr"
    }

    /// "pt" and "pt-BR" are one language; the two Chinese scripts are not.
    static func sameLanguage(_ first: String, _ second: String) -> Bool {
        func key(_ code: String) -> String {
            let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
            return lower.hasPrefix("zh") ? lower : String(lower.prefix { $0 != "-" })
        }
        return key(first) == key(second)
    }

    /// Replacing only makes sense for a selection, not for the clipboard or a typed text.
    static func canReplace(_ request: Request) -> Bool {
        request.source == .selection
    }

    // MARK: - The island

    static let pageSymbol = "character.bubble"

    static func title(french: Bool) -> String { french ? "Traduction" : "Translation" }

    static func pageSummary(french: Bool) -> String {
        french ? "Le texte sélectionné, copié ou écrit, traduit par macOS sur ce Mac, dans la langue de votre choix."
            : "The selected, copied or typed text, translated by macOS on this Mac, into the language you choose."
    }

    static func pageAvailable(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: DefaultsKey.forkTranslateEnabled) }

    static func islandControlAvailable(in defaults: UserDefaults) -> Bool { pageAvailable(in: defaults) }

    /// The translation opens in the island when it shows the page; the panel
    /// under the menu bar is for when the island is off or the page hidden.
    static func showsInIsland(islandEnabled: Bool, pageShown: Bool) -> Bool {
        islandEnabled && pageShown
    }

    // MARK: - The fallback panel

    static let panelWidth: CGFloat = 440

    /// The panel's height for its texts: grows with them, then scrolls.
    static func panelHeight(original: String, translated: String?) -> CGFloat {
        func lines(_ text: String, perLine: Int) -> Int {
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(perLine)))) }
        }
        let body = lines(original, perLine: 60) * 16 + lines(translated ?? original, perLine: 48) * 21
        return min(max(CGFloat(190 + body), 270), 560)
    }
}
