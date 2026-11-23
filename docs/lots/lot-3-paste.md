# Lot 3 : Paste, historique visuel et pinboards

Préparé le 21/11/2026, validé le même jour (« 5 ok » : les cinq recommandations ci-dessous). Chemins relatifs à `Sources/Vorssaint/`.
Abréviations : Svc = `Services/Clipboard/ClipboardHistoryService.swift`, Sup = `ClipboardHistorySupport.swift`,
QP = `UI/MenuPanel/ClipboardQuickPanelView.swift`, Set = `UI/Settings/ClipboardSettings.swift`.

## Ce que Vorssaint fait déjà

L'upstream a déjà un bandeau de cartes en bas de l'écran (disposition `cards`), invisible ici pour
deux raisons : la disposition réglée est « Liste », et le raccourci ouvre la page Presse-papiers de
l'île (`toggleHistoryWindow`, Svc:1301-1308, renvoie vers l'île quand `routesClipboardWindow()` est vrai).

| Fonction | État | Où |
|---|---|---|
| Bandeau horizontal en bas de l'écran du pointeur | Oui | Sup:8-24, Svc:1488-1501, QP:135-147 |
| Grandes cartes avec aperçu (texte 7 lignes, vignette, fichiers) | Partiel (184 × 210 pt) | QP:371, 481-506, 595-638 |
| App source, heure | Oui (app connue si une seule au premier plan) | QP:520-574, Ign:120-137 |
| Couleur de l'app, type de contenu détaillé | Non / partiel | QP:592-609 |
| ←/→, Entrée colle, ⇧Entrée copie, ⌘1–9 | Oui | Sup:935-954, Svc:1577-1628 |
| Double-clic pour coller | Non (un clic colle) | QP:447, 745-758 |
| Recherche en tapant, surlignage | Oui | Svc:495-556, Sup:756-915 |
| Collage dans l'app au premier plan | Oui (Accessibilité) | Svc:1344-1396 |
| Épinglage (hors limite, jamais expiré) | Oui | Sup:192, 391-468 |
| Pinboards nommés et colorés, glisser-déposer | Non | — |
| Aperçu (Espace), menu contextuel | Oui | Svc:1571-1576, QP:719-743 |
| Formats conservés | Partiel : texte brut, PNG/TIFF, fichiers ; pas de texte riche | Svc:890-928 |
| Presse-papiers universel | Partiel, lu dans le code, pas testé | Sup:1140-1142, Svc:769-770 |

## Architecture recommandée : un bandeau propre au fork

La carte de l'upstream (`QuickEntryView`) est privée, et les fichiers du presse-papiers bougent beaucoup
(44 commits upstream depuis septembre). Un bandeau du fork pose 2 lignes dans Svc et 1 dans Set, et
réutilise les fonctions internes de l'upstream : entrées, recherche, copie, épinglage, vignettes, aperçu,
collage. Contrepartie : le fork redessine cartes et clavier, sans profiter des évolutions du bandeau upstream.

## Sous-lots

- **3a. Bandeau façon Paste** (environ 800 à 1 000 lignes). Ouvert par tous les points d'entrée de
  l'historique, en bas de l'écran du pointeur, glissé depuis le bas. Carte : app, aperçu, heure, ⌘n.
  Clavier : ←/→, recherche en tapant, Entrée colle, ⇧Entrée copie, ⌘1–9, ⌘⌫, ⌥P, Espace, Échap.
  Raccords : en tête de `toggleHistoryWindow()` et `showHistoryWindow(preferNotch:)` (2 lignes, non extraites
  par les tests), `ForkClipboardSettingsSection()` dans Set. Préférence `forkClipboardShelf` (vrai).
  Fichiers : `Fork/Core/ForkClipboardShelfLayout.swift`, `Fork/ForkClipboardShelf.swift`,
  `Fork/ForkClipboardShelfView.swift`, `Fork/ForkClipboardSettingsSection.swift`, tests.
- **3b. Pinboards** (environ 500 lignes). Groupes nommés et colorés d'éléments **épinglés** (la
  conservation est celle de l'épinglage), un pinboard par élément. Onglets : Historique, Épinglés, puis un
  par pinboard ; ⌘←/→ change d'onglet ; « Ranger dans ▸ ». Stockage `ForkClipboardBoards.json` à côté de
  l'historique, version 1, droits 0600, hors sauvegarde des réglages. Aucun raccord.
- **3c. Finitions des cartes** (environ 200 lignes). Bande teintée par la couleur de l'icône de l'app,
  type et détail (n caractères, domaine d'un lien, couleur, L×H, nombre de fichiers). Aucun raccord.
- **3d. Glisser-déposer** (environ 200 lignes). Carte vers un pinboard, réordonnancement, carte vers une
  autre app. Aucun raccord.
- **3e. Presse-papiers universel** (vérification sans code) : iPhone → Mac (texte, lien, photo) et
  inverse. Une photo JPEG ou HEIC pourrait ne pas entrer (lecture limitée au PNG et au TIFF, fonction
  privée de l'upstream) : à proposer en ticket upstream plutôt qu'à modifier.

## Risques

Collage bloqué par un champ en saisie sécurisée ; Electron et Chrome à tester ; ⇧⌘V, s'il est choisi,
remplace « Coller et adapter le style » partout ; un double-clic retarde le simple clic en SwiftUI ;
un désépinglage fait ailleurs sort l'élément de son pinboard sans prévenir ; plein écran et Spaces à tester.

## Questions

1. Raccourci : garder ⌃⌥⌘V ou passer à ⇧⌘V comme Paste ? Recommandation : ⇧⌘V.
2. Bandeau activé, le raccourci ouvre-t-il le bandeau plutôt que la page de l'île ? Recommandation : oui.
3. Pinboards : groupes d'épinglés (un pinboard par élément) ou copies indépendantes ? Recommandation : groupes.
4. Clic : un clic sélectionne, double-clic ou Entrée colle (Paste), ou un clic colle (upstream) ? Recommandation : Paste.
5. Dimensions : provisoires tout de suite, ou attendre tes captures de Paste ? Recommandation : provisoires.
