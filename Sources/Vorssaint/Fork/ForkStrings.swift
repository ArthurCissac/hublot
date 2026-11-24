// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The few strings the fork adds, in English and French.
///
/// Upstream's catalogs cover every language of `AppLanguage`; these do not, on
/// purpose. They only describe the fork itself, which is a personal build, and
/// any other language falls back to English. The app and upstream names are
/// passed in rather than written here, so renaming the fork stays a one-file
/// change (Fork/identity.sh).
struct ForkStrings {
    let attribution: (_ fork: String, _ upstream: String) -> String
    let forkSource: String
    let upstreamProject: (_ upstream: String) -> String
    let versionLine: (_ fork: String, _ version: String, _ upstream: String, _ base: String) -> String
    let coexistenceTitle: (_ upstream: String) -> String
    let coexistenceMessage: (_ fork: String, _ upstream: String) -> String
    let quit: (_ app: String) -> String
    let keepBoth: String
    let excludeDesktopIconsToggle: String
    let excludeDesktopIconsCaption: String
    let captureSoundToggle: String
    let previewCardToggle: String
    let previewCardCaption: String
    let captureMenuToggle: (_ shortcut: String) -> String
    let captureMenuCaption: String
    let captureMenuArea: String
    let captureMenuFullScreen: String
    let captureMenuWindow: String
    let captureMenuScrolling: String
    let captureMenuTimer: String
    let captureMenuSeconds: (_ seconds: Int) -> String
    let captureMenuText: String
    let captureMenuRecording: String
    let captureMenuAuto: String
    let captureMenuVertical: String
    let captureMenuHorizontal: String
    let captureMenuStart: String
    let captureMenuRecord: String
    let captureMenuMicrophone: String
    let captureMenuSystemAudio: String
    let captureMenuMicOff: String
    let captureMenuCamera: String
    let cameraShapeCircle: String
    let cameraShapeSquare: String
    let cameraShapeRectangle: String
    let noClosedPreview: String
    let titleBarSection: String
    let titleBarSwipeToggle: String
    let titleBarSwipeCaption: String
    let titleBarPinchToggle: String
    let titleBarPinchCaption: String
    let titleBarSwishNote: String
    let switcherGestureToggle: String
    let switcherGestureCaption: String
    let switcherGestureConflict: String
    let switcherGestureOpenTrackpad: String
    let clipboardPaste: String
    let clipboardCharacters: (Int) -> String
    let clipboardColor: String
    let kindText: String
    let kindLink: String
    let kindColor: String
    let kindImage: String
    let kindFile: String
    let kindFiles: String
    let tabHistory: String
    let tabPinned: String
    let newBoard: String
    let boardDefaultName: (Int) -> String
    let renameBoard: String
    let boardColor: String
    let deleteBoard: String
    let fileIn: String
    let removeFromBoard: String
    let pinnedEmpty: String
    let boardEmpty: String
    let colorNames: [String]
    let clipboardShelfToggle: String
    let clipboardShelfCaption: String
    let shelfGlassToggle: String
    let shelfTintToggle: String
    let shelfTintColor: String
    let shelfTintIntensity: String
    let copySoundLabel: String
    let copySoundNone: String
    let areaFormatFree: String
    let settingsRecording: String
    let keysToggle: String
    let keysWhich: String
    let keysShortcutsOnly: String
    let keysAll: String
    let keysCaption: String
    let keySpace: String
    let focusToggle: String
    let focusShortcutsLabel: String
    let focusShortcutsReady: String
    let focusShortcutsToCreate: String
    let focusCreate: String
    let focusCheck: String
    let focusCaption: String
    let focusShortcutsMissing: String
    let micBoostLabel: String
    let micBoostHelp: String
    let imageMirror: String
    let imageStraighten: String
    let imageRotate: String
    let addMusicButton: String
    let musicLaneLabel: String
    let musicVolume: String
    let removeMusic: String
    let musicImportFailed: String
    let cameraAllowed: String
    let cameraRefused: String
    let captureMenuMono: String
    let captureMenuClicks: String
    let captureMenuKeys: String
    let captureMenuBack: String
    let settingsLastRegion: String
    let settingsShortcuts: String
    let settingsFullScreen: String
    let settingsFullScreenCaption: String
    let settingsArea: String
    let settingsAreaCaption: String
    let settingsAfterCapture: String
    let settingsDefaultActionCaption: (_ app: String) -> String
    let settingsFolder: String
    let settingsChoose: String
    let settingsFolderCaption: String
    let settingsInPicture: String
    let settingsPointer: String
    let windowStyleLabel: String
    let windowStylePlain: String
    let windowStyleShadow: String
    let windowStyleBackdrop: String
    let windowStyleCaption: String
    let settingsHideOwnWindows: (_ app: String) -> String
    let settingsHideOwnWindowsCaption: String
    let settingsDelay: String
    let settingsDelayNone: String
    let settingsDelayCaption: String
    let settingsDuringSelection: String
    let settingsFreeze: String
    let settingsFreezeCaption: String
    let settingsShowAll: String
    let settingsHideAll: String
    let settingsAllCaption: String
    let pinRestore: String
    let pinDrag: String
    let pinShrink: String
    let pinEnlarge: String

    func colorName(_ color: ForkClipboardBoards.Color) -> String {
        let index = ForkClipboardBoards.Color.allCases.firstIndex(of: color) ?? 0
        return colorNames.indices.contains(index) ? colorNames[index] : color.rawValue
    }

    static var current: ForkStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkStrings(
        attribution: { fork, upstream in
            "\(fork) is a personal, unofficial fork of \(upstream), under the GPL-3.0-or-later license. "
                + "It is neither published nor endorsed by \(upstream)'s author."
        },
        forkSource: "Source of this fork",
        upstreamProject: { "\($0), the original project" },
        versionLine: { "\($0) \($1), based on \($2) \($3)" },
        coexistenceTitle: { "\($0) is running too" },
        coexistenceMessage: { fork, upstream in
            "\(fork) and \(upstream) react to the same shortcuts and gestures, so each one would fire twice. "
                + "Keep only one of the two apps open."
        },
        quit: { "Quit \($0)" },
        keepBoth: "Keep Both Open",
        excludeDesktopIconsToggle: "Leave desktop icons out of captures",
        excludeDesktopIconsCaption: "The desktop itself is not changed: the icons are simply left out of the picture.",
        captureSoundToggle: "Play a sound when capturing",
        previewCardToggle: "Show the preview as a card at the bottom left",
        previewCardCaption: "Each capture stays at the bottom left of the pointer's display, and the next ones "
            + "stack above it. Click to edit, drag to drop into an app. It replaces the island's preview.",
        captureMenuToggle: { "Capture menu on \($0)" },
        captureMenuCaption: "Draw an area: it stays on screen, framed, with a bar to choose what to do with it. "
            + "Picture, scrolling capture, text, video; or full screen, a window, a delay.",
        captureMenuArea: "Area",
        captureMenuFullScreen: "Full Screen",
        captureMenuWindow: "Window",
        captureMenuScrolling: "Scrolling",
        captureMenuTimer: "Timer",
        captureMenuSeconds: { "\($0) s" },
        captureMenuText: "Text",
        captureMenuRecording: "Video",
        captureMenuAuto: "Auto-scroll",
        captureMenuVertical: "Vertical",
        captureMenuHorizontal: "Horizontal",
        captureMenuStart: "Start",
        captureMenuRecord: "Record",
        captureMenuMicrophone: "Mac mic",
        captureMenuSystemAudio: "Mac audio",
        captureMenuMicOff: "Mic off",
        captureMenuCamera: "Camera",
        cameraShapeCircle: "Round",
        cameraShapeSquare: "Square",
        cameraShapeRectangle: "Rectangle",
        noClosedPreview: "No capture preview to reopen",
        titleBarSection: "Title bar gestures",
        titleBarSwipeToggle: "Swipe on the title bar with two fingers",
        titleBarSwipeCaption: "Left or right: that half of the screen. Toward a corner: that quarter. Up: maximize. Down: minimize. With Shift, left or right: the display on that side. The window under the pointer is laid out, not the active one.",
        titleBarPinchToggle: "Pinch on the title bar",
        titleBarPinchCaption: "Pinch closed: close the window. Spread open: full screen.",
        titleBarSwishNote: "Quit Swish if it is installed: each gesture would act twice.",
        switcherGestureToggle: "Swipe sideways with three fingers",
        switcherGestureCaption: "Opens the switcher and moves through the windows as the fingers travel; lifting them picks the window.",
        switcherGestureConflict: "macOS uses three fingers to move between full-screen apps. Set that to four fingers in Trackpad settings.",
        switcherGestureOpenTrackpad: "Trackpad settings…",
        clipboardPaste: "Paste",
        clipboardCharacters: { $0 == 1 ? "1 character" : "\($0) characters" },
        clipboardColor: "Colour",
        kindText: "Text",
        kindLink: "Link",
        kindColor: "Colour",
        kindImage: "Image",
        kindFile: "File",
        kindFiles: "Files",
        tabHistory: "History",
        tabPinned: "Pinned",
        newBoard: "New pinboard",
        boardDefaultName: { "Pinboard \($0)" },
        renameBoard: "Rename",
        boardColor: "Colour",
        deleteBoard: "Delete pinboard",
        fileIn: "File in",
        removeFromBoard: "Remove from pinboard",
        pinnedEmpty: "No loose pins. Pin an entry with ⌥P or its right-click menu.",
        boardEmpty: "Nothing filed here yet. Right-click a card, then File in.",
        colorNames: ["Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Gray"],
        clipboardShelfToggle: "Open the history as a shelf of cards",
        clipboardShelfCaption: "Along the bottom of the screen, newest first. A click copies a card and closes the shelf. Type to search, arrows to move, Return pastes into the app that was in front, Shift-Return only copies, ⌘1 to ⌘9 paste a card, Space previews, ⌘⌫ deletes, ⌥P pins. Off: the list or the island, as before.",
        shelfGlassToggle: "Liquid Glass",
        shelfTintToggle: "Tint the shelf",
        shelfTintColor: "Colour",
        shelfTintIntensity: "Strength",
        copySoundLabel: "Sound on each copy",
        copySoundNone: "None",
        areaFormatFree: "Free",
        settingsRecording: "Screen recording",
        keysToggle: "Show the keys pressed",
        keysWhich: "Keys shown",
        keysShortcutsOnly: "Shortcuts only",
        keysAll: "All keys",
        keysCaption: "They become captions in the editor, at the bottom of the video, to move, edit or delete. Nothing typed in a password field is seen. Also in the recording bar.",
        keySpace: "Space",
        focusToggle: "Turn on Do Not Disturb while recording",
        focusShortcutsLabel: "Shortcuts",
        focusShortcutsReady: "Found",
        focusShortcutsToCreate: "To create",
        focusCreate: "Create…",
        focusCheck: "Check again",
        focusCaption: "macOS lets no app switch a Focus by itself. Create two shortcuts once in the Shortcuts app: \u{201C}Create…\u{201D} opens them with their names; add to each the action \u{201C}Set Focus\u{201D}, Do Not Disturb, turned on in the first and off in the second. Do Not Disturb is turned off when the recording ends, even if it was on before.",
        focusShortcutsMissing: "Do Not Disturb shortcuts not found: see Settings › Screen Capture",
        micBoostLabel: "Boost",
        micBoostHelp: "Makes the microphone louder than 100 %, up to four times, rounding off the peaks.",
        imageMirror: "Mirror",
        imageStraighten: "Stand upright",
        imageRotate: "Drag to rotate. Shift: 15° steps. Double-click: upright.",
        addMusicButton: "Add music",
        musicLaneLabel: "Music",
        musicVolume: "Music volume",
        removeMusic: "Remove the music",
        musicImportFailed: "This file could not be read as a sound",
        cameraAllowed: "Camera allowed: open the capture menu again",
        cameraRefused: "Camera refused in System Settings › Privacy",
        captureMenuMono: "Mono",
        captureMenuClicks: "Clicks",
        captureMenuKeys: "Keys",
        captureMenuBack: "Back",
        settingsLastRegion: "Outline the previous capture",
        settingsShortcuts: "Shortcuts",
        settingsFullScreen: "Capture the whole screen",
        settingsFullScreenCaption: "Takes the display under the pointer at once, with no menu and no selection.",
        settingsArea: "Capture an area or a window",
        settingsAreaCaption: "Drag for an area, click for a whole window. Escape cancels.",
        settingsAfterCapture: "After a capture",
        settingsDefaultActionCaption: { "What \($0) does by itself with every capture, before the preview even shows." },
        settingsFolder: "Save folder",
        settingsChoose: "Choose…",
        settingsFolderCaption: "Where saved captures go, including the ones a full stack of previews lets go.",
        settingsInPicture: "In the picture",
        settingsPointer: "Include the mouse pointer",
        windowStyleLabel: "Window capture",
        windowStylePlain: "As it is",
        windowStyleShadow: "With its shadow",
        windowStyleBackdrop: "On a background",
        windowStyleCaption: "The shadow comes on a transparent background. The background is the one last chosen in the screenshot editor.",
        settingsHideOwnWindows: { "Hide \($0)’s windows" },
        settingsHideOwnWindowsCaption: "Settings, the editor and pinned captures stay out of the picture.",
        settingsDelay: "Delay before the capture",
        settingsDelayNone: "None",
        settingsDelayCaption: "Time to open a menu or place the pointer before the screen is taken.",
        settingsDuringSelection: "While selecting",
        settingsFreeze: "Freeze the screen",
        settingsFreezeCaption: "The screen is photographed as the selection opens: a video or an animation "
            + "holds still while the area is chosen.",
        settingsShowAll: "All settings",
        settingsHideAll: "Hide the other settings",
        settingsAllCaption: "Loupe, shelf, file names, links, and the settings for video, text and color.",
        pinRestore: "Back to the previews",
        pinDrag: "Drag into an app",
        pinShrink: "Shrink",
        pinEnlarge: "Enlarge"
    )

