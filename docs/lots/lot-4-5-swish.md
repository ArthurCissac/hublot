# Lots 4 et 5 : Swish

Préparé le 21/11/2026, validé le même jour (« Code Swish » : les cinq recommandations ci-dessous). Chemins relatifs à `Sources/Vorssaint/`.

## Ce que Vorssaint fait déjà

**Lot 4, gestes sur la barre de titre**

| Brique | État | Où |
|---|---|---|
| Geste sur la barre de titre | Non | — |
| Trackpad ou molette | Oui | `Services/ScrollWheelSupport.swift:148-153, 353-371` |
| Fenêtre sous le pointeur sans Accessibilité | Oui | `WindowServerSupport.swift:129-151, 192-222` |
| Fenêtre sous le pointeur par Accessibilité | Partiel (privé) | `WindowMaximizer.swift:276-330` ; public : `AXWindowResolver` |
| Direction en 8 secteurs | Oui, public | `WindowGestureSupport.swift:310-336` |
| Moitiés, quarts, agrandir, plein écran, écran voisin | Partiel : `apply` n'agit que sur la fenêtre active | `WindowLayoutService.swift:236-240, 423-474` |
| Réduire, fermer | Partiel / oui | `WindowActivator.setWindowMinimized` (543-578), `closeWindow` (582-607) |
| Pincement | Non (champs des événements connus) | `ScrollInverter.swift:405-413` |
| Conventions des taps (écoute seule, réactivation) | Oui | `WindowLayoutService.swift:1056-1077`, `MiddleClickService.swift:486-516` |

**Lot 5, changer de fenêtre au trackpad**

| Brique | État | Où |
|---|---|---|
| Sélecteur au clavier, défilement dans un sélecteur ouvert | Oui | `AppSwitcher.swift`, `SwitcherSupport.swift:63-132` |
| Ouvrir le sélecteur par un geste | Non | session ouverte par le clavier seulement (`beginPendingSession` privé) |
| Lecture des doigts | Partiel (pont MultitouchSupport privé du clic du milieu) | `MiddleClickService.swift:652-758` |

Sur ce Mac, les balayages à trois et quatre doigts appartiennent à macOS (espaces, Mission Control).

## Tickets upstream

#967 (ouvert, chapeau) : lire le défilement continu et ses phases, tester la fenêtre au début, cumuler,
appeler la logique existante ; l'Accessibilité est trop lente sur le fil du tap. #579 : mosaïque façon Swish
par balayage sur la barre de titre. #864 : trois doigts pour passer d'une fenêtre à l'autre. #3598 : naviguer
dans le sélecteur à trois doigts, relâcher pour valider. La PR #3395 (« Réduire ») n'est pas dans notre arbre.

## Sous-lots, par ordre de valeur (compteurs de Swish : quarts 1 226, réduire 1 098, agrandir 1 023,
moitiés 647, écran voisin 411, plein écran 147, fermer 145)

- **4a. Balayage à deux doigts sur la barre de titre** (environ 78 % des actions) : ←/→ moitiés,
  diagonales quarts, ↑ agrandir, ↓ réduire, au lever des doigts, seuil d'environ 50 pt. Tap en **écoute
  seule** sur le défilement ; test WindowServer au début du geste, Accessibilité sur une file à part.
  Raccords : `WindowLayoutService.apply` gagne un paramètre `window:` (2 lignes), 1 ligne de réglages.
  Préférence `forkTitleBarSwipeEnabled`. Fichiers : `Fork/Core/ForkTitleBarGestureLogic.swift`,
  `Fork/ForkTitleBarGestures.swift`, `Fork/ForkTitleBarGestureSection.swift`, tests.
