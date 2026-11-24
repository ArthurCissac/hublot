// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation
import NaturalLanguage

/// Translation of the selected text (ForkTranslate): which text, from and to
/// which language, and how tall the panel gets. The translation itself is
/// macOS's own, on the Mac, without network.
enum ForkTranslateLogic {
    /// Longer texts are cut: the panel is for a sentence or a paragraph, not a book.
    static let maxCharacters = 5_000

    enum Source: Equatable {
        case selection, clipboard
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
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.rangeOfCharacter(from: .letters) != nil else { continue }
            let truncated = trimmed.count > maxCharacters
            return Request(text: truncated ? String(trimmed.prefix(maxCharacters)) : trimmed,
                           source: source, truncated: truncated)
        }
        return nil
    }

    /// The text's language as a code such as "fr" or "en", or nil when unclear.
    static func detectedLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    /// French text goes to English; any other language, or an unclear one, to French.
    static func target(forDetected code: String?) -> String {
        guard let code else { return "fr" }
        return code.lowercased().hasPrefix("fr") ? "en" : "fr"
    }

    /// Replacing only makes sense for a selection, not for the clipboard.
    static func canReplace(_ request: Request) -> Bool {
        request.source == .selection
    }

    static let panelWidth: CGFloat = 440

    /// The panel's height for its texts: grows with them, then scrolls.
    static func panelHeight(original: String, translated: String?) -> CGFloat {
        func lines(_ text: String, perLine: Int) -> Int {
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(perLine)))) }
        }
        let body = lines(original, perLine: 60) * 16 + lines(translated ?? original, perLine: 48) * 21
        return min(max(CGFloat(150 + body), 230), 540)
    }
}