    static let french = ForkStrings(
        attribution: { fork, upstream in
            "\(fork) est un fork personnel et non officiel de \(upstream), sous licence GPL-3.0-or-later. "
                + "Il n’est ni publié ni soutenu par l’auteur de \(upstream)."
        },
        forkSource: "Sources de ce fork",
        upstreamProject: { "\($0), le projet d’origine" },
        versionLine: { "\($0) \($1), basé sur \($2) \($3)" },
        coexistenceTitle: { "\($0) est aussi lancé" },
        coexistenceMessage: { fork, upstream in
            "\(fork) et \(upstream) réagissent aux mêmes raccourcis et aux mêmes gestes : "
                + "chacun se déclencherait deux fois. Ne gardez qu’une des deux apps ouverte."
        },
        quit: { "Quitter \($0)" },
        keepBoth: "Garder les deux",
        excludeDesktopIconsToggle: "Capturer sans les icônes du bureau",
        excludeDesktopIconsCaption: "Le bureau n’est pas modifié : les icônes sont simplement absentes de l’image.",
        captureSoundToggle: "Jouer un son à la capture",
        previewCardToggle: "Afficher l’aperçu en carte, en bas à gauche",
        previewCardCaption: "Chaque capture reste en bas à gauche de l’écran du pointeur, et les suivantes "
            + "s’empilent au-dessus. Cliquer pour modifier, glisser pour déposer dans une app. Remplace l’aperçu de l’île.",
        captureMenuToggle: { "Menu de capture sur \($0)" },
        captureMenuCaption: "Tracer une zone : elle reste à l’écran, encadrée, avec une barre pour choisir quoi en "
            + "faire. Image, capture défilante, texte, vidéo ; ou plein écran, fenêtre, délai.",
        captureMenuArea: "Zone",
        captureMenuFullScreen: "Plein écran",
        captureMenuWindow: "Fenêtre",
        captureMenuScrolling: "Défilante",
        captureMenuTimer: "Minuteur",
        captureMenuSeconds: { "\($0) s" },
        captureMenuText: "Texte",
        captureMenuRecording: "Vidéo",
        captureMenuAuto: "Défil. auto",
        captureMenuVertical: "Verticale",
        captureMenuHorizontal: "Horizontale",
        captureMenuStart: "Démarrer",
        captureMenuRecord: "Enregistrer",
        captureMenuMicrophone: "Micro Mac",
        captureMenuSystemAudio: "Son du Mac",
        captureMenuMicOff: "Micro coupé",
        captureMenuCamera: "Caméra",
        cameraShapeCircle: "Rond",
        cameraShapeSquare: "Carré",
        cameraShapeRectangle: "Rectangle",
        noClosedPreview: "Aucun aperçu de capture à rouvrir",
        titleBarSection: "Gestes sur la barre de titre",
        titleBarSwipeToggle: "Balayer la barre de titre à deux doigts",
        titleBarSwipeCaption: "À gauche ou à droite : cette moitié de l’écran. Vers un coin : ce quart. Vers le haut : agrandir. Vers le bas : réduire. Avec Maj, à gauche ou à droite : l’écran de ce côté. C’est la fenêtre sous le pointeur qui est rangée, pas la fenêtre active.",
        titleBarPinchToggle: "Pincer la barre de titre",
        titleBarPinchCaption: "Pincer pour fermer la fenêtre, écarter pour la mettre en plein écran.",
        titleBarSwishNote: "Quittez Swish s’il est installé : chaque geste agirait deux fois.",
        switcherGestureToggle: "Balayer à trois doigts sur le côté",
        switcherGestureCaption: "Ouvre le sélecteur et passe d’une fenêtre à l’autre à mesure que les doigts avancent ; les lever choisit la fenêtre.",
        switcherGestureConflict: "macOS utilise trois doigts pour passer d’une app en plein écran à l’autre. Réglez-le sur quatre doigts dans les réglages du trackpad.",
        switcherGestureOpenTrackpad: "Réglages du trackpad…",
        clipboardPaste: "Coller",
        clipboardCharacters: { $0 <= 1 ? "\($0) caractère" : "\($0) caractères" },
        clipboardColor: "Couleur",
        kindText: "Texte",
        kindLink: "Lien",
        kindColor: "Couleur",
        kindImage: "Image",
        kindFile: "Fichier",
        kindFiles: "Fichiers",
        tabHistory: "Historique",
        tabPinned: "Épinglés",
        newBoard: "Nouveau tableau",
        boardDefaultName: { "Tableau \($0)" },
        renameBoard: "Renommer",
        boardColor: "Couleur",
        deleteBoard: "Supprimer le tableau",
        fileIn: "Ranger dans",
        removeFromBoard: "Retirer du tableau",
        pinnedEmpty: "Aucun épinglé libre. Épinglez un élément avec ⌥P ou son clic droit.",
        boardEmpty: "Rien de rangé ici. Clic droit sur une carte, puis Ranger dans.",
        colorNames: ["Rouge", "Orange", "Jaune", "Vert", "Turquoise", "Bleu", "Violet", "Rose", "Gris"],
        clipboardShelfToggle: "Ouvrir l’historique en bandeau de cartes",
        clipboardShelfCaption: "En bas de l’écran, le plus récent d’abord. Un clic copie une carte et ferme le bandeau. Tapez pour chercher, flèches pour se déplacer, Entrée colle dans l’app qui était devant, Maj-Entrée copie seulement, ⌘1 à ⌘9 collent une carte, Espace l’agrandit, ⌘⌫ la supprime, ⌥P l’épingle. Désactivé : la liste ou l’île, comme avant.",
        shelfGlassToggle: "Liquid Glass",
        shelfTintToggle: "Teinter le bandeau",
        shelfTintColor: "Couleur",
        shelfTintIntensity: "Intensité",
        copySoundLabel: "Son à chaque copie",
        copySoundNone: "Aucun",
        areaFormatFree: "Libre",
        settingsRecording: "Enregistrement vidéo",
        keysToggle: "Afficher les touches pressées",
        keysWhich: "Touches affichées",
        keysShortcutsOnly: "Raccourcis seulement",
        keysAll: "Toutes les touches",
        keysCaption: "Elles deviennent des textes dans l’éditeur, en bas de la vidéo, à déplacer, modifier ou supprimer. Rien de ce qui est tapé dans un champ de mot de passe n’est vu. Aussi dans le volet vidéo.",
        keySpace: "Espace",
        focusToggle: "Activer Ne pas déranger pendant l’enregistrement",
        focusShortcutsLabel: "Raccourcis",
        focusShortcutsReady: "Trouvés",
        focusShortcutsToCreate: "À créer",
        focusCreate: "Créer…",
        focusCheck: "Vérifier à nouveau",
        focusCaption: "macOS ne laisse aucune app changer de mode de concentration seule. Créez une fois deux raccourcis dans l’app Raccourcis : « Créer… » les ouvre avec leur nom ; ajoutez à chacun l’action « Définir la concentration », Ne pas déranger, activée dans le premier et désactivée dans le second. Ne pas déranger est désactivé à la fin de l’enregistrement, même s’il était actif avant.",
        focusShortcutsMissing: "Raccourcis Ne pas déranger introuvables : voir Réglages › Capture d’écran",
        micBoostLabel: "Amplifier",
        micBoostHelp: "Rend le micro plus fort que 100 %, jusqu’à quatre fois, en adoucissant les crêtes.",
        imageMirror: "Miroir",
        imageStraighten: "Remettre droit",
        imageRotate: "Glisser pour faire pivoter. Maj : par 15°. Double-clic : droit.",
        addMusicButton: "Ajouter une musique",
        musicLaneLabel: "Musique",
        musicVolume: "Volume de la musique",
        removeMusic: "Retirer la musique",
        musicImportFailed: "Ce fichier n’a pas pu être lu comme un son",
        cameraAllowed: "Caméra autorisée : rouvrir le menu de capture",
        cameraRefused: "Caméra refusée dans Réglages Système › Confidentialité",
        captureMenuMono: "Mono",
        captureMenuClicks: "Clics",
        captureMenuKeys: "Touches",
        captureMenuBack: "Retour",
        settingsLastRegion: "Afficher le contour de la capture précédente",
        settingsShortcuts: "Raccourcis",
        settingsFullScreen: "Capturer tout l’écran",
        settingsFullScreenCaption: "Capture immédiate de l’écran où se trouve le pointeur, sans menu ni sélection.",
        settingsArea: "Capturer une zone ou une fenêtre",
        settingsAreaCaption: "Glisser pour une zone, cliquer pour une fenêtre entière. Échap annule.",
        settingsAfterCapture: "Après la capture",
        settingsDefaultActionCaption: { "Ce que \($0) fait de lui-même à chaque capture, avant même l’aperçu." },
        settingsFolder: "Dossier d’enregistrement",
        settingsChoose: "Choisir…",
        settingsFolderCaption: "Là où vont les captures enregistrées, y compris celles qu’une pile d’aperçus "
            + "pleine laisse partir.",
        settingsInPicture: "Dans l’image",
        settingsPointer: "Inclure le pointeur de la souris",
        windowStyleLabel: "Capture d’une fenêtre",
        windowStylePlain: "Telle quelle",
        windowStyleShadow: "Avec son ombre",
        windowStyleBackdrop: "Sur un fond",
        windowStyleCaption: "L’ombre vient sur un fond transparent. Le fond est le dernier choisi dans l’éditeur de capture.",
        settingsHideOwnWindows: { "Masquer les fenêtres de \($0)" },
        settingsHideOwnWindowsCaption: "Les réglages, l’éditeur et les captures épinglées ne figurent pas dans l’image.",
        settingsDelay: "Délai avant la capture",
        settingsDelayNone: "Aucun",
        settingsDelayCaption: "Le temps d’ouvrir un menu ou de placer le pointeur avant la prise de vue.",
        settingsDuringSelection: "Pendant la sélection",
        settingsFreeze: "Figer l’écran",
        settingsFreezeCaption: "L’écran est photographié à l’ouverture de la sélection : une vidéo ou une "
            + "animation ne bouge plus pendant le choix de la zone.",
        settingsShowAll: "Tous les réglages",
        settingsHideAll: "Masquer les autres réglages",
        settingsAllCaption: "Loupe, étagère, nom des fichiers, liens, et les réglages de la vidéo, du texte et de la couleur.",
        pinRestore: "Remettre dans les aperçus",
        pinDrag: "Glisser vers une app",
        pinShrink: "Réduire",
        pinEnlarge: "Agrandir"
    )
}

/// The texts of the Swish-style gestures' settings, kept apart from the main
/// list so the page's many captions do not crowd it.
struct ForkSwishStrings {
    let section: String
    let swishRunning: String
    let quitSwish: String
    let pinchTwiceCaption: String
    let doubleTapToggle: String
    let doubleTapCaption: String
    let dockToggle: String
    let dockCaption: String
    let previewToggle: String
    let hapticToggle: String
    let hapticCaption: String
    let listenerToggle: String
    let listenerCaption: String
    let sensitivity: String
    let sensitivityCaption: String
    let cancelTimeout: (_ seconds: Double) -> String
    let cancelCaption: String
    let moveCursorToggle: String
    let modifiersSection: String
    let superModifier: String
    let superCaption: String
    let requireSuper: String
    let generalModifier: String
    let generalCaption: String
    let screenModifier: String
    let screenCaption: String
    let secondaryModifier: String
    let secondaryCaption: String
    let tertiaryModifier: String
    let tertiaryCaption: String
    let keyboardSection: String
    let arrowKeysToggle: (_ superKey: String) -> String
    let arrowKeysCaption: (_ screenKey: String) -> String
    let arrowKeysFailed: String
    let importSection: String
    let importButton: String
    let importCaption: String
    let importDone: (_ count: Int) -> String
    let importNone: String
    let bubbleToggle: String
    let bubbleCaption: String
    let liveMoveToggle: String
    let liveMoveCaption: String
    let previewCaption: String
    let actionClose: String
    let actionQuit: String
    let actionMinimize: String
    let actionMinimizeAll: String
    let actionUnminimize: String
    let actionUnminimizeAll: String
    let actionNextWindow: String
    let actionPreviousWindow: String
    let actionDisplay: (_ direction: ForkTitleBarGestureLogic.Direction) -> String
    let actionCell: (_ column: Int, _ row: Int) -> String

    static var current: ForkSwishStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkSwishStrings(
        section: "Title bar gestures",
        swishRunning: "Swish is running: every gesture would act twice.",
        quitSwish: "Quit Swish",
        pinchTwiceCaption: "Pinch closed twice in a row: quit the app.",
        doubleTapToggle: "Double-tap the title bar with two fingers",
        doubleTapCaption: "Centers the window.",
        dockToggle: "Gestures on Dock icons",
        dockCaption: "Two fingers on the icon of a running app. Left or right: go through its windows. Down: minimize its front window. Up: bring back its last minimized window. Pinch closed: quit the app. With the secondary modifier, down and up act on all its windows.",
        previewToggle: "Show where the window will go during a swipe",
        hapticToggle: "Haptic feedback",
        hapticCaption: "The trackpad taps once when a gesture acts, if force feedback is on in Trackpad settings.",
        listenerToggle: "Hold back scrolling during a gesture",
        listenerCaption: "The window under the fingers neither scrolls nor zooms while a title bar gesture lasts.",
        sensitivity: "Sensitivity",
        sensitivityCaption: "The lower it is, the farther a swipe has to travel.",
        cancelTimeout: { String(format: "Cancel after resting %.1f s", locale: Locale(identifier: "en_US"), $0) },
        cancelCaption: "Escape also cancels a gesture under way.",
        moveCursorToggle: "The pointer follows a window it lays out or sends to another display",
        modifiersSection: "Gesture modifiers",
        superModifier: "Super",
        superCaption: "Held, gestures work anywhere in a window, not only on its title bar. Combines with the others.",
        requireSuper: "Require the super modifier for every gesture",
        generalModifier: "General",
        generalCaption: "Swipe down: close the window; twice: quit the app. Up: almost full screen.",
        screenModifier: "Screen",
        screenCaption: "Swipe toward a display to send the window there, in all four directions; it fills that display.",
        secondaryModifier: "Secondary",
        secondaryCaption: "3×2 grid: toward a corner, that sixth. Up or down: the top or bottom half. Left or right: that third.",
        tertiaryModifier: "Tertiary",
        tertiaryCaption: "3×3 grid: toward an edge or a corner, that cell.",
        keyboardSection: "Keyboard",
        arrowKeysToggle: { "\($0) + arrow keys" },
        arrowKeysCaption: { "Left or right: that half. Up: maximize. Down: minimize. Two arrows in a row (left then up, say): that quarter. With \($0) as well: the display that way. As with Swish, apps no longer get these keys (start or end of a line or document, Finder's enclosing folder); apps left alone below keep them." },
        arrowKeysFailed: "Another app, or another shortcut of this app, already holds one of these combinations.",
        importSection: "Moving over from Swish",
        importButton: "Take my Swish settings",
        importCaption: "Reads Swish's preferences on this Mac (modifiers, arrow keys, sensitivity, live preview, pointer) and copies them here.",
        importDone: { "\($0) settings taken from Swish." },
        importNone: "Swish has no preferences on this Mac.",
        bubbleToggle: "Action bubble by the pointer",
        bubbleCaption: "During a gesture, a bubble shows what it is about to do: close, quit, minimize, full screen, or where the window goes.",
        liveMoveToggle: "The window glides into place during the swipe",
        liveMoveCaption: "It follows the fingers from one place to the next, and glides back if the gesture is called off.",
        previewCaption: "Shown when the window does not glide during the swipe.",
        actionClose: "Close window",
        actionQuit: "Quit app",
        actionMinimize: "Minimize",
        actionMinimizeAll: "Minimize all windows",
        actionUnminimize: "Bring window back",
        actionUnminimizeAll: "Bring all windows back",
        actionNextWindow: "Next window",
        actionPreviousWindow: "Previous window",
        actionDisplay: { direction in
            switch direction {
            case .left: return "Display on the left"
            case .right: return "Display on the right"
            case .up: return "Display above"
            default: return "Display below"
            }
        },
        actionCell: { column, row in
            let rows = ["Top", "Middle", "Bottom"], columns = ["left", "center", "right"]
            return row == 1 && column == 1 ? "Center" : "\(rows[max(0, min(2, row))]) \(columns[max(0, min(2, column))])"
        }
    )