- **4b. Écran voisin** : ⇧ + balayage vers l'écran voulu. Aucun raccord.
- **4c. Pincer et écarter sur la barre de titre** : fermer et plein écran (à confirmer à l'observation).
- **4d. Avaler le défilement** : un tap actif, seulement si 4a montre une fuite gênante.
- **4e. Aperçu pendant le geste** : panneau du fork dessiné avec `WindowLayoutGeometry.rect`.
- **5a. Trois doigts ←/→ : ouvrir le sélecteur et avancer, lever pour valider** : copie du pont
  MultitouchSupport dans `Fork/`, aucun event tap ; un bloc d'environ 20 lignes en fin de `AppSwitcher.swift`
  pour ouvrir une session depuis le fork. Demande de passer « Balayer entre les apps en plein écran » à
  quatre doigts dans Réglages Système ; en attendant, Hublot ne réagit pas et l'explique.
- **5b. Trois doigts ↑/↓ : changer de rangée** dans une session ouverte, si Mission Control ne s'en mêle pas.
- **5c. Portée** : toutes les apps, ou les fenêtres de l'app au premier plan.

## Risques

Fuite du défilement vers l'app (barres d'onglets de Safari et Chrome, apps Electron où un balayage
horizontal peut revenir en arrière) ; position des boutons sous Electron ; écran voisin approximatif à trois
écrans ; plein écran et Stage Manager non couverts ; deux abonnés à MultitouchSupport (clic du milieu et fork)
non vérifiés ; Swish lancé en même temps ferait agir chaque geste deux fois.

## Questions

1. Lot 4 : modifier 2 lignes de `WindowLayoutService.apply` (paramètre `window:`), ou activer d'abord la
   fenêtre puis appeler `apply`, au prix d'une course possible ? Recommandation : les 2 lignes.
2. Carte des gestes : ←/→ moitiés, diagonales quarts, ↑ agrandir, ↓ réduire, ⇧ + balayage écran voisin,
   pincer fermer, écarter plein écran. Recommandation : oui, à corriger après observation de Swish.
3. Fuite du défilement : écoute seule d'abord, tap actif seulement si les tests le justifient ? Recommandation : oui.
4. Lot 5 : passer les balayages plein écran à quatre doigts dans Réglages Système, portée par défaut toutes
   les apps avec un réglage « fenêtres de l'app » ? Recommandation : oui aux deux.
5. Lot 5 : copie du pont MultitouchSupport et bloc en fin de `AppSwitcher.swift`, plutôt que `NSTouch` (pont
   Objective-C à ajouter à `build.sh`, fragile avec Universal Control) ? Recommandation : MultitouchSupport.

## Suite : Swish au complet (validée le 21/11/2026, « tout ok »)

Après le relevé des réglages de Swish (`docs/reference/swish.md`) :

- **4f.** Section « Gestes façon Swish » en tête de Disposition des fenêtres (raccord déplacé, aucune
  ligne de plus). Modificateurs aux valeurs de Swish : super ⌘, général fn, écran ⇧, secondaire
  fn⌃⌥, tertiaire fn⌥. Bouton « Reprendre mes réglages Swish ». ⌘ + flèches (⌘↓ réduit, deux
  flèches de suite : un quart), ⇧⌘ + flèche : écran. ⌘O n'est pas intercepté.
- **4d, 4g.** ⌘ maintenu : gestes partout dans la fenêtre. Tap actif éteint hors geste, qui retient
  défilement et pincement pendant le geste et son élan. fn ↓ fermer, fn ↑ presque plein écran ;
  fn⌃⌥ coins 3×2, ↑/↓ moitiés haute et basse, ←/→ tiers ; fn⌥ cases 3×3 (les cases du centre des
  grilles ne sont pas atteintes). Pincer ou fn ↓ deux fois : quitter.
- **4h.** Double toucher à deux doigts (pont MultitouchSupport partagé) : centrer. Retour haptique,
  annulation par Échap ou 0,8 s d'immobilité, sensibilité 1 à 5.
- **4e.** Cadre translucide qui montre la place de la fenêtre pendant le balayage.
- **4i.** Icônes du Dock : ←/→ fenêtres de l'app, ↓ réduire, ↑ faire revenir, pincer ou fn ↓ quitter,
  fn⌃⌥ : toutes les fenêtres.

Choix faits sans le bas de l'onglet Snapping (à corriger après capture) : moitiés haute et basse
sur fn⌃⌥ ↑/↓, presque plein écran sur fn ↑, tiers sur fn⌃⌥ ←/→.
