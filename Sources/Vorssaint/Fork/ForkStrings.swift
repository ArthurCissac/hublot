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
        clipboardShelfCaption: "Along the bottom of the screen, newest first. Type to search, arrows to move, Return pastes into the app that was in front, Shift-Return only copies, ⌘1 to ⌘9 paste a card, Space previews, ⌘⌫ deletes, ⌥P pins. Off: the list or the island, as before.",
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
        clipboardShelfCaption: "En bas de l’écran, le plus récent d’abord. Tapez pour chercher, flèches pour se déplacer, Entrée colle dans l’app qui était devant, Maj-Entrée copie seulement, ⌘1 à ⌘9 collent une carte, Espace l’agrandit, ⌘⌫ la supprime, ⌥P l’épingle. Désactivé : la liste ou l’île, comme avant.",
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
        section: "Swish-style gestures",
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
        section: "Gestes façon Swish",
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
        nearbyDurationCaption: "When a player such as Spotify reports a length up to 8 seconds away from the catalog’s, lyrics of the same song and album still show. If they run early or late, shift them with − and + under the lyrics.",
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
        nearbyDurationCaption: "Quand un lecteur comme Spotify annonce une durée jusqu’à 8 secondes différente de celle du catalogue, les paroles du même titre et du même album s’affichent quand même. En avance ou en retard, décalez-les avec − et + sous les paroles.",
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