    static let french = ForkSwishStrings(
        section: "Gestes sur la barre de titre",
        swishRunning: "Swish est ouvert : chaque geste agirait deux fois.",
        quitSwish: "Quitter Swish",
        pinchTwiceCaption: "Pincer deux fois de suite : quitter l’app.",
        doubleTapToggle: "Toucher deux fois la barre de titre à deux doigts",
        doubleTapCaption: "Centre la fenêtre.",
        dockToggle: "Gestes sur les icônes du Dock",
        dockCaption: "Deux doigts sur l’icône d’une app ouverte. À gauche ou à droite : passer d’une de ses fenêtres à l’autre. Vers le bas : réduire sa fenêtre de devant. Vers le haut : faire revenir sa dernière fenêtre réduite. Pincer : quitter l’app. Avec le modificateur secondaire, le bas et le haut agissent sur toutes ses fenêtres.",
        previewToggle: "Montrer où ira la fenêtre pendant un balayage",
        hapticToggle: "Retour haptique",
        hapticCaption: "Le trackpad tape une fois quand un geste agit, si le retour de force est activé dans les réglages du trackpad.",
        listenerToggle: "Bloquer le défilement pendant un geste",
        listenerCaption: "La fenêtre sous les doigts ne défile pas et ne zoome pas tant que dure un geste sur la barre de titre.",
        sensitivity: "Sensibilité",
        sensitivityCaption: "Plus elle est basse, plus il faut balayer loin.",
        cancelTimeout: { String(format: "Annuler après %.1f s d’immobilité", locale: Locale(identifier: "fr_FR"), $0) },
        cancelCaption: "Échap annule aussi un geste en cours.",
        moveCursorToggle: "Le pointeur suit la fenêtre placée ou envoyée sur un autre écran",
        modifiersSection: "Modificateurs des gestes",
        superModifier: "Super",
        superCaption: "Maintenu, les gestes marchent partout dans une fenêtre, pas seulement sur sa barre de titre. Se combine avec les autres.",
        requireSuper: "Exiger le super modificateur pour tous les gestes",
        generalModifier: "Général",
        generalCaption: "Balayer vers le bas : fermer la fenêtre ; deux fois : quitter l’app. Vers le haut : presque plein écran.",
        screenModifier: "Écran",
        screenCaption: "Balayer vers un écran y envoie la fenêtre, dans les quatre directions ; elle y prend tout l’écran.",
        secondaryModifier: "Secondaire",
        secondaryCaption: "Grille 3×2 : vers un coin, ce sixième. Vers le haut ou le bas : la moitié haute ou basse. À gauche ou à droite : ce tiers.",
        tertiaryModifier: "Tertiaire",
        tertiaryCaption: "Grille 3×3 : vers un bord ou un coin, cette case.",
        keyboardSection: "Clavier",
        arrowKeysToggle: { "\($0) + flèches" },
        arrowKeysCaption: { "À gauche ou à droite : cette moitié. Vers le haut : agrandir. Vers le bas : réduire. Deux flèches de suite (gauche puis haut, par exemple) : ce quart. Avec \($0) en plus : l’écran dans cette direction. Comme avec Swish, les apps ne reçoivent plus ces touches (début ou fin de ligne ou de document, dossier parent du Finder) ; les apps ignorées plus bas les gardent." },
        arrowKeysFailed: "Une autre app, ou un autre raccourci de cette app, tient déjà une de ces combinaisons.",
        importSection: "Reprise depuis Swish",
        importButton: "Reprendre mes réglages Swish",
        importCaption: "Relit les préférences de Swish sur ce Mac (modificateurs, flèches, sensibilité, aperçu, pointeur) et les recopie ici.",
        importDone: { "\($0) réglages repris de Swish." },
        importNone: "Swish n’a pas de préférences sur ce Mac.",
        bubbleToggle: "Bulle d’action près du pointeur",
        bubbleCaption: "Pendant un geste, une bulle montre ce qu’il va faire : fermer, quitter, réduire, plein écran, ou la place de la fenêtre.",
        liveMoveToggle: "La fenêtre glisse vers sa place pendant le balayage",
        liveMoveCaption: "Elle suit les doigts d’une place à l’autre, et revient si le geste est annulé.",
        previewCaption: "Affiché quand la fenêtre ne glisse pas pendant le balayage.",
        actionClose: "Fermer la fenêtre",
        actionQuit: "Quitter l’app",
        actionMinimize: "Réduire",
        actionMinimizeAll: "Réduire toutes les fenêtres",
        actionUnminimize: "Faire revenir la fenêtre",
        actionUnminimizeAll: "Faire revenir toutes les fenêtres",
        actionNextWindow: "Fenêtre suivante",
        actionPreviousWindow: "Fenêtre précédente",
        actionDisplay: { direction in
            switch direction {
            case .left: return "Écran de gauche"
            case .right: return "Écran de droite"
            case .up: return "Écran du dessus"
            default: return "Écran du dessous"
            }
        },
        actionCell: { column, row in
            let rows = ["En haut", "Au milieu", "En bas"], columns = ["à gauche", "au centre", "à droite"]
            return row == 1 && column == 1 ? "Au centre" : "\(rows[max(0, min(2, row))]) \(columns[max(0, min(2, column))])"
        }
    )
}

/// The texts of the capture menu's settings.
struct ForkCaptureMenuStrings {
    let section: (_ shortcut: String) -> String
    let shortcut: String
    let opening: String
    let openingBar: String
    let openingLastArea: String
    let openingSelect: String
    let areaAtOnce: String
    let areaAtOnceCaption: String
    let items: String
    let itemsCaption: String
    let moveUp: String
    let moveDown: String
    let defaultOrder: String

    static var current: ForkCaptureMenuStrings {
        L10n.shared.language == .fr ? french : english
    }

    func name(of opening: ForkCaptureMenuLayout.Opening) -> String {
        switch opening {
        case .bar: return openingBar
        case .lastArea: return openingLastArea
        case .select: return openingSelect
        }
    }

    static let english = ForkCaptureMenuStrings(
        section: { "Capture menu (\($0))" },
        shortcut: "Shortcut",
        opening: "On opening",
        openingBar: "The bar alone",
        openingLastArea: "The last area, framed",
        openingSelect: "Draw an area at once",
        areaAtOnce: "“Area” captures as soon as the area is drawn",
        areaAtOnceCaption: "As with Shift-Command-4. Otherwise the area stays framed to be adjusted; “Area” or Return takes it.",
        items: "Items of the bar",
        itemsCaption: "Tick the items to show and order them with the arrows. One item at least stays shown.",
        moveUp: "Move up",
        moveDown: "Move down",
        defaultOrder: "Default order"
    )

    static let french = ForkCaptureMenuStrings(
        section: { "Menu de capture (\($0))" },
        shortcut: "Raccourci",
        opening: "À l’ouverture",
        openingBar: "La barre seule",
        openingLastArea: "La dernière zone, encadrée",
        openingSelect: "Tracer une zone tout de suite",
        areaAtOnce: "« Zone » capture dès que la zone est tracée",
        areaAtOnceCaption: "Comme ⇧⌘4. Sinon, la zone reste encadrée pour être ajustée ; « Zone » ou Entrée la capture.",
        items: "Boutons de la barre",
        itemsCaption: "Cochez les boutons à afficher et rangez-les avec les flèches. Un bouton au moins reste affiché.",
        moveUp: "Monter",
        moveDown: "Descendre",
        defaultOrder: "Ordre par défaut"
    )
}

/// The texts the fork adds to the shelf's settings.
struct ForkShelfStrings {
    let dragTopGuardToggle: String
    let dragTopGuardCaption: String

    static var current: ForkShelfStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkShelfStrings(
        dragTopGuardToggle: "No Mission Control while dragging to the top of the screen",
        dragTopGuardCaption: "During a drag and drop, the pointer never rests on a top edge: it goes straight onto the display above when there is one, and stops one point under the edge otherwise. A file reaches the island's shelf, or the other display, without macOS opening Mission Control. Moving a window is not affected."
    )

    static let french = ForkShelfStrings(
        dragTopGuardToggle: "Pas de Mission Control en glissant vers le haut de l’écran",
        dragTopGuardCaption: "Pendant un glisser-déposer, le pointeur ne reste jamais sur un bord du haut : il passe directement sur l’écran du dessus s’il y en a un, et s’arrête à un point du bord sinon. Un fichier arrive à l’étagère de l’île, ou sur l’autre écran, sans que macOS ouvre Mission Control. Déplacer une fenêtre n’est pas concerné."
    )
}

/// The texts of the trackpad switcher's setting.
struct ForkSwitcherStrings {
    let toggle: (_ fingers: Int) -> String
    let fingers: String
    let conflict: (_ fingers: Int) -> String

    static var current: ForkSwitcherStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkSwitcherStrings(
        toggle: { "Swipe sideways with \($0 == 4 ? "four" : "three") fingers" },
        fingers: "Fingers",
        conflict: { fingers in
            fingers == 4
                ? "macOS also uses four fingers to move between full-screen apps. In Trackpad settings, choose to swipe with three fingers only."
                : "macOS uses three fingers to move between full-screen apps. Set that to four fingers in Trackpad settings, or use four fingers here."
        }
    )

    static let french = ForkSwitcherStrings(
        toggle: { "Balayer à \($0 == 4 ? "quatre" : "trois") doigts sur le côté" },
        fingers: "Doigts",
        conflict: { fingers in
            fingers == 4
                ? "macOS utilise aussi quatre doigts pour passer d’une app en plein écran à l’autre. Dans les réglages du trackpad, choisissez de balayer avec trois doigts seulement."
                : "macOS utilise trois doigts pour passer d’une app en plein écran à l’autre. Réglez-le sur quatre doigts dans les réglages du trackpad, ou choisissez quatre doigts ici."
        }
    )
}

/// The texts of the capture previews' shortcuts.
struct ForkPreviewStrings {
    let reopenToggle: String
    let reopenCaption: String
    let hideToggle: String
    let hideCaption: String
    let hidden: String
    let shown: String
    let noneToHide: String
    let shortcutTaken: String

    static var current: ForkPreviewStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkPreviewStrings(
        reopenToggle: "Reopen the last preview",
        reopenCaption: "Brings back the last capture preview put away.",
        hideToggle: "Hide all previews",
        hideCaption: "Hides the capture previews for a moment, out of the way; the same shortcut, or the next capture, brings them back.",
        hidden: "Previews hidden",
        shown: "Previews back",
        noneToHide: "No capture preview to hide",
        shortcutTaken: "Another app, or another shortcut of this app, already holds this combination."
    )

    static let french = ForkPreviewStrings(
        reopenToggle: "Rouvrir le dernier aperçu",
        reopenCaption: "Fait revenir le dernier aperçu de capture rangé.",
        hideToggle: "Masquer tous les aperçus",
        hideCaption: "Masque un moment les aperçus de capture pour dégager l’écran ; le même raccourci, ou la capture suivante, les fait revenir.",
        hidden: "Aperçus masqués",
        shown: "Aperçus revenus",
        noneToHide: "Aucun aperçu de capture à masquer",
        shortcutTaken: "Une autre app, ou un autre raccourci de cette app, tient déjà cette combinaison."
    )
}

/// The texts the fork adds to the island's music page and its settings.
struct ForkMusicStrings {
    let nearbyDurationToggle: String
    let nearbyDurationCaption: String
    let spotifyToggle: String
    let spotifyCaption: (_ app: String, _ redirect: String) -> String
    let clientID: String
    let clientIDPrompt: String
    let clientIDHint: String
    let clientIDInvalid: String
    let account: String
    let connect: String
    let disconnect: String
    let connected: String
    let notConnected: String
    let waiting: String
    let failed: String
    let browserConnected: (_ app: String) -> String
    let browserFailed: (_ app: String) -> String

    static var current: ForkMusicStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkMusicStrings(
        nearbyDurationToggle: "Accept lyrics a few seconds off",
        nearbyDurationCaption: "When a player such as Spotify reports a length up to 8 seconds away from the catalog’s, lyrics of the same song and album still show. If they run early or late, shift them with − and + under the lyrics. When no version is that close, the words of the nearest one show, without scrolling along.",
        spotifyToggle: "Spotify queue",
        spotifyCaption: { app, redirect in
            "Spotify does not share its queue with macOS: \(app) reads it through Spotify’s Web API, only while the queue page is open. Create an app on developer.spotify.com with the redirect URI \(redirect) and the Web API, then paste its Client ID here. Read only: a queued song cannot be played from the island."
        },
        clientID: "Client ID",
        clientIDPrompt: "32 letters and digits",
        clientIDHint: "From your app’s page on developer.spotify.com. It is not a secret.",
        clientIDInvalid: "This is not a Spotify Client ID: it has 32 letters and digits.",
        account: "Spotify account",
        connect: "Connect Spotify",
        disconnect: "Disconnect",
        connected: "Connected. The sign-in is kept in the Keychain of this Mac.",
        notConnected: "Not connected.",
        waiting: "Waiting for the browser…",
        failed: "The connection failed. Check the Client ID and the redirect URI of your Spotify app, then try again.",
        browserConnected: { "\($0) is connected to Spotify. You can close this tab." },
        browserFailed: { "The connection to Spotify did not go through. Go back to \($0) to try again." }
    )

