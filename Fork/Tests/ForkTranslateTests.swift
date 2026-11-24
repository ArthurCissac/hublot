// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Translation of the selected text (ForkTranslateLogic).
enum ForkTranslateTests {
    typealias Logic = ForkTranslateLogic

    static func run(_ suite: TestSuite) {
        let selected = Logic.request(selection: "  Hello world \n", clipboard: "ignored")
        suite.expect(selected == Logic.Request(text: "Hello world", source: .selection, truncated: false),
               "the selection comes first, without the spaces around it")
        suite.expect(Logic.request(selection: nil, clipboard: "Bonjour")?.source == .clipboard
            && Logic.request(selection: "   ", clipboard: "Bonjour")?.source == .clipboard
            && Logic.request(selection: "42 — 17", clipboard: "Bonjour")?.text == "Bonjour",
               "with no words selected, the clipboard's text is translated")
        suite.expect(Logic.request(selection: nil, clipboard: nil) == nil
            && Logic.request(selection: "", clipboard: "1 234,56") == nil,
               "with no words anywhere, there is nothing to translate")
        let long = String(repeating: "a", count: Logic.maxCharacters + 10)
        let cut = Logic.request(selection: long, clipboard: nil)
        suite.expect(cut?.text.count == Logic.maxCharacters && cut?.truncated == true,
               "a very long text is cut, and says so")

        suite.expect(Logic.detectedLanguage("Bonjour, je voudrais réserver une table pour ce soir.") == "fr"
            && Logic.detectedLanguage("Could you send me the invoice by Friday, please?") == "en",
               "the text's language is recognised")
        suite.expect(Logic.target(forDetected: "fr") == "en" && Logic.target(forDetected: "fr-CA") == "en",
               "French goes to English")
        suite.expect(Logic.target(forDetected: "en") == "fr" && Logic.target(forDetected: "es") == "fr"
            && Logic.target(forDetected: nil) == "fr",
               "every other language, or an unclear one, goes to French")

        suite.expect(Logic.canReplace(Logic.Request(text: "x", source: .selection, truncated: false))
            && !Logic.canReplace(Logic.Request(text: "x", source: .clipboard, truncated: false)),
               "only a selection can be replaced by its translation")

        let short = Logic.panelHeight(original: "Hi", translated: "Salut")
        let tall = Logic.panelHeight(original: long, translated: long)
        suite.expect(short == 230 && tall == 540 && Logic.panelHeight(original: String(repeating: "word ", count: 60), translated: nil) > short,
               "the panel grows with the text, then scrolls")

        for key in [DefaultsKey.forkTranslateEnabled, DefaultsKey.forkTranslateShortcutEnabled] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) is on out of the box and travels in backups")
        }
    }
}