    static let french = ForkMusicStrings(
        nearbyDurationToggle: "Accepter des paroles à quelques secondes près",
        nearbyDurationCaption: "Quand un lecteur comme Spotify annonce une durée jusqu’à 8 secondes différente de celle du catalogue, les paroles du même titre et du même album s’affichent quand même. En avance ou en retard, décalez-les avec − et + sous les paroles. Si aucune version n’est aussi proche, le texte de la plus proche s’affiche, sans défiler avec la musique.",
        spotifyToggle: "File d’attente de Spotify",
        spotifyCaption: { app, redirect in
            "Spotify ne partage pas sa file avec macOS : \(app) la lit par l’API Web de Spotify, seulement quand la page File est ouverte. Créez une app sur developer.spotify.com avec l’adresse de retour \(redirect) et l’API Web, puis collez son Client ID ici. Lecture seule : un morceau de la file ne se lance pas depuis l’île."
        },
        clientID: "Client ID",
        clientIDPrompt: "32 lettres et chiffres",
        clientIDHint: "Sur la page de votre app, sur developer.spotify.com. Ce n’est pas un secret.",
        clientIDInvalid: "Ce n’est pas un Client ID Spotify : il compte 32 lettres et chiffres.",
        account: "Compte Spotify",
        connect: "Connecter Spotify",
        disconnect: "Déconnecter",
        connected: "Connecté. La connexion est gardée dans le trousseau de ce Mac.",
        notConnected: "Non connecté.",
        waiting: "En attente du navigateur…",
        failed: "La connexion a échoué. Vérifiez le Client ID et l’adresse de retour de votre app Spotify, puis réessayez.",
        browserConnected: { "\($0) est connecté à Spotify. Vous pouvez fermer cet onglet." },
        browserFailed: { "La connexion à Spotify n’a pas abouti. Revenez dans \($0) pour réessayer." }
    )
}

/// The texts of the fork's scrolling capture controls, and of their settings.
struct ForkScrollingStrings {
    let cancel: String
    let done: String
    let auto: String
    let autoOnDown: String
    let autoOnRight: String
    let autoHelpDown: String
    let autoHelpRight: String
    let noPage: String
    let section: String
    let controlsToggle: String
    let controlsCaption: String
    let horizontalToggle: String
    let horizontalCaption: String

    static var current: ForkScrollingStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkScrollingStrings(
        cancel: "Cancel",
        done: "Done",
        auto: "Auto-scroll",
        autoOnDown: "Move the pointer down",
        autoOnRight: "Move the pointer right",
        autoHelpDown: "The lower the pointer, the faster the page scrolls. Move it back up to slow down; it stops where you clicked.",
        autoHelpRight: "The further right the pointer, the faster the page scrolls. Move it back to slow down; it stops where you clicked.",
        noPage: "No page to scroll under the area",
        section: "Scrolling capture",
        controlsToggle: "Auto-scroll steered by the pointer",
        controlsCaption: "Cancel, Auto-scroll and Done sit above the area. Once Auto-scroll is on, the lower the pointer, the faster the page scrolls; back where you clicked, it stops. Scrolling by hand still works. Return finishes, Escape cancels.",
        horizontalToggle: "Scroll sideways from the capture menu",
        horizontalCaption: "Scrolling captures started from the capture menu follow the page to the right instead of down."
    )

    static let french = ForkScrollingStrings(
        cancel: "Annuler",
        done: "Terminer",
        auto: "Défilement auto",
        autoOnDown: "Descendez le curseur",
        autoOnRight: "Allez vers la droite",
        autoHelpDown: "Plus le curseur descend, plus la page défile vite. Remontez-le pour ralentir ; elle s’arrête là où vous avez cliqué.",
        autoHelpRight: "Plus le curseur va à droite, plus la page défile vite. Ramenez-le pour ralentir ; elle s’arrête là où vous avez cliqué.",
        noPage: "Aucune page à faire défiler sous la zone",
        section: "Capture défilante",
        controlsToggle: "Défilement auto guidé par le curseur",
        controlsCaption: "Annuler, Défilement auto et Terminer s’affichent au-dessus de la zone. Une fois le défilement auto lancé, plus le curseur descend, plus la page défile vite ; revenu là où vous avez cliqué, il s’arrête. Le défilement à la main marche toujours. Entrée termine, Échap annule.",
        horizontalToggle: "Défiler de côté depuis le menu de capture",
        horizontalCaption: "Les captures défilantes lancées depuis le menu de capture suivent la page vers la droite au lieu du bas."
    )
}

/// The texts of the editor's simpler crop, and of its setting.
struct ForkCropStrings {
    let ratio: String
    let free: String
    let original: String
    let settingsToggle: String
    let settingsCaption: String

    static var current: ForkCropStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkCropStrings(
        ratio: "Ratio",
        free: "Free",
        original: "Original",
        settingsToggle: "Simpler cropping in the editor",
        settingsCaption: "Large grips at the corners and on each edge, whatever the zoom; the thirds and the size while you pull; a ratio menu (Shift keeps the current one on a corner). Return, a double click in the frame or another tool crops; Escape leaves the picture as it was."
    )

    static let french = ForkCropStrings(
        ratio: "Proportions",
        free: "Libre",
        original: "Originale",
        settingsToggle: "Rognage simplifié dans l’éditeur",
        settingsCaption: "De grandes poignées aux coins et sur chaque bord, quel que soit le zoom ; la grille des tiers et la taille pendant que vous tirez ; un menu de proportions (Maj garde les proportions sur un coin). Entrée, un double-clic dans le cadre ou un autre outil rogne ; Échap laisse l’image telle quelle."
    )
}

/// The texts of Mission Control's × and shortcuts, and of their setting.
struct ForkMissionControlStrings {
    let section: String
    let toggle: String
    let caption: String
    let closeWindow: String

    static var current: ForkMissionControlStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkMissionControlStrings(
        section: "Mission Control",
        toggle: "Close windows from Mission Control",
        caption: "In Mission Control, a × shows on the window under the pointer and closes it. ⌘W closes that window, ⌘H hides its app, ⌘Q quits it; with no window under the pointer the keys work as usual. Pinching two fingers on a window quits its app. Quit Mission Control Plus first: both would act.",
        closeWindow: "Close the window"
    )

    static let french = ForkMissionControlStrings(
        section: "Mission Control",
        toggle: "Fermer les fenêtres depuis Mission Control",
        caption: "Dans Mission Control, un × apparaît sur la fenêtre survolée et la ferme. ⌘W ferme cette fenêtre, ⌘H masque son app, ⌘Q la quitte ; sans fenêtre survolée, les touches marchent comme d’habitude. Pincer deux doigts sur une fenêtre quitte son app. Quittez d’abord Mission Control Plus : les deux agiraient.",
        closeWindow: "Fermer la fenêtre"
    )
}

/// The texts of the Chrome full-screen swipe's setting.
struct ForkChromeStrings {
    let section: String
    let toggle: String
    let caption: String

    static var current: ForkChromeStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkChromeStrings(
        section: "Chrome",
        toggle: "Three fingers down leave a video's full screen",
        caption: "In Chrome, swiping three fingers down leaves full screen and shows the tabs again. The same swipe later brings the video's tab back and puts it in full screen again (the F key most players take). macOS asks once to let this app control Chrome. Not available while App Exposé uses three fingers down."
    )

    static let french = ForkChromeStrings(
        section: "Chrome",
        toggle: "Trois doigts vers le bas sortent une vidéo du plein écran",
        caption: "Dans Chrome, glisser trois doigts vers le bas quitte le plein écran et rend les onglets. Le même geste ramène ensuite l’onglet de la vidéo et la remet en plein écran (touche F, comprise par la plupart des lecteurs). macOS demande une fois l’autorisation de piloter Chrome. Indisponible si App Exposé utilise trois doigts vers le bas."
    )
}

/// The texts of lot 8: battery alerts, charger sounds, the pinned device.
struct ForkBatteryStrings {
    let title: String
    let alerts: String
    let alertsCaption: String
    let halo: String
    let powerSounds: String
    let pinned: String
    let none: String
    let showInMenuBar: String
    let pinnedCaption: String
    let low: (_ percent: Int) -> String
    let charged: (_ percent: Int) -> String

    static var current: ForkBatteryStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkBatteryStrings(
        title: "Battery",
        alerts: "Battery alerts",
        alertsCaption: "At 20 % (orange), 15 % (yellow) and 5 % (red) on battery, and when charging reaches 80 % (green): a banner at the top of the screen and a sound.",
        halo: "Coloured halo round the screen for low battery",
        powerSounds: "Sound when the charger is plugged in or out",
        pinned: "Device pinned in the menu bar",
        none: "None: the lowest battery",
        showInMenuBar: "Show device batteries in the menu bar",
        pinnedCaption: "The pinned device shows in place of the lowest battery. Devices appear here once their batteries have been read, with the menu bar item on.",
        low: { "Battery at \($0) %" },
        charged: { "Battery charged to \($0) %" }
    )

    static let french = ForkBatteryStrings(
        title: "Batterie",
        alerts: "Alertes de batterie",
        alertsCaption: "À 20 % (orange), 15 % (jaune) et 5 % (rouge) sur batterie, et quand la charge atteint 80 % (vert) : un bandeau en haut de l’écran et un son.",
        halo: "Halo coloré autour de l’écran quand la batterie est faible",
        powerSounds: "Son au branchement et au débranchement du chargeur",
        pinned: "Appareil épinglé dans la barre des menus",
        none: "Aucun : la batterie la plus faible",
        showInMenuBar: "Afficher les batteries des appareils dans la barre des menus",
        pinnedCaption: "L’appareil épinglé s’affiche à la place de la batterie la plus faible. Les appareils apparaissent ici une fois leur batterie lue, avec l’affichage dans la barre des menus activé.",
        low: { "Batterie à \($0) %" },
        charged: { "Batterie chargée à \($0) %" }
    )
}

/// The texts of lot 9: the disk map and the antivirus.
struct ForkDiskToolsStrings {
    let diskMapTitle: String
    let antivirusTitle: String
    let showTools: String
    let chooseFolder: String
    let rescan: String
    let scanning: (_ files: Int) -> String
    let other: String
    let showInFinder: String
    let trash: String
    let cancel: String
    let pickHint: String
    let trashConfirm: (_ name: String) -> String
    let trashConfirmDetail: (_ size: String) -> String
    let notInstalled: String
    let notInstalledDetail: String
    let install: String
    let installConfirm: String
    let installDetail: String
    let installing: String
    let installFailed: String
    let noHomebrew: String
    let installed: String
    let signatures: (_ date: Date) -> String
    let noSignatures: String
    let updating: String
    let updateFailed: String
    let timedOut: String
    let quickScan: String
    let scanFolder: String
    let scanningTarget: (_ path: String) -> String
    let lastScan: (_ date: Date, _ threats: Int) -> String
    let threatsFound: (_ count: Int) -> String
    let nothingFound: String
    let setAside: String
    let quarantineTitle: String
    let restore: String
    let delete: String
    let deleteConfirm: (_ name: String) -> String
    let deleteDetail: String
    let moveFailed: (_ reason: String) -> String

    static var current: ForkDiskToolsStrings {
        L10n.shared.language == .fr ? french : english
    }

    private static func when(_ date: Date, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static let english = ForkDiskToolsStrings(
        diskMapTitle: "Disk map",
        antivirusTitle: "Antivirus",
        showTools: "Show the disk map and the antivirus",
        chooseFolder: "Choose a folder…",
        rescan: "Scan again",
        scanning: { "Reading the disk… \($0) files" },
        other: "Other",
        showInFinder: "Show in Finder",
        trash: "Move to Trash",
        cancel: "Cancel",
        pickHint: "Click an item to pick it, double-click a folder to open it.",
        trashConfirm: { "Move “\($0)” to the Trash?" },
        trashConfirmDetail: { "\($0) will be freed once the Trash is emptied." },
        notInstalled: "ClamAV is not installed",
        notInstalledDetail: "The antivirus uses ClamAV, a free scanner, installed with Homebrew the first time.",
        install: "Install ClamAV",
        installConfirm: "Install ClamAV with Homebrew?",
        installDetail: "About 300 MB with its virus signatures. It runs only when you start a scan.",
        installing: "Installing ClamAV… this can take a few minutes.",
        installFailed: "ClamAV could not be installed. Try “brew install clamav” in Terminal.",
        noHomebrew: "Homebrew is needed to install ClamAV.",
        installed: "ClamAV is ready",
        signatures: { "Signatures updated \(when($0, locale: "en"))" },
        noSignatures: "No signatures yet: they are downloaded before the first scan.",
        updating: "Updating the virus signatures…",
        updateFailed: "The virus signatures could not be updated.",
        timedOut: "This took too long and was stopped.",
        quickScan: "Quick scan",
        scanFolder: "Scan a folder…",
        scanningTarget: { "Scanning \($0)" },
        lastScan: { date, threats in "Last scan \(when(date, locale: "en")): \(threats == 0 ? "nothing found" : "\(threats) threat(s)")" },
        threatsFound: { "\($0) threat(s) found" },
        nothingFound: "Nothing found.",
        setAside: "Quarantine",
        quarantineTitle: "Quarantine",
        restore: "Restore",
        delete: "Delete",
        deleteConfirm: { "Delete “\($0)” for good?" },
        deleteDetail: "It will not go to the Trash.",
        moveFailed: { "The file could not be moved: \($0)" }
    )

    static let french = ForkDiskToolsStrings(
        diskMapTitle: "Carte du disque",
        antivirusTitle: "Antivirus",
        showTools: "Afficher la carte du disque et l’antivirus",
        chooseFolder: "Choisir un dossier…",
        rescan: "Analyser à nouveau",
        scanning: { "Lecture du disque… \($0) fichiers" },
        other: "Autres",
        showInFinder: "Afficher dans le Finder",
        trash: "Mettre à la corbeille",
        cancel: "Annuler",
        pickHint: "Cliquez sur un élément pour le choisir, double-cliquez sur un dossier pour l’ouvrir.",
        trashConfirm: { "Mettre « \($0) » à la corbeille ?" },
        trashConfirmDetail: { "\($0) seront libérés une fois la corbeille vidée." },
        notInstalled: "ClamAV n’est pas installé",
        notInstalledDetail: "L’antivirus utilise ClamAV, un analyseur gratuit, installé avec Homebrew la première fois.",
        install: "Installer ClamAV",
        installConfirm: "Installer ClamAV avec Homebrew ?",
        installDetail: "Environ 300 Mo avec ses signatures de virus. Il ne tourne que quand vous lancez une analyse.",
        installing: "Installation de ClamAV… cela peut prendre quelques minutes.",
        installFailed: "ClamAV n’a pas pu être installé. Essayez « brew install clamav » dans le Terminal.",
        noHomebrew: "Homebrew est nécessaire pour installer ClamAV.",
        installed: "ClamAV est prêt",
        signatures: { "Signatures mises à jour le \(when($0, locale: "fr"))" },
        noSignatures: "Pas encore de signatures : elles sont téléchargées avant la première analyse.",
        updating: "Mise à jour des signatures de virus…",
        updateFailed: "Les signatures de virus n’ont pas pu être mises à jour.",
        timedOut: "C’était trop long : l’opération a été arrêtée.",
        quickScan: "Analyse rapide",
        scanFolder: "Analyser un dossier…",
        scanningTarget: { "Analyse de \($0)" },
        lastScan: { date, threats in "Dernière analyse le \(when(date, locale: "fr")) : \(threats == 0 ? "rien trouvé" : "\(threats) menace(s)")" },
        threatsFound: { "\($0) menace(s) trouvée(s)" },
        nothingFound: "Rien trouvé.",
        setAside: "Mettre en quarantaine",
        quarantineTitle: "Quarantaine",
        restore: "Restaurer",
        delete: "Supprimer",
        deleteConfirm: { "Supprimer « \($0) » définitivement ?" },
        deleteDetail: "Il n’ira pas à la corbeille.",
        moveFailed: { "Le fichier n’a pas pu être déplacé : \($0)" }
    )
}

/// The texts the fork adds to Keep Awake's closed-lid mode.
struct ForkEnergyStrings {
    let lidSleepsDisplaysTitle: String
    let lidSleepsDisplaysCaption: String
    let lidSleepsDisplaysShortCaption: String

    static var current: ForkEnergyStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkEnergyStrings(
        lidSleepsDisplaysTitle: "Turn off the external display too",
        lidSleepsDisplaysCaption: "A few seconds after the lid closes, every display goes to sleep, as with the “Put Display to Sleep” hot corner. The Mac keeps working. The displays come back when the lid opens, or with the keyboard or the mouse. Meanwhile, the slight pointer move of Keep Awake waits.",
        lidSleepsDisplaysShortCaption: "Puts the displays to sleep when the lid closes."
    )

    static let french = ForkEnergyStrings(
        lidSleepsDisplaysTitle: "Éteindre aussi l’écran externe",
        lidSleepsDisplaysCaption: "Quelques secondes après la fermeture du couvercle, tous les écrans se mettent en veille, comme avec le coin actif « Mettre l’écran en veille ». Le Mac continue de travailler. Les écrans se rallument à l’ouverture du couvercle, ou au clavier et à la souris. Pendant ce temps, le léger déplacement du pointeur de Garder éveillé attend.",
        lidSleepsDisplaysShortCaption: "Met les écrans en veille à la fermeture du couvercle."
    )
}

/// The texts of the maintenance window (lot 9d).
struct ForkMaintenanceStrings {
    let title: String
    let intro: String
    let dnsTitle: String
    let dnsCaption: String
    let launchServicesTitle: String
    let launchServicesCaption: String
    let memoryTitle: String
    let memoryCaption: String
    let spotlightTitle: String
    let spotlightCaption: String
    let needsPassword: String
    let run: String
    let running: String
    let never: String
    let lastRun: (_ when: String) -> String
    let done: String
    let failed: String
    let cancelled: String
    let administratorFailed: String
    let administratorPrompt: (_ app: String) -> String
    let spotlightConfirm: String
    let spotlightDetail: String
    let reindex: String
    let cancel: String

    static var current: ForkMaintenanceStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkMaintenanceStrings(
        title: "Maintenance",
        intro: "Upkeep jobs to run now and then. Those with a padlock need the administrator password, asked once for all of them.",
        dnsTitle: "Flush the DNS cache",
        dnsCaption: "When a site no longer opens or goes to an old address, after a change of network or of DNS.",
        launchServicesTitle: "Repair “Open With”",
        launchServicesCaption: "Compacts the database of apps macOS keeps and registers the apps of the Applications folders again: duplicates and vanished apps leave the “Open With” menu.",
        memoryTitle: "Free up memory",
        memoryCaption: "Empties the disk cache held in memory. macOS uses free memory as a cache on purpose: apps then read the disk again. Only worth it when the Mac slows down.",
        spotlightTitle: "Reindex Spotlight",
        spotlightCaption: "When search no longer finds files that exist. Reindexing takes several hours, and search stays incomplete meanwhile.",
        needsPassword: "Administrator password",
        run: "Run",
        running: "Running maintenance…",
        never: "Never run",
        lastRun: { "Last run \($0)" },
        done: "Done",
        failed: "Failed",
        cancelled: "Password prompt dismissed: the jobs that need it did not run.",
        administratorFailed: "The jobs that need the administrator password could not run.",
        administratorPrompt: { "\($0) wants to run the maintenance jobs you chose." },
        spotlightConfirm: "Reindex Spotlight?",
        spotlightDetail: "Search will stay incomplete for a few hours, while the Mac rebuilds its index in the background.",
        reindex: "Reindex",
        cancel: "Cancel"
    )

    static let french = ForkMaintenanceStrings(
        title: "Maintenance",
        intro: "Des tâches d’entretien à lancer de temps en temps. Celles marquées d’un cadenas demandent le mot de passe administrateur, une seule fois pour toutes.",
        dnsTitle: "Vider le cache DNS",
        dnsCaption: "Quand un site ne s’ouvre plus ou mène à une ancienne adresse, après un changement de réseau ou de DNS.",
        launchServicesTitle: "Réparer « Ouvrir avec »",
        launchServicesCaption: "Compacte la base des apps que garde macOS et réenregistre les apps des dossiers Applications : les doublons et les apps disparues quittent le menu « Ouvrir avec ».",
        memoryTitle: "Libérer la mémoire",
        memoryCaption: "Vide le cache disque gardé en mémoire. macOS se sert volontairement de la mémoire libre comme cache : les apps relisent ensuite le disque. Utile seulement si le Mac ralentit.",
        spotlightTitle: "Réindexer Spotlight",
        spotlightCaption: "Quand la recherche ne trouve plus des fichiers qui existent. La réindexation prend plusieurs heures, et la recherche reste incomplète pendant ce temps.",
        needsPassword: "Mot de passe administrateur",
        run: "Lancer",
        running: "Maintenance en cours…",
        never: "Jamais lancé",
        lastRun: { "Dernier passage \($0)" },
        done: "Terminé",
        failed: "Échec",
        cancelled: "Demande de mot de passe fermée : les tâches qui en ont besoin n’ont pas été lancées.",
        administratorFailed: "Les tâches qui demandent le mot de passe administrateur n’ont pas pu être lancées.",
        administratorPrompt: { "\($0) veut lancer les tâches de maintenance choisies." },
        spotlightConfirm: "Réindexer Spotlight ?",
        spotlightDetail: "La recherche restera incomplète pendant quelques heures, le temps que le Mac refasse son index en arrière-plan.",
        reindex: "Réindexer",
        cancel: "Annuler"
    )
}

/// The texts of the cleaning tools' shared look (lot 9e): welcome screens,
/// round buttons and summaries.
struct ForkCareStrings {
    let maintenanceSubtitle: String
    let chosen: (_ count: Int) -> String
    let chooseJobs: String
    let hideJobs: String
    let working: String
    let allDone: (_ count: Int) -> String
    let partly: (_ done: Int, _ failed: Int) -> String
    let nothingRan: String
    let finish: String
    let runAgain: String
    let analyze: String
    let install: String
    let noThreat: String
    let quarantine: (_ count: Int) -> String
    let quarantineAll: String
    let back: String
    let diskSubtitle: String
    let freeSpace: (_ free: String, _ total: String) -> String
    let stop: String
    let antivirusSubtitle: String
    let notRun: String

    static var current: ForkCareStrings {
        L10n.shared.language == .fr ? french : english
    }

    private static func plural(_ count: Int, french: Bool, _ one: String, _ many: String) -> String {
        ForkCareLogic.isPlural(count, french: french) ? many : one
    }

    static let english = ForkCareStrings(
        maintenanceSubtitle: "A few upkeep jobs to keep the Mac responsive.",
        chosen: { "\($0) \(plural($0, french: false, "job", "jobs")) chosen" },
        chooseJobs: "Choose the jobs",
        hideJobs: "Hide the jobs",
        working: "Working",
        allDone: { "\($0) \(plural($0, french: false, "job", "jobs")) done" },
        partly: { done, failed in "\(done) done, \(failed) failed" },
        nothingRan: "Nothing ran",
        finish: "OK",
        runAgain: "Run again",
        analyze: "Scan",
        install: "Install",
        noThreat: "No threat found",
        quarantine: { "Quarantine (\($0))" },
        quarantineAll: "Quarantine all",
        back: "Back",
        diskSubtitle: "See what takes room, sorted by size. Nothing is removed without your say.",
        freeSpace: { free, total in "\(free) free of \(total)" },
        stop: "Stop",
        antivirusSubtitle: "Looks for malware where it usually lands: downloads, what starts by itself, new apps.",
        notRun: "Not run"
    )

    static let french = ForkCareStrings(
        maintenanceSubtitle: "Quelques tâches d’entretien pour garder le Mac réactif.",
        chosen: { $0 == 0 ? "Aucune tâche choisie" : "\($0) \(plural($0, french: true, "tâche choisie", "tâches choisies"))" },
        chooseJobs: "Choisir les tâches",
        hideJobs: "Masquer les tâches",
        working: "En cours",
        allDone: { "\($0) \(plural($0, french: true, "tâche terminée", "tâches terminées"))" },
        partly: { done, failed in "\(done) \(plural(done, french: true, "terminée", "terminées")), \(failed) en échec" },
        nothingRan: "Rien n’a été lancé",
        finish: "OK",
        runAgain: "Relancer",
        analyze: "Analyser",
        install: "Installer",
        noThreat: "Aucune menace trouvée",
        quarantine: { "Quarantaine (\($0))" },
        quarantineAll: "Tout mettre en quarantaine",
        back: "Retour",
        diskSubtitle: "Voyez ce qui prend de la place, rangé par taille. Rien n’est supprimé sans votre accord.",
        freeSpace: { free, total in "\(free) libres sur \(total)" },
        stop: "Arrêter",
        antivirusSubtitle: "Cherche les logiciels malveillants là où ils arrivent : téléchargements, démarrage automatique, nouvelles apps.",
        notRun: "Pas lancée"
    )
}

/// The texts of the one-click scan (lot 9f).
struct ForkSmartScanStrings {
    let title: String
    let subtitle: String
    let cleaning: String
    let protection: String
    let performance: String
    let scanningCleaning: String
    let scanningProtection: String
    let scanningPerformance: String
    let resultsTitle: String
    let toFree: (_ size: String) -> String
    let safeItems: (_ count: Int) -> String
    let nothingToClean: String
    let cleanerOff: String
    let notInstalled: String
    let installHint: String
    let threatsHint: String
    let cleanHint: String
    let jobsDue: (_ count: Int) -> String
    let upToDate: String
    let upToDateHint: String
    let run: String
    let running: String
    let seeDetails: String
    let look: String
    let allGood: String
    let freed: (_ size: String) -> String
    let cleanFailed: (_ count: Int) -> String
    let jobsFailed: (_ count: Int) -> String
    let rescan: String

    static var current: ForkSmartScanStrings {
        L10n.shared.language == .fr ? french : english
    }

    private static func plural(_ count: Int, french: Bool, _ one: String, _ many: String) -> String {
        ForkCareLogic.isPlural(count, french: french) ? many : one
    }

    static let english = ForkSmartScanStrings(
        title: "One-click scan",
        subtitle: "Cleaning, protection and upkeep in one scan. Nothing is removed before you say so.",
        cleaning: "Cleaning",
        protection: "Protection",
        performance: "Performance",
        scanningCleaning: "Looking for junk…",
        scanningProtection: "Looking for malware…",
        scanningPerformance: "Checking upkeep…",
        resultsTitle: "Scan results",
        toFree: { "\($0) to free" },
        safeItems: { "\($0) safe \(plural($0, french: false, "item", "items")), recoverable from the Trash" },
        nothingToClean: "Nothing to clean",
        cleanerOff: "The cleaner is turned off.",
        notInstalled: "Antivirus not installed",
        installHint: "Install ClamAV from the antivirus.",
        threatsHint: "To look at in the antivirus: nothing is handled by itself.",
        cleanHint: "Downloads, startup items and new apps.",
        jobsDue: { "\($0) \(plural($0, french: false, "job", "jobs")) recommended" },
        upToDate: "Upkeep up to date",
        upToDateHint: "Everything ran within the last 30 days.",
        run: "Run",
        running: "Running…",
        seeDetails: "See details",
        look: "Look",
        allGood: "All in order",
        freed: { "\($0) freed" },
        cleanFailed: { "\($0) \(plural($0, french: false, "item", "items")) left in place: see the Cleaner page." },
        jobsFailed: { "\($0) \(plural($0, french: false, "job", "jobs")) failed." },
        rescan: "Scan again"
    )

    static let french = ForkSmartScanStrings(
        title: "Analyse en un clic",
        subtitle: "Nettoyage, protection et entretien, en une seule analyse. Rien n’est supprimé avant votre accord.",
        cleaning: "Nettoyage",
        protection: "Protection",
        performance: "Performance",
        scanningCleaning: "Recherche des fichiers inutiles…",
        scanningProtection: "Recherche de logiciels malveillants…",
        scanningPerformance: "Vérification de l’entretien…",
        resultsTitle: "Résultat de l’analyse",
        toFree: { "\($0) à libérer" },
        safeItems: { "\($0) \(plural($0, french: true, "élément sûr", "éléments sûrs")), récupérables dans la corbeille" },
        nothingToClean: "Rien à nettoyer",
        cleanerOff: "Le nettoyeur est désactivé.",
        notInstalled: "Antivirus non installé",
        installHint: "Installez ClamAV depuis l’Antivirus.",
        threatsHint: "À examiner dans l’Antivirus : rien n’est traité tout seul.",
        cleanHint: "Téléchargements, démarrage automatique et nouvelles apps.",
        jobsDue: { "\($0) \(plural($0, french: true, "tâche recommandée", "tâches recommandées"))" },
        upToDate: "Entretien à jour",
        upToDateHint: "Tout a été lancé il y a moins de 30 jours.",
        run: "Exécuter",
        running: "Exécution…",
        seeDetails: "Voir le détail",
        look: "Voir",
        allGood: "Tout est en ordre",
        freed: { "\($0) libérés" },
        cleanFailed: { "\($0) \(plural($0, french: true, "élément laissé", "éléments laissés")) en place : voyez la page Nettoyage." },
        jobsFailed: { "\($0) \(plural($0, french: true, "tâche", "tâches")) en échec." },
        rescan: "Analyser à nouveau"
    )
}

/// The texts of the menu bar panel's direct ways in: quitting apps, the cleaning tools.
struct ForkMenuShortcutsStrings {
    let heavyAppsTitle: String
    let quit: String
    let quitHelp: String
    let forceQuit: String
    let measuring: String
    let nothing: String

    static var current: ForkMenuShortcutsStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkMenuShortcutsStrings(
        heavyAppsTitle: "Heaviest apps",
        quit: "Quit",
        quitHelp: "Quit (hold ⌥ to force quit)",
        forceQuit: "Force quit",
        measuring: "Measuring…",
        nothing: "No app to quit."
    )

    static let french = ForkMenuShortcutsStrings(
        heavyAppsTitle: "Apps gourmandes",
        quit: "Quitter",
        quitHelp: "Quitter (⌥ pour forcer à quitter)",
        forceQuit: "Forcer à quitter",
        measuring: "Mesure en cours…",
        nothing: "Aucune app à quitter."
    )
}


/// The texts of the simple menus: the tabs' short names, the quick actions'
/// tiles, Keep Awake's state and the switch in Settings.
struct ForkPanelStrings {
    let tabs: [PanelSectionID: String]
    let darkMode: String
    let keyboardLight: String
    let micMuted: String
    let emptyTrash: String
    let quitAll: String
    let eject: String
    let hiddenFiles: String
    let desktopIcons: String
    let lock: String
    let displayOff: String
    let screenSaver: String
    let awake: String
    let sleeps: String
    let remaining: (String, String) -> String
    let batteryNote: (Int) -> String
    let expanded: String
    let collapsed: String
    let toggle: String
    let caption: String
    let waiting: String
    let fanStopped: String

    func tab(_ id: PanelSectionID) -> String? { tabs[id] }

    static var current: ForkPanelStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkPanelStrings(
        tabs: [.toggles: "Actions", .keepAwake: "Keep Awake", .mixer: "Sound", .network: "Network",
               .disk: "Disks", .fanControl: "Fans", .system: "System", .brightness: "Brightness",
               .power: "Power", .utilities: "Tools", .controls: "Controls", .wallpaper: "Wallpaper"],
        darkMode: "Dark Mode",
        keyboardLight: "Keyboard Light",
        micMuted: "Mic Off",
        emptyTrash: "Empty Trash",
        quitAll: "Quit Apps",
        eject: "Eject Disks",
        hiddenFiles: "Hidden Files",
        desktopIcons: "Desktop Icons",
        lock: "Lock Screen",
        displayOff: "Display Off",
        screenSaver: "Screen Saver",
        awake: "Staying awake",
        sleeps: "Sleeps as usual",
        remaining: { "\($0) left · until \($1)" },
        batteryNote: { "Battery at \($0)%: plug in, or lower the battery limit, to start" },
        expanded: "expanded",
        collapsed: "collapsed",
        toggle: "Simple menus",
        caption: "The active tab shows its name, quick actions are tiles, Keep Awake opens on its state and the disk tab shows what is of use. Off, the menus are as before.",
        waiting: "Waiting for a reading",
        fanStopped: "Stopped"
    )

    static let french = ForkPanelStrings(
        tabs: [.toggles: "Actions", .keepAwake: "Garder éveillé", .mixer: "Son", .network: "Réseau",
               .disk: "Disques", .fanControl: "Ventilateurs", .system: "Système", .brightness: "Luminosité",
               .power: "Énergie", .utilities: "Outils", .controls: "Commandes", .wallpaper: "Fond d’écran"],
        darkMode: "Mode sombre",
        keyboardLight: "Éclairage clavier",
        micMuted: "Micro coupé",
        emptyTrash: "Vider la Corbeille",
        quitAll: "Quitter les apps",
        eject: "Éjecter les disques",
        hiddenFiles: "Fichiers masqués",
        desktopIcons: "Icônes du bureau",
        lock: "Verrouiller",
        displayOff: "Éteindre l’écran",
        screenSaver: "Économiseur",
        awake: "Mac éveillé",
        sleeps: "Veille normale",
        remaining: { "Encore \($0) · jusqu’à \($1)" },
        batteryNote: { "Batterie à \($0)\u{00A0}% : branchez le chargeur ou baissez la limite de batterie pour démarrer" },
        expanded: "déplié",
        collapsed: "replié",
        toggle: "Menus simplifiés",
        caption: "L’onglet actif affiche son nom, les actions rapides sont des tuiles, Garder éveillé s’ouvre sur son état et l’onglet Disques ne montre que l’utile. Désactivé, les menus sont comme avant.",
        waiting: "En attente d’une mesure",
        fanStopped: "À l’arrêt"
    )
}

/// The texts of background sound.
struct ForkAmbientStrings {
    let title: String
    let subtitle: String
    let play: String
    let pause: String
    let open: String
    let volume: String
    let timer: String
    let never: String
    let minutes: (_ count: Int) -> String
    let remaining: (_ clock: String) -> String
    let presetsTitle: String
    let favoritesTitle: String
    let saveFavorite: String
    let favoriteName: String
    let defaultFavoriteName: String
    let rename: String
    let delete: String
    let noFavorite: String
    let soundsTitle: String
    let optionsTitle: String
    let modeTitle: String
    let timerMode: String
    let pomodoroMode: String
    let workLength: String
    let phase: (ForkAmbientLogic.Phase) -> String
    let round: (_ done: Int, _ of: Int) -> String
    let held: String
    let menuBarIcon: String
    let inIsland: String
    let inIslandCaption: String
    let islandWave: String
    let islandScenes: String
    let islandScenesCaption: String
    let shortcut: String
    let shortcutTaken: String
    let pauseForCalls: String
    let pauseForMusic: String
    let pauseForMusicCaption: String
    let pausesOnLock: String
    let headphones: String
    let family: (ForkAmbientLogic.Family) -> String
    let sound: (ForkAmbientLogic.Sound) -> String
    let preset: (ForkAmbientLogic.Preset) -> String
    let custom: String

    static var current: ForkAmbientStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkAmbientStrings(
        title: "Background sound",
        subtitle: "Sounds made live by the app to work in peace. No file, no connection.",
        play: "Play",
        pause: "Pause",
        open: "Open Background sound",
        volume: "Volume",
        timer: "Stop after",
        never: "Never",
        minutes: { "\($0) min" },
        remaining: { "\($0) left" },
        presetsTitle: "Ambiences",
        favoritesTitle: "Favourites",
        saveFavorite: "Save this mix",
        favoriteName: "Name",
        defaultFavoriteName: "My mix",
        rename: "Rename",
        delete: "Delete",
        noFavorite: "Save a mix you like to find it here.",
        soundsTitle: "Sounds",
        optionsTitle: "Options",
        modeTitle: "Mode",
        timerMode: "Timer",
        pomodoroMode: "Pomodoro",
        workLength: "Work",
        phase: { phase in
            switch phase {
            case .work: return "Work"
            case .shortBreak: return "Break"
            case .longBreak: return "Long break"
            }
        },
        round: { done, total in "Session \(done) of \(total)" },
        held: "Paused while you are on a call or music plays",
        menuBarIcon: "Icon in the menu bar while playing",
        inIsland: "Control in the Dynamic Island",
        inIslandCaption: "A tile among the island's controls: a click plays and pauses, a long press opens this window.",
        islandWave: "Animation in the closed island while playing",
        islandScenes: "A scene for what plays",
        islandScenesCaption: "A bird for the forest, a campfire for the fire, a storm cloud for thunder… Off, a wave.",
        shortcut: "Play and pause from anywhere",
        shortcutTaken: "Another app already uses this shortcut.",
        pauseForCalls: "Pause during calls",
        pauseForMusic: "Pause while music plays",
        pauseForMusicCaption: "Music the Dynamic Island shows, such as Spotify or Music.",
        pausesOnLock: "The sound also pauses when the screen locks or the Mac sleeps, and comes back after.",
        headphones: "With headphones",
        family: { family in
            switch family {
            case .noise: return "Noises"
            case .nature: return "Nature"
            case .binaural: return "Binaural and 40 Hz"
            case .music: return "Soft music"
            }
        },
        sound: { sound in
            switch sound {
            case .white: return "White noise"
            case .pink: return "Pink noise"
            case .brown: return "Brown noise"
            case .rain: return "Rain"
            case .ocean: return "Ocean"
            case .wind: return "Wind"
            case .fire: return "Fire"
            case .forest: return "Forest"
            case .stream: return "Stream"
            case .thunder: return "Thunder"
            case .alpha: return "Alpha · calm"
            case .beta: return "Beta · focus"
            case .gamma: return "Gamma 40 Hz"
            case .chords: return "Lo-fi chords"
            case .drone: return "Deep drone"
            case .bowls: return "Singing bowls"
            }
        },
        preset: { preset in
            switch preset {
            case .focus: return "Focus"
            case .deepFocus: return "Deep focus"
            case .calm: return "Calm"
            case .nature: return "Nature"
            case .storm: return "Storm"
            case .lofi: return "Lo-fi"
            }
        },
        custom: "Your mix"
    )

    static let french = ForkAmbientStrings(
        title: "Bruit de fond",
        subtitle: "Des sons créés en direct par l’app pour travailler au calme. Aucun fichier, aucune connexion.",
        play: "Écouter",
        pause: "Pause",
        open: "Ouvrir Bruit de fond",
        volume: "Volume",
        timer: "Arrêt après",
        never: "Jamais",
        minutes: { "\($0) min" },
        remaining: { "Encore \($0)" },
        presetsTitle: "Ambiances",
        favoritesTitle: "Favoris",
        saveFavorite: "Enregistrer ce mélange",
        favoriteName: "Nom",
        defaultFavoriteName: "Mon mélange",
        rename: "Renommer",
        delete: "Supprimer",
        noFavorite: "Enregistrez un mélange qui vous plaît pour le retrouver ici.",
        soundsTitle: "Sons",
        optionsTitle: "Options",
        modeTitle: "Mode",
        timerMode: "Minuteur",
        pomodoroMode: "Pomodoro",
        workLength: "Travail",
        phase: { phase in
            switch phase {
            case .work: return "Travail"
            case .shortBreak: return "Pause"
            case .longBreak: return "Longue pause"
            }
        },
        round: { done, total in "Séance \(done) sur \(total)" },
        held: "En pause pendant un appel ou quand la musique joue",
        menuBarIcon: "Icône dans la barre des menus pendant la lecture",
        inIsland: "Commande dans la Dynamic Island",
        inIslandCaption: "Une tuile parmi les commandes de l’île : un clic lance ou met en pause, un appui long ouvre cette fenêtre.",
        islandWave: "Animation dans l’île fermée pendant la lecture",
        islandScenes: "Une scène selon le son",
        islandScenesCaption: "Un oiseau pour la forêt, un feu de camp pour le feu, un nuage d’orage pour le tonnerre… Désactivé : une onde.",
        shortcut: "Lecture et pause depuis n’importe où",
        shortcutTaken: "Une autre app utilise déjà ce raccourci.",
        pauseForCalls: "Pause pendant les appels",
        pauseForMusic: "Pause quand la musique joue",
        pauseForMusicCaption: "La musique que montre la Dynamic Island, comme Spotify ou Musique.",
        pausesOnLock: "Le son se met aussi en pause quand l’écran se verrouille ou que le Mac se met en veille, et reprend au retour.",
        headphones: "Au casque",
        family: { family in
            switch family {
            case .noise: return "Bruits"
            case .nature: return "Nature"
            case .binaural: return "Binauraux et 40 Hz"
            case .music: return "Musique douce"
            }
        },
        sound: { sound in
            switch sound {
            case .white: return "Bruit blanc"
            case .pink: return "Bruit rose"
            case .brown: return "Bruit brun"
            case .rain: return "Pluie"
            case .ocean: return "Océan"
            case .wind: return "Vent"
            case .fire: return "Feu de cheminée"
            case .forest: return "Forêt"
            case .stream: return "Ruisseau"
            case .thunder: return "Tonnerre"
            case .alpha: return "Alpha · calme"
            case .beta: return "Bêta · attention"
            case .gamma: return "Gamma 40 Hz"
            case .chords: return "Accords lo-fi"
            case .drone: return "Drone grave"
            case .bowls: return "Bols chantants"
            }
        },
        preset: { preset in
            switch preset {
            case .focus: return "Concentration"
            case .deepFocus: return "Concentration profonde"
            case .calm: return "Calme"
            case .nature: return "Nature"
            case .storm: return "Orage"
            case .lofi: return "Lo-fi"
            }
        },
        custom: "Votre mélange"
    )
}

/// The texts of the QR code that opens a local dev server on a phone.
struct ForkLocalQRStrings {
    let menuItem: String
    let button: String
    let title: String
    let sameNetwork: (String?) -> String
    let localOnlyTitle: String
    let localOnlyDetail: String
    let noNetworkTitle: String
    let noNetworkDetail: String
    let copyLink: String
    let openHere: String
    let copied: String
    let toggle: String

    static var current: ForkLocalQRStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkLocalQRStrings(
        menuItem: "QR Code for a Phone",
        button: "Show a QR code to open this server on a phone",
        title: "Open on a phone",
        sameNetwork: { name in
            name.map { "The phone must be on the same network as this Mac (\($0))." }
                ?? "The phone must be on the same network as this Mac."
        },
        localOnlyTitle: "This server answers this Mac only",
        localOnlyDetail: "It listens on 127.0.0.1, which a phone cannot reach. Start it on every interface, then try again. For example:",
        noNetworkTitle: "No network",
        noNetworkDetail: "This Mac has no address on a local network. Connect it to the same Wi-Fi as the phone.",
        copyLink: "Copy Link",
        openHere: "Open Here",
        copied: "Link copied",
        toggle: "QR code button on dev server ports"
    )

    static let french = ForkLocalQRStrings(
        menuItem: "QR code pour un téléphone",
        button: "Afficher un QR code pour ouvrir ce serveur sur un téléphone",
        title: "Ouvrir sur un téléphone",
        sameNetwork: { name in
            name.map { "Le téléphone doit être sur le même réseau que ce Mac (\($0))." }
                ?? "Le téléphone doit être sur le même réseau que ce Mac."
        },
        localOnlyTitle: "Ce serveur ne répond qu’à ce Mac",
        localOnlyDetail: "Il écoute sur 127.0.0.1, qu’un téléphone ne peut pas joindre. Lancez-le sur toutes les interfaces, puis réessayez. Par exemple :",
        noNetworkTitle: "Pas de réseau",
        noNetworkDetail: "Ce Mac n’a pas d’adresse sur un réseau local. Connectez-le au même Wi-Fi que le téléphone.",
        copyLink: "Copier le lien",
        openHere: "Ouvrir ici",
        copied: "Lien copié",
        toggle: "Bouton QR code sur les ports des serveurs de dev"
    )
}

/// The texts of currency conversion in the command bar.
struct ForkCurrencyStrings {
    let toggle: String
    let target: String
    let loading: String
    let source: String
    let rates: (String) -> String

    static var current: ForkCurrencyStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkCurrencyStrings(
        toggle: "Currencies, with the European Central Bank's rates",
        target: "Without a target, convert to",
        loading: "Fetching exchange rates…",
        source: "European Central Bank reference rates",
        rates: { "ECB rates of \($0)" }
    )

    static let french = ForkCurrencyStrings(
        toggle: "Devises, aux taux de la Banque centrale européenne",
        target: "Sans devise cible, convertir en",
        loading: "Récupération des taux de change…",
        source: "Taux de référence de la Banque centrale européenne",
        rates: { "taux BCE du \($0)" }
    )
}

/// The texts of lot 9 in the background: the daily signature check, the
/// downloads' watch and the scheduled one-click scan.
struct ForkCareAutomationStrings {
    let signaturesOld: String
    let dailyUpdate: String
    let watchDownloads: String
    let scheduleOff: String
    let everyDay: (String) -> String
    let everyWeek: (String, String) -> String
    let scheduleTitle: String
    let frequency: String
    let off: String
    let weekly: String
    let daily: String
    let day: String
    let time: String
    let scheduleNote: String
    let scanDone: String
    let toFree: (String) -> String
    let jobsDue: (Int) -> String
    let threats: (Int) -> String
    let noThreat: String
    let allGood: String
    let downloadThreat: String
    let threatsIn: (Int, String) -> String

    static var current: ForkCareAutomationStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkCareAutomationStrings(
        signaturesOld: "Signatures over a week old: check your connection",
        dailyUpdate: "Update every day",
        watchDownloads: "Scan new downloads",
        scheduleOff: "Schedule the scan",
        everyDay: { "Every day at \($0)" },
        everyWeek: { "Every \($0) at \($1)" },
        scheduleTitle: "Scan by itself",
        frequency: "Frequency",
        off: "Never",
        weekly: "Every week",
        daily: "Every day",
        day: "Day",
        time: "Time",
        scheduleNote: "On the charger or above half battery; asleep at that time, the Mac scans on waking. Nothing is cleaned: a notification says what was found.",
        scanDone: "Scan finished",
        toFree: { "\($0) to free" },
        jobsDue: { $0 == 1 ? "1 task due" : "\($0) tasks due" },
        threats: { $0 == 1 ? "1 threat" : "\($0) threats" },
        noThreat: "no threat",
        allGood: "Everything is in order",
        downloadThreat: "Threat in Downloads",
        threatsIn: { "\($0) threats, including \($1)" }
    )

    static let french = ForkCareAutomationStrings(
        signaturesOld: "Signatures de plus d’une semaine : vérifiez la connexion",
        dailyUpdate: "Mettre à jour chaque jour",
        watchDownloads: "Analyser les nouveaux téléchargements",
        scheduleOff: "Planifier l’analyse",
        everyDay: { "Chaque jour à \($0)" },
        everyWeek: { "Chaque \($0) à \($1)" },
        scheduleTitle: "Analyse automatique",
        frequency: "Fréquence",
        off: "Jamais",
        weekly: "Chaque semaine",
        daily: "Chaque jour",
        day: "Jour",
        time: "Heure",
        scheduleNote: "Sur secteur ou au-dessus de la moitié de la batterie ; endormi à cette heure-là, le Mac analyse au réveil. Rien n’est nettoyé : une notification dit ce qui a été trouvé.",
        scanDone: "Analyse terminée",
        toFree: { "\($0) à libérer" },
        jobsDue: { $0 == 1 ? "1 tâche due" : "\($0) tâches dues" },
        threats: { $0 == 1 ? "1 menace" : "\($0) menaces" },
        noThreat: "aucune menace",
        allGood: "Tout est en ordre",
        downloadThreat: "Menace dans Téléchargements",
        threatsIn: { "\($0) menaces, dont \($1)" }
    )
}

/// The texts of the fork's quick action tiles.
struct ForkQuickActionStrings {
    let titles: [ForkQuickActionLogic.Action: String]
    let noDevServer: String
    let added: String
    let focusReady: String
    let focusMissing: String
    let hiddenSection: String
    let hiddenEmpty: String
    let editHint: String
    let hide: (String) -> String
    let show: (String) -> String

    func title(_ action: ForkQuickActionLogic.Action) -> String { titles[action] ?? action.rawValue }

    static var current: ForkQuickActionStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkQuickActionStrings(
        titles: [.tasks: "Tasks", .colorPicker: "Color Picker", .screenText: "Screen Text", .phoneSite: "Site on Phone",
                 .ambient: "Background Sound", .note: "Quick Note", .clipboard: "Clipboard",
                 .presentation: "Presentation", .camera: "Camera Mirror", .soundOutput: "Sound Output",
                 .smartScan: "One-Click Scan", .recordScreen: "Record Screen", .weather: "Weather"],
        noDevServer: "No dev server running",
        added: "Added actions",
        focusReady: "Do Not Disturb shortcuts found: notifications stay quiet during the demo.",
        focusMissing: "For Do Not Disturb too, make the shortcuts « Hublot présentation début » and « Hublot présentation fin » in the Shortcuts app.",
        hiddenSection: "Hidden",
        hiddenEmpty: "Drag a tile here to hide it",
        editHint: "Hold a tile and drag it to move it; − hides it, + brings it back.",
        hide: { "Hide \($0)" },
        show: { "Show \($0)" }
    )

    static let french = ForkQuickActionStrings(
        titles: [.tasks: "Tâches", .colorPicker: "Pipette", .screenText: "Texte de l’écran", .phoneSite: "Site sur téléphone",
                 .ambient: "Bruit de fond", .note: "Note rapide", .clipboard: "Presse-papiers",
                 .presentation: "Présentation", .camera: "Miroir caméra", .soundOutput: "Sortie audio",
                 .smartScan: "Analyse en un clic", .recordScreen: "Enregistrer l’écran", .weather: "Météo"],
        noDevServer: "Aucun serveur de dev lancé",
        added: "Actions ajoutées",
        focusReady: "Raccourcis Ne pas déranger trouvés : aucune notification pendant la démo.",
        focusMissing: "Pour couper aussi les notifications de macOS, créez les raccourcis « Hublot présentation début » et « Hublot présentation fin » dans l’app Raccourcis.",
        hiddenSection: "Masquées",
        hiddenEmpty: "Glisse une tuile ici pour la masquer",
        editHint: "Maintiens une tuile et glisse-la pour la déplacer ; − la masque, + la remet.",
        hide: { "Masquer \($0)" },
        show: { "Afficher \($0)" }
    )
}

/// The texts of Todoist in Hublot.
struct ForkTodoistStrings {
    let title: String
    let today: String
    let refresh: String
    let openApp: String
    let addPlaceholder: String
    let addHint: String
    let loading: String
    let nothing: String
    let overdue: (String) -> String
    let complete: (String) -> String
    let unauthorized: String
    let offline: String
    let failed: String
    let setupTitle: String
    let setupDetail: String
    let getToken: String
    let token: String
    let save: String
    let toggle: String
    let toggleCaption: String
    let account: String
    let connected: String
    let disconnect: String
    let shortcut: String
    let shortcutTaken: String
    let countLabel: (Int) -> String
    let islandActivity: String
    let islandActivityCaption: String
    let islandLead: String
    let islandLeadCaption: String
    let minutes: (Int) -> String
    let doing: String
    let reminders: String
    let remindersCaption: String
    let reminderDetail: (String) -> String

    func problem(_ problem: ForkTodoist.Problem) -> String {
        switch problem {
        case .unauthorized: return unauthorized
        case .offline: return offline
        case .failed: return failed
        }
    }

    static var current: ForkTodoistStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkTodoistStrings(
        title: "Tasks",
        today: "Today",
        refresh: "Refresh",
        openApp: "Open Todoist",
        addPlaceholder: "Add a task",
        addHint: "Write as in Todoist: « Call Sam tomorrow 10am #Work p1 ». Without a date it is for today. Return or + adds it.",
        loading: "Loading…",
        nothing: "Nothing left for today",
        overdue: { "Overdue · \($0)" },
        complete: { "Complete « \($0) »" },
        unauthorized: "Todoist refused the token: make a new one and paste it in Settings › Island.",
        offline: "No connection: the list will come back with the network.",
        failed: "Todoist did not answer as expected. Try again in a moment.",
        setupTitle: "Connect Todoist",
        setupDetail: "Make your personal token in Todoist (Settings › Integrations › Developer) and paste it here. It stays in this Mac's Keychain.",
        getToken: "Get My Token",
        token: "Token",
        save: "Save",
        toggle: "Todoist tasks",
        toggleCaption: "Today's and overdue tasks in a panel that drops from the island, from its tile, the menu's or the shortcut. Added and ticked tasks show on every device.",
        account: "Todoist account",
        connected: "Connected with your personal token.",
        disconnect: "Disconnect",
        shortcut: "Shortcut",
        shortcutTaken: "Another app already uses this shortcut.",
        countLabel: { $0 == 1 ? "1 task today" : "\($0) tasks today" },
        islandActivity: "Current task in the closed island",
        islandActivityCaption: "The task you’re doing while it lasts, and a task with a time shortly before it until half an hour after. Tasks without a time stay in the list; a click opens the list.",
        islandLead: "Shows before its time",
        islandLeadCaption: "How long before its time a task appears in the closed island.",
        minutes: { "\($0) min" },
        doing: "Doing now",
        reminders: "Recall a task at its time",
        remindersCaption: "A task with a time appears in the island when it comes.",
        reminderDetail: { "Due now · \($0)" }
    )

    static let french = ForkTodoistStrings(
        title: "Tâches",
        today: "Aujourd’hui",
        refresh: "Actualiser",
        openApp: "Ouvrir Todoist",
        addPlaceholder: "Ajouter une tâche",
        addHint: "Écrivez comme dans Todoist : « Appeler Marie demain 10h #Travail p1 ». Sans date, elle est pour aujourd’hui. Entrée ou + l’ajoute.",
        loading: "Chargement…",
        nothing: "Plus rien pour aujourd’hui",
        overdue: { "En retard · \($0)" },
        complete: { "Terminer « \($0) »" },
        unauthorized: "Todoist a refusé le jeton : créez-en un nouveau et collez-le dans Réglages › Île.",
        offline: "Pas de connexion : la liste reviendra avec le réseau.",
        failed: "Todoist n’a pas répondu comme prévu. Réessayez dans un instant.",
        setupTitle: "Connecter Todoist",
        setupDetail: "Créez votre jeton personnel dans Todoist (Réglages › Intégrations › Développeur) et collez-le ici. Il reste dans le trousseau de ce Mac.",
        getToken: "Obtenir mon jeton",
        token: "Jeton",
        save: "Enregistrer",
        toggle: "Tâches Todoist",
        toggleCaption: "Les tâches du jour et en retard dans un panneau qui descend de l’île, depuis sa tuile, celle du menu ou le raccourci. Les tâches ajoutées ou cochées apparaissent sur tous vos appareils.",
        account: "Compte Todoist",
        connected: "Connecté avec votre jeton personnel.",
        disconnect: "Déconnecter",
        shortcut: "Raccourci",
        shortcutTaken: "Une autre app utilise déjà ce raccourci.",
        countLabel: { $0 <= 1 ? "\($0) tâche aujourd’hui" : "\($0) tâches aujourd’hui" },
        islandActivity: "Tâche du moment dans l’île fermée",
        islandActivityCaption: "La tâche en cours tant qu’elle dure, et une tâche avec une heure peu avant celle-ci, jusqu’à une demi-heure après. Les tâches sans heure restent dans la liste ; un clic ouvre la liste.",
        islandLead: "Apparaît avant l’heure",
        islandLeadCaption: "Combien de temps avant son heure une tâche apparaît dans l’île fermée.",
        minutes: { "\($0) min" },
        doing: "En cours",
        reminders: "Rappeler une tâche à son heure",
        remindersCaption: "Une tâche avec une heure apparaît dans l’île au moment venu.",
        reminderDetail: { "À faire maintenant · \($0)" }
    )
}

/// The texts of the livelier companion.
struct ForkMascotStrings {
    let lively: String
    let livelyCaption: String
    let day: String
    let dayCaption: String
    let variants: String
    let variantName: (ForkMascotVariantLogic.Variant) -> String
    let bubbles: String
    let bubblesCaption: String
    let typing: String
    let typingCaption: String
    let weather: String
    let weatherCaption: String
    let weatherFor: (String) -> String
    let city: String
    let cityPrompt: String
    let cityNotFound: String
    let save: String

    static var current: ForkMascotStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkMascotStrings(
        lively: "A livelier companion",
        livelyCaption: "At rest it stretches, yawns, whistles, blows a bubble, reads or does push-ups now and then; its visits take several ways; its eyes follow the pointer around the island; petted often it is glad, left alone long it looks for you.",
        day: "Follows your day",
        dayCaption: "Coffee in the morning, a nightcap in the evening and asleep after 11 pm; a headset during background sound or a Pomodoro, a stretch at each break; it cheers each Todoist task you tick and worries in the evening about late ones; a beanie in winter, sunglasses in summer, a pumpkin at Halloween, a party hat at New Year.",
        variants: "More styles",
        variantName: { variant in
            switch variant {
            case .classic: return "Classic"
            case .cat: return "Cat"
            case .ghost: return "Ghost"
            case .pixel: return "Pixel"
            case .blob: return "Blob"
            }
        },
        bubbles: "Little bubbles",
        bubblesCaption: "Now and then a word beside it: « Nice! » for a task, « Break? » at a Pomodoro's break, hello in the morning, bedtime late at night. One every ten minutes at most.",
        typing: "Types along with you",
        typingCaption: "When you type fast, it taps on a little keyboard. Only the rhythm is counted, never the keys.",
        weather: "Weather",
        weatherCaption: "An umbrella when it rains, sunglasses when the sun is out, from Open-Meteo (free, no account). Type a city below.",
        weatherFor: { "Weather for \($0), checked every hour." },
        city: "City",
        cityPrompt: "Paris",
        cityNotFound: "This city was not found: check its spelling.",
        save: "Save"
    )

    static let french = ForkMascotStrings(
        lively: "Compagnon plus vivant",
        livelyCaption: "Au repos, il s’étire, bâille, sifflote, fait une bulle, lit ou fait des pompes de temps en temps ; ses visites prennent plusieurs chemins ; ses yeux suivent le pointeur autour de l’île ; souvent caressé il est joyeux, longtemps seul il vous cherche.",
        day: "Suit votre journée",
        dayCaption: "Café le matin, bonnet de nuit le soir et endormi après 23 h ; casque pendant le bruit de fond ou un Pomodoro, étirement à chaque pause ; il fête chaque tâche Todoist cochée et s’inquiète le soir des tâches en retard ; bonnet en hiver, lunettes de soleil l’été, citrouille à Halloween, chapeau de fête au Nouvel An.",
        variants: "Autres styles",
        variantName: { variant in
            switch variant {
            case .classic: return "Classique"
            case .cat: return "Chat"
            case .ghost: return "Fantôme"
            case .pixel: return "Pixel"
            case .blob: return "Blob"
            }
        },
        bubbles: "Petites bulles",
        bubblesCaption: "De temps en temps un mot à côté de lui : « Bravo ! » pour une tâche, « Pause ? » à la pause d’un Pomodoro, bonjour le matin, dodo tard le soir. Une toutes les dix minutes au plus.",
        typing: "Tape avec vous",
        typingCaption: "Quand vous tapez vite, il tape sur un petit clavier. Seul le rythme est compté, jamais les touches.",
        weather: "Météo",
        weatherCaption: "Un parapluie quand il pleut, des lunettes de soleil quand il fait beau, d’après Open-Meteo (gratuit, sans compte). Saisissez une ville ci-dessous.",
        weatherFor: { "Météo de \($0), vérifiée toutes les heures." },
        city: "Ville",
        cityPrompt: "Paris",
        cityNotFound: "Cette ville est introuvable : vérifiez son orthographe.",
        save: "Enregistrer"
    )
}

/// The texts of the tasks' list, form and done tasks.
struct ForkTodoistBoardStrings {
    let doing: String
    let stopDoing: String
    let inProgress: String
    let edit: String
    let delete: String
    let openInTodoist: String
    let deleted: String
    let undo: String
    let doneTitle: String
    let doneEmpty: String
    let reopen: String
    let back: String
    let newTask: String
    let editTask: String
    let titlePlaceholder: String
    let notesPlaceholder: String
    let project: String
    let inbox: String
    let urgency: String
    let urgencyNames: [String]
    let date: String
    let noDate: String
    let today: String
    let tomorrow: String
    let time: String
    let repeatTitle: String
    let repeatNames: [String]
    let currentRepeat: (String) -> String
    let add: String
    let save: String
    let cancel: String
    let yesterday: String
    let moreOptions: String
    let late: String

    static var current: ForkTodoistBoardStrings { L10n.shared.language == .fr ? french : english }

    static let english = ForkTodoistBoardStrings(
        doing: "I'm on it", stopDoing: "Stop", inProgress: "In progress", edit: "Edit", delete: "Delete",
        openInTodoist: "Open in Todoist", deleted: "Task deleted", undo: "Undo", doneTitle: "Done",
        doneEmpty: "Nothing done in the last 30 days", reopen: "Restore", back: "Back", newTask: "New task",
        editTask: "Edit task", titlePlaceholder: "What to do", notesPlaceholder: "Notes", project: "Project",
        inbox: "Inbox", urgency: "Urgency", urgencyNames: ["P1 · Urgent", "P2 · High", "P3 · Medium", "P4 · Normal"],
        date: "Date", noDate: "None", today: "Today", tomorrow: "Tomorrow", time: "Time", repeatTitle: "Repeat",
        repeatNames: ["Never", "Every day", "Every week", "Every month", "Every year"],
        currentRepeat: { "Now: \($0)" }, add: "Add", save: "Save", cancel: "Cancel", yesterday: "Yesterday",
        moreOptions: "Date, urgency, repeat…", late: "Late"
    )

    static let french = ForkTodoistBoardStrings(
        doing: "Je la fais", stopDoing: "Arrêter", inProgress: "En cours", edit: "Modifier", delete: "Supprimer",
        openInTodoist: "Ouvrir dans Todoist", deleted: "Tâche supprimée", undo: "Annuler", doneTitle: "Tâches faites",
        doneEmpty: "Aucune tâche faite ces 30 derniers jours", reopen: "Rétablir", back: "Retour",
        newTask: "Nouvelle tâche", editTask: "Modifier la tâche", titlePlaceholder: "Que faut-il faire ?",
        notesPlaceholder: "Notes", project: "Projet", inbox: "Boîte de réception", urgency: "Urgence",
        urgencyNames: ["P1 · Urgente", "P2 · Haute", "P3 · Moyenne", "P4 · Normale"],
        date: "Date", noDate: "Aucune", today: "Aujourd’hui", tomorrow: "Demain", time: "Heure",
        repeatTitle: "Répétition", repeatNames: ["Jamais", "Chaque jour", "Chaque semaine", "Chaque mois", "Chaque année"],
        currentRepeat: { "Actuelle : \($0)" }, add: "Ajouter", save: "Enregistrer", cancel: "Annuler",
        yesterday: "Hier", moreOptions: "Date, urgence, répétition…", late: "En retard"
    )
}

// MARK: - Vercel

struct ForkVercelStrings {
    let title: String
    let toggle: String
    let toggleCaption: String
    let account: String
    let connected: String
    let disconnect: String
    let token: String
    let tokenCaption: String
    let save: String
    let getToken: String
    let scope: String
    let scopeCaption: String
    let scopeAll: String
    let scopeProduction: String
    let notifySuccess: String
    let notifySuccessCaption: String
    let notifyFailure: String
    let notifyFailureCaption: String
    let online: String
    let failed: String
    let production: String
    let building: String
    let openHint: String
    let unauthorized: String
    let offline: String
    let failedCheck: String

    static var current: ForkVercelStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkVercelStrings(
        title: "Vercel",
        toggle: "Deployments in the island",
        toggleCaption: "While a deployment builds, its project and how long it has run show in the closed island; a notice says when it is online or failed. Read only.",
        account: "Vercel account",
        connected: "Connected; checked every minute, every five seconds during a build.",
        disconnect: "Disconnect",
        token: "Vercel token",
        tokenCaption: "Create a token for your team on vercel.com, valid one year, then paste it here. It is kept in the Keychain only.",
        save: "Save",
        getToken: "Create a token",
        scope: "Deployments followed",
        scopeCaption: "Production and branch previews, or production only.",
        scopeAll: "All",
        scopeProduction: "Production only",
        notifySuccess: "When online",
        notifySuccessCaption: "A green notice, and the companion celebrates.",
        notifyFailure: "When it fails",
        notifyFailureCaption: "A red notice, and the companion worries. A click opens the build log.",
        online: "Online",
        failed: "Failed",
        production: "production",
        building: "Deployment building",
        openHint: "Opens the deployment on Vercel",
        unauthorized: "Vercel refused the token: create a new one.",
        offline: "Vercel could not be reached; it will be asked again.",
        failedCheck: "Vercel did not answer as expected; it will be asked again."
    )

    static let french = ForkVercelStrings(
        title: "Vercel",
        toggle: "Déploiements dans l’île",
        toggleCaption: "Pendant un build, le projet et le temps écoulé s’affichent dans l’île fermée ; une notification dit quand il est en ligne ou en échec. Lecture seule.",
        account: "Compte Vercel",
        connected: "Connecté ; vérifié chaque minute, toutes les cinq secondes pendant un build.",
        disconnect: "Déconnecter",
        token: "Jeton Vercel",
        tokenCaption: "Créez un jeton pour votre équipe sur vercel.com, valable un an, puis collez-le ici. Il est gardé dans le trousseau uniquement.",
        save: "Enregistrer",
        getToken: "Créer un jeton",
        scope: "Déploiements suivis",
        scopeCaption: "Production et aperçus des branches, ou production seulement.",
        scopeAll: "Tous",
        scopeProduction: "Production seulement",
        notifySuccess: "Quand c’est en ligne",
        notifySuccessCaption: "Une notification verte, et le compagnon fait la fête.",
        notifyFailure: "En cas d’échec",
        notifyFailureCaption: "Une notification rouge, et le compagnon s’inquiète. Un clic ouvre le journal du build.",
        online: "En ligne",
        failed: "Échec",
        production: "production",
        building: "Déploiement en cours",
        openHint: "Ouvre le déploiement sur Vercel",
        unauthorized: "Vercel a refusé le jeton : créez-en un nouveau.",
        offline: "Vercel est injoignable ; nouvel essai bientôt.",
        failedCheck: "Vercel n’a pas répondu comme prévu ; nouvel essai bientôt."
    )
}

// MARK: - Weather page

struct ForkWeatherStrings {
    let title: String
    let empty: String
    let home: String
    let retry: String
    let remove: String
    let rainAround: (String) -> String
    let addPlaceholder: String
    let full: String
    let toggle: String
    let toggleCaption: String
    let shortcut: String
    let shortcutCaption: String

    static var current: ForkWeatherStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkWeatherStrings(
        title: "Weather",
        empty: "Add a city below, or type yours in the companion’s Weather setting.",
        home: "My city",
        retry: "Try again",
        remove: "Remove",
        rainAround: { "Rain around \($0)" },
        addPlaceholder: "Add a city",
        full: "Six cities at most: remove one to add another.",
        toggle: "Weather page",
        toggleCaption: "Your city (the companion’s) and up to six more in the island: sky, temperature, rain, the coming hours and days. From Open-Meteo, asked only while the page is open.",
        shortcut: "Shortcut ⌃⌥W",
        shortcutCaption: "Opens the Weather page from anywhere."
    )

    static let french = ForkWeatherStrings(
        title: "Météo",
        empty: "Ajoutez une ville ci-dessous, ou saisissez la vôtre dans le réglage Météo du compagnon.",
        home: "Ma ville",
        retry: "Réessayer",
        remove: "Retirer",
        rainAround: { "Pluie vers \($0)" },
        addPlaceholder: "Ajouter une ville",
        full: "Six villes au plus : retirez-en une pour en ajouter une autre.",
        toggle: "Page Météo",
        toggleCaption: "Votre ville (celle du compagnon) et jusqu’à six autres dans l’île : ciel, température, pluie, heures et jours à venir. D’après Open-Meteo, interrogé seulement quand la page est ouverte.",
        shortcut: "Raccourci ⌃⌥W",
        shortcutCaption: "Ouvre la page Météo de n’importe où."
    )
}

/// The texts of the round 5 % steps for the volume and brightness keys.
struct ForkRoundStepStrings {
    let volumeToggle: String
    let brightnessToggle: String
    let caption: String

    static var current: ForkRoundStepStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkRoundStepStrings(
        volumeToggle: "Volume keys in steps of 5 %",
        brightnessToggle: "Brightness keys in steps of 5 %",
        caption: "While the island shows the level, each press lands on a round value: 60, 65, 70 %. Option-Shift keeps the fine step."
    )

    static let french = ForkRoundStepStrings(
        volumeToggle: "Touches de volume par pas de 5 %",
        brightnessToggle: "Touches de luminosité par pas de 5 %",
        caption: "Quand l’île affiche le niveau, chaque appui tombe sur une valeur ronde : 60, 65, 70 %. Option-Maj garde le pas fin."
    )
}

/// The texts of the translation of the selected text.
struct ForkTranslateStrings {
    let title: String
    let translating: String
    let copy: String
    let copied: String
    let replace: String
    let close: String
    let download: String
    let openSettings: String
    let failed: String
    let nothingToTranslate: String
    let needsNewerMacOS: String
    let needsDownload: (_ from: String, _ to: String) -> String
    let unsupported: (_ from: String, _ to: String) -> String
    let truncated: (_ characters: Int) -> String
    let toggle: String
    let toggleCaption: String
    let shortcut: String
    let shortcutCaption: String
    let shortcutTaken: String

    static var current: ForkTranslateStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkTranslateStrings(
        title: "Translation",
        translating: "Translating…",
        copy: "Copy",
        copied: "Copied",
        replace: "Replace selection",
        close: "Close",
        download: "Download languages",
        openSettings: "Language & Region",
        failed: "The translation did not go through. Try again, or check the languages in Language & Region.",
        nothingToTranslate: "Select some text, or copy it, then press the shortcut again.",
        needsNewerMacOS: "Translation needs macOS 15 or later.",
        needsDownload: { from, to in "To translate \(from) → \(to) on this Mac, macOS needs these languages once. They then work offline." },
        unsupported: { from, to in "macOS does not translate \(from) → \(to)." },
        truncated: { "Only the first \($0) characters are translated." },
        toggle: "Translate the selection",
        toggleCaption: "The selected text, or the clipboard's when nothing is selected, translated by macOS on this Mac, without network: French into English, every other language into French.",
        shortcut: "Shortcut ⌃⌥⌘T",
        shortcutCaption: "Translates from any app.",
        shortcutTaken: "Another app already uses ⌃⌥⌘T: the shortcut is off until it lets it go."
    )

    static let french = ForkTranslateStrings(
        title: "Traduction",
        translating: "Traduction…",
        copy: "Copier",
        copied: "Copié",
        replace: "Remplacer la sélection",
        close: "Fermer",
        download: "Télécharger les langues",
        openSettings: "Langue et région",
        failed: "La traduction n’a pas abouti. Réessayez, ou vérifiez les langues dans Langue et région.",
        nothingToTranslate: "Sélectionnez un texte, ou copiez-le, puis refaites le raccourci.",
        needsNewerMacOS: "La traduction demande macOS 15 ou plus récent.",
        needsDownload: { from, to in "Pour traduire \(from) → \(to) sur ce Mac, macOS a besoin de ces langues une fois. Elles marchent ensuite sans réseau." },
        unsupported: { from, to in "macOS ne traduit pas \(from) → \(to)." },
        truncated: { "Seuls les \($0) premiers caractères sont traduits." },
        toggle: "Traduire la sélection",
        toggleCaption: "Le texte sélectionné, ou celui du presse-papiers sans sélection, traduit par macOS sur ce Mac, sans réseau : le français vers l’anglais, toute autre langue vers le français.",
        shortcut: "Raccourci ⌃⌥⌘T",
        shortcutCaption: "Traduit depuis n’importe quelle app.",
        shortcutTaken: "Une autre app utilise déjà ⌃⌥⌘T : le raccourci reste coupé tant qu’elle ne le libère pas."
    )
}

/// The texts of the Care window (lot 9i): its title, its tools and their state lines.
struct ForkCareHubStrings {
    let title: String
    let names: [ForkCareHubLogic.Module: String]
    let purposes: [ForkCareHubLogic.Module: String]
    let scanning: String
    let resultsReady: String
    let running: String
    let done: String

    func name(_ module: ForkCareHubLogic.Module) -> String { names[module] ?? module.rawValue }
    func purpose(_ module: ForkCareHubLogic.Module) -> String { purposes[module] ?? "" }

    static var current: ForkCareHubStrings {
        L10n.shared.language == .fr ? french : english
    }

    static let english = ForkCareHubStrings(
        title: "Care",
        names: [.smartScan: "One-click scan", .cleanup: "Cleanup", .protection: "Protection",
                .performance: "Performance", .applications: "Applications", .diskMap: "Disk map"],
        purposes: [.smartScan: "Everything in one click", .cleanup: "Caches, logs, leftovers",
                   .protection: "Antivirus", .performance: "Mac maintenance",
                   .applications: "Uninstall cleanly", .diskMap: "What takes the space"],
        scanning: "Scanning…",
        resultsReady: "Results ready",
        running: "Running…",
        done: "Done"
    )

    static let french = ForkCareHubStrings(
        title: "Entretien",
        names: [.smartScan: "Analyse en un clic", .cleanup: "Nettoyage", .protection: "Protection",
                .performance: "Performance", .applications: "Applications", .diskMap: "Carte du disque"],
        purposes: [.smartScan: "Tout en un clic", .cleanup: "Caches, journaux, restes",
                   .protection: "Antivirus", .performance: "Maintenance du Mac",
                   .applications: "Désinstaller proprement", .diskMap: "Ce qui prend de la place"],
        scanning: "Analyse en cours…",
        resultsReady: "Résultats prêts",
        running: "En cours…",
        done: "Terminé"
    )
}
