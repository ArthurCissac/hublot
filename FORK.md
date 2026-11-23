# Hublot : notes du fork

Hublot est un fork **personnel et non officiel** de
[Vorssaint](https://github.com/vorssaint/vorssaint-utils), sous licence GPL-3.0-or-later.
Il n'est ni publié ni soutenu par l'auteur de Vorssaint, et n'est pas distribué.

- `origin` : `ArthurCissac/hublot` (ce dépôt, public).
- `upstream` : `vorssaint/vorssaint-utils` (lecture seule : le push y est désactivé en local).

Ce fichier décrit ce que le fork change, pourquoi, et comment le garder à jour.
Le plan des fonctions à ajouter est dans `docs/HUBLOT-PLAN.md`, les règles de travail dans `CLAUDE.md`.

## Principe

L'upstream est très actif. Chaque ligne modifiée dans un de ses fichiers est un conflit de rebase
potentiel. Le fork tient donc en trois idées :

1. **Tout ce qui lui est propre vit dans de nouveaux fichiers** : `Fork/` (outillage) et
   `Sources/Vorssaint/Fork/` (Swift).
2. **Le nom est défini une seule fois**, dans `Fork/identity.sh`.
3. **Le renommage se fait au moment du build**, pas dans les sources (voir « La passe d'identité »).

Les fichiers de l'upstream ne portent que des appels d'une ligne, listés dans « Surface de conflit ».

## Identité

| | Variante quotidienne | Variante Developer (`./build.sh --dev`) |
|---|---|---|
| Nom | Hublot | Hublot (Developer) |
| Exécutable | `Hublot` | `HublotDeveloper` |
| Bundle id | `agency.nexflow.hublot` | `agency.nexflow.hublot.dev` |
| Optimisation | `-O` | `-Onone` |

Les deux variantes ont leurs propres préférences, autorisations macOS et helper de ventilateurs.
Elles coexistent avec le Vorssaint officiel (`com.vorssaint.utils`) sur le disque, mais ne doivent
pas tourner en même temps que lui (voir « Cohabitation »).

Pour renommer le fork : modifier `Fork/identity.sh`, puis rebuilder. Changer le bundle id revient à
créer une nouvelle app pour macOS : préférences, autorisations et helper repartent de zéro.

Non renommés, volontairement : le dossier `Sources/Vorssaint/`, les modules, le drapeau
`VORSSAINT_DEVELOPMENT`, les clés de préférences, les en-têtes de copyright.

## La passe d'identité

« Vorssaint » apparaît dans environ 1 600 endroits des textes de l'interface, en 15 langues, dans
des fichiers que l'upstream modifie en permanence. Les réécrire créerait des conflits à chaque
rebase. À la place :

- `Fork/brand.py` écrit un **miroir** de `Sources/Vorssaint` dans `build/objects/fork-sources/`, où
  les règles ci-dessous sont appliquées ;
- `build.sh` compile ce miroir au lieu des sources ;
- les sources restent celles de l'upstream, et les tests continuent de les compiler telles quelles.

Les nouvelles chaînes ajoutées par l'upstream sont donc renommées sans rien faire.

| Règle | Remplace | Par |
|---|---|---|
| `bundle-id` | `com.vorssaint.utils` (le suffixe `.dev` est conservé) | `agency.nexflow.hublot` |
| `id-prefix` | le préfixe `com.vorssaint` | `agency.nexflow.hublot` |
| `upstream-host` | `screenshots.vorssaint.com` | `upstream-service-disabled.invalid` |
| `app-name` | `Vorssaint`, sauf suivi d'une majuscule, d'un chiffre ou de `_` | `Hublot` |
| `team-id` | `3D485NHW29` (équipe Apple de Vorssaint) | `FORK_TEAM_ID` |

Détails utiles :

- La règle `app-name` laisse intacts les identifiants composés (`VorssaintBuildCommit`,
  `keepAwakeActiveIconVorssaint`, `libVorssaintNowPlaying`) et les lignes de copyright.
- Les règles `bundle-id` et `id-prefix` corrigent aussi les endroits où l'app se reconnaît
  elle-même : sans elles, « Quitter toutes les apps » fermerait Hublot, et le nettoyeur proposerait
  de vider son cache.
- Une règle qui toucherait du **code** (hors chaîne et hors commentaire) renommerait un identifiant :
  le build s'arrête et désigne la ligne.
- Les fichiers du miroir s'appellent `X.mirror.swift`. Chacun commence par une directive
  `#sourceLocation`, donc **les erreurs du compilateur citent le vrai fichier** et la bonne ligne.
  Exception : `main.swift` doit garder son nom (c'est le point d'entrée), il n'a donc pas de
  directive et une erreur dans ce fichier cite le chemin du miroir.
- `Sources/Vorssaint/Fork/` est recopié **tel quel** : ces fichiers nomment Vorssaint exprès
  (attribution, détection de l'app officielle).
- Les textes du bundle (`Info.plist`, les 14 `InfoPlist.strings`, donc les demandes d'autorisation)
  sont renommés dans la copie préparée par le build. `Resources/` reste tel que l'upstream le livre.
- Une demande d'autorisation est réécrite par le fork quand il fait de l'autorisation un usage que
  l'upstream n'a pas : la caméra, dont l'upstream promet qu'elle n'est jamais enregistrée alors que
  la bulle caméra entre dans les vidéos. Ces textes sont dans `BUNDLE_TEXTS` (`Fork/brand.py`), en
  anglais et en français, avec `{name}` pour le nom de l'app ; les autres langues affichent l'anglais.
  C'est la seule exception à la règle des textes dans `ForkStrings.swift` : un texte d'`Info.plist`
  ne peut pas venir du code. Si l'upstream retire la clé, le build s'arrête.

**Règle pour le code du fork :** dans une chaîne affichée, ne jamais écrire le nom de l'app en dur.
Utiliser `AppInfo.name`.

```sh
python3 Fork/brand.py audit      # ce que les règles touchent, et aucune correspondance dans du code
python3 Fork/brand.py selftest   # les règles elles-mêmes
```

## Ce que le fork change dans le comportement

| Sujet | Upstream | Hublot |
|---|---|---|
| Mises à jour | Télécharge et installe la release officielle | Jamais. « Rechercher des mises à jour » répond « à jour » sans réseau |
| Helper des ventilateurs | Exige l'équipe Apple de Vorssaint | Exige l'équipe du fork (`FORK_TEAM_ID`) |
| Partage en ligne de captures et de vidéos | Envoie vers `screenshots.vorssaint.com` | Désactivé : les boutons de partage sont masqués |
| Feedback | Envoie vers `screenshots.vorssaint.com` | L'envoi échoue (hôte neutralisé) |
| À propos | Copyright Vorssaint | Copyright Vorssaint inchangé, plus une ligne « fork non officiel » et le lien vers ces sources |
| Lancement | — | Alerte si le Vorssaint officiel tourne en même temps |
| Captures d'image | Les icônes du bureau figurent dans l'image | Absentes de l'image par défaut (réglage « Capturer sans les icônes du bureau ») |
| Son de capture | Aucun | Le son de capture d'écran de macOS, lu depuis le système (réglage « Jouer un son à la capture ») |
| Historique du presse-papiers | Liste, cartes ou page de l'île selon les réglages | Par défaut, un bandeau aux mesures de Paste (`docs/reference/paste.md`) : toute la largeur de l'écran, 332 pt de haut, monté depuis le bas par-dessus le Dock, cartes carrées de 232 pt à bande colorée ; en Liquid Glass sur macOS 26 et ensuite, teinte au choix et à l'intensité réglable (« Teinter le bandeau ») ; le plus récent d'abord, recherche en tapant, Entrée colle dans l'app qui était devant, double-clic colle, ⌘1–9, Espace pour l'aperçu de l'upstream ; onglets Historique, Épinglés et pinboards nommés et colorés, ⌘←/⌘→ pour passer de l'un à l'autre ; bandeau de chaque carte à la couleur de l'icône de son app, et sous l'aperçu le nombre de caractères, le site d'un lien, la couleur d'une valeur de couleur, la taille d'une image ou le nombre de fichiers (réglage « Ouvrir l'historique en bandeau de cartes ») |
| Son à chaque copie | Aucun | « Pop » de macOS à chaque nouvelle copie enregistrée par l'historique (réglage « Son à chaque copie » : six sons de macOS ou aucun) ; un collage depuis le bandeau n'en joue pas |
| Gestes sur la barre de titre (Swish) | Aucun | Deux doigts sur la barre de titre : ←/→ moitiés, diagonales quarts, ↑ agrandir, ↓ réduire, ⇧ + ←/→ écran voisin ; pincer ferme, écarter met en plein écran ; sur la fenêtre sous le pointeur (réglages dans Disposition des fenêtres) |
| Sélecteur de fenêtres au trackpad (Swish) | Clavier seulement | En option, trois doigts sur le côté ouvrent le sélecteur, avancent d'une fenêtre par pas, et le lever des doigts choisit (réglage sous les raccourcis du sélecteur) ; en retrait tant que macOS utilise trois doigts pour les apps en plein écran |
| Capture défilante | Verticale seulement | En plus, depuis le menu ⇧⌘5, un bouton « Horizontale » du volet « Défilante » (défilement à la main) |
| Capture d'une fenêtre | La fenêtre seule, sans ombre ; le fond n'existe que dans l'éditeur | Réglage « Capture d'une fenêtre » : telle quelle, avec son ombre (par défaut, fond transparent) ou sur le dernier fond choisi dans l'éditeur |
| Aperçu après capture | Panneau de 350 × 210, ou dans l'île | Carte de 210 × 150 en bas à gauche de l'écran du pointeur (réglage « Afficher l'aperçu en carte ») |
| Menu de capture | Choix de l'outil dans la sélection, ou dans l'île | En plus, une barre de sept modes ouverte par ⇧⌘5 (réglage « Menu de capture ») |
| Réglages de capture | Une trentaine de réglages sur cinq sections, par outil | Une page courte en tête ; la page d'origine reste accessible par « Tous les réglages » |
| Image épinglée | Déplacement, redimensionnement par les bords, menu au clic droit | En plus, au survol, une barre de boutons : fermer, remettre dans les aperçus, modifier, enregistrer, glisser vers une app, réduire, agrandir |
| Image posée sur une vidéo (montage) | Neuf positions au choix, taille par un curseur, jusqu'à 60 % de la largeur | En plus, sur l'aperçu : un clic sélectionne l'image, la glisser la place où l'on veut, une poignée à chaque coin règle sa taille, jusqu'à toute la largeur ; une poignée ronde au-dessus la fait pivoter sur 360° (calée sur les quarts de tour à 5° près, par 15° avec Maj, droite au double-clic) ; une petite barre au-dessus offre le miroir gauche-droite, l'angle et « remettre droit » |
| Son d'une vidéo (montage) | Les deux sons enregistrés : celui du Mac et le micro, chacun avec son volume, jusqu'à 100 % | En plus, une musique ajoutée depuis un fichier : un bouton à côté de « ajouter une image », une piste sur la timeline avec son volume et un bouton pour la retirer ; et une ligne « Amplifier » sous le micro, de 100 % à 400 % |
| Touches pressées pendant un enregistrement | Seuls les instants de frappe sont notés, pour les zooms | En option (bouton « Touches » du volet vidéo, réglage dans Capture d'écran), les raccourcis, ou toutes les touches, deviennent des textes du montage en bas de la vidéo |
| Ne pas déranger pendant un enregistrement | Rien | Deux raccourcis de l'app Raccourcis, créés une fois par l'utilisateur sous des noms donnés par le fork, sont lancés au début et à la fin (réglage « Activer Ne pas déranger pendant l'enregistrement ») |
| Enregistrement vidéo | Son en stéréo, anneau de clic activé par défaut, micro : l'entrée par défaut du système | Son en mono par défaut ; anneau de clic désactivé par défaut ; micro du Mac par défaut, même casque branché ; en option, une bulle avec l'image de la caméra (ronde, carrée ou rectangle 16:9, de taille réglable), filmée avec le reste ; tout se règle dans le volet vidéo du menu de capture |

Précisions :

- **Mises à jour.** L'updater de l'upstream vérifie la release contre le bundle id et l'équipe de
  Vorssaint, l'installe, puis supprime le bundle en cours s'il porte un autre nom : il remplacerait
  Hublot par l'app officielle. Ses 5 points d'entrée sont fermés par `AppInfo.neverSelfUpdates`.
  Hublot se met à jour par rebase (voir plus bas).
- **Partage en ligne.** `ForkBootstrap` force les deux préférences à « non » au lancement. Les deux
  interrupteurs existent toujours dans les Réglages (vues de l'upstream) : les activer les fait
  revenir aussitôt à « non ».
- **Feedback.** Les boutons « Envoyer un retour » restent visibles (réglages généraux, panneau du
  menu, barre de commandes). Les masquer demanderait de modifier trois fichiers de l'upstream.
  L'envoi échoue : rien ne part vers l'auteur de Vorssaint.
- Deux lectures publiques sont conservées, sans envoi de données : la vidéo des nouveautés
  (`UpdateShowcaseMedia`) et la grille de prix des agents (`AgentPriceSource`), toutes deux sur GitHub.
- **Icônes du bureau.** La fenêtre des icônes du Finder est ajoutée à la liste des fenêtres que la
  capture exclut. Rien ne change à l'écran : pas de redémarrage du Finder, rien à restaurer. La
  fonction « Watch » de l'île, qui lit l'écran par le même chemin, garde les icônes.
  L'enregistrement vidéo n'est pas concerné (lot 7).
- **Son de capture.** Aucun fichier son n'est embarqué : l'app lit celui que macOS fournit, par le
  service des sons système, donc au volume des alertes et en respectant « Émettre les effets
  sonores de l'interface ». Si macOS déplace ce fichier, la capture reste muette (un test le signale).
- **Aperçu en carte.** Dimensions et marges mesurées sur l'app de référence
  (`docs/reference/cleanshot-x.md`), dessin et icônes propres au fork. La carte reprend les actions
  de l'aperçu de l'upstream (copier, enregistrer, modifier, épingler, jeter) et ne prend jamais le
  clavier. Elle remplace aussi l'aperçu dans l'île. Réglage désactivé : comportement de l'upstream.
  Fermer l'éditeur renvoie l'image, modifications comprises, en carte : l'éditeur ne demande donc
  plus s'il faut abandonner les modifications.
  Le pointeur sur une carte, ⌘C copie, ⌘S enregistre, ⌘W la range, ⌘E ouvre l'éditeur (les lettres
  sont lues telles que tapées : ⌘W est la touche W d'un clavier AZERTY). Comme la carte ne prend pas
  le clavier, ces quatre touches sont prises par un event tap qui n'existe que pendant le survol
  d'une carte et ne retient qu'elles. Un balayage à deux doigts vers la gauche la range ; un balayage
  trop court la fait revenir. ⌥⇧⌘R rouvre la dernière carte rangée (préférences
  `forkReopenPreviewShortcutEnabled` et `forkReopenPreviewShortcut`, sans champ de réglage pour
  l'instant) ; une capture jetée, épinglée ou ouverte dans l'éditeur n'est pas reprise.
- **Menu de capture.** Son raccourci ouvre une sélection de l'upstream, lancée par le fork dans son mode
  « où », qui ne photographie rien. La zone tracée reste à l'écran, encadrée, avec dessous une barre
  aux proportions mesurées sur l'app de référence. Les boutons décident de la suite : image, capture
  défilante, texte, vidéo, ou plein écran, fenêtre, délai. « Défilante » et « Vidéo » ouvrent chacun
  un volet avec un bouton pour démarrer : défilement automatique en option pour l'une ; pour l'autre, micro (chaque clic passe au micro
  suivant, celui du Mac en premier, puis le coupe), son du Mac, mono, clics, caméra, forme de la bulle et compte à rebours. Chaque action remet la zone au point
  d'entrée par lequel les outils de l'upstream en reçoivent déjà une, après vérification de la
  fonction. « Fenêtre » fait exception : la fenêtre cliquée ensuite est photographiée aussitôt, sans
  passer par une zone encadrée. Le bandeau d'aide de l'upstream (« faites glisser… ») n'est pas
  affiché sous ce menu, et Échap le ferme à tout moment, quelle que soit l'app au premier plan.
  La zone encadrée se déplace, se redimensionne par ses bords et ses coins (Maj : carré), et une
  étiquette au-dessus montre sa taille en pixels et son format : un clic passe de Libre à 1:1, 4:3,
  16:9, 9:16, 1280×720 puis 1920×1080. Le menu s'ouvre sur la dernière zone encadrée (réglage, et
  préférence `forkCaptureMenuLastArea` gardée hors des sauvegardes : elle décrit les écrans de ce Mac).
  Aucun fichier de l'upstream n'appelle le menu : `ForkBootstrap` l'enregistre au lancement.
  Le raccourci se règle par la préférence `forkCaptureMenuShortcut` ; il n'a pas encore de champ de
  saisie dans les Réglages.

## Ajouter une fonction au fork

Les fonctions ajoutées (lots de `docs/HUBLOT-PLAN.md`) suivent toutes le même montage, pour que
l'upstream ne gagne qu'une ligne par point de raccord :

| Quoi | Où |
|---|---|
| Logique pure, testable | `Sources/Vorssaint/Fork/Core/` (compilée aussi dans les tests) |
| Raccords avec AppKit, ScreenCaptureKit, vues SwiftUI | `Sources/Vorssaint/Fork/` |
| Clés de préférences, préfixées `fork` | `Sources/Vorssaint/Fork/Core/ForkDefaults.swift` |
| Valeur par défaut de chaque clé | le bloc du fork, en tête de `Defaults.registeredDefaults` (`Core/Defaults.swift`) |
| Textes, en français et en anglais | `Sources/Vorssaint/Fork/ForkStrings.swift` |
| Réglage visible | une ligne dans `Sources/Vorssaint/Fork/ForkCaptureSettingsPage.swift` |
| Tests | `Fork/Tests/`, appelés depuis `Fork/Tests/ForkTests.swift` (suite `fork`) |
| Contrôle du raccord | une entrée dans `Fork/check.sh` |

Piège : les tests recompilent des extraits de fichiers de l'upstream (`Tests/generate_sources.py`
en dresse la liste, déclaration par déclaration). Un raccord posé dans une déclaration extraite ne
peut appeler que du code de `Sources/Vorssaint/Fork/Core/`, seul dossier du fork compilé par les
tests ; sinon `./build.sh --test` ne compile plus. Exemple vécu : `editorDidClose` du service de
capture, d'où le raccord placé dans l'éditeur.

Une clé enregistrée dans `Defaults.registeredDefaults` voyage automatiquement dans la sauvegarde
des réglages. Un état propre à la machine doit en plus être ajouté à
`SettingsBackupSupport.machineStateKeys`, qui est à l'upstream. Le fork fait plus simple pour le
sien : la clé n'est pas enregistrée du tout, donc jamais exportée, et sa ligne dans
`ForkDefaults.swift` porte le commentaire `// not registered`, que `Fork/check.sh` reconnaît.
Exemple : `forkRecorderMicrophoneID`, le micro choisi, qui n'existe que sur ce Mac.

La bulle caméra ne touche à aucun fichier de l'upstream. C'est une fenêtre ordinaire de l'app,
affichée avant le début de l'enregistrement : l'enregistreur de l'upstream garde les fenêtres
ordinaires de l'app dans l'image et construit son filtre une seule fois, au démarrage. Deux
conséquences : une bulle affichée après le démarrage ne serait pas filmée ; et une fenêtre cliquée,
que l'upstream enregistre seule depuis son propre tampon, ne contiendrait pas la bulle. Caméra
active, le fork fait donc enregistrer la zone de la fenêtre (`ForkRecorderOptions.recordedRegion`) :
la bulle est dans la vidéo, mais l'enregistrement ne suit plus la fenêtre si elle bouge. L'upstream ne signale pas la
fin d'un enregistrement : une minuterie, vivante seulement tant que la bulle est affichée, la
retire quand `ScreenRecorderService.hasActiveCapture` retombe. La bulle se déplace en la glissant et
se redimensionne en tirant son bord ou en la pinçant, avant comme pendant l'enregistrement : rien
d'autre qu'elle n'apparaît dans la vidéo. Tant que le menu de capture est ouvert, elle est placée
au-dessus de ses fenêtres pour rester manipulable ; elle redevient une fenêtre flottante ordinaire
au démarrage. Sa forme se choisit dans le volet vidéo, puis par un clic droit sur la bulle pendant
l'enregistrement (ce menu-là est filmé s'il est dans la zone). Taille et forme sont mémorisées
(`forkRecorderCameraSize`, `forkRecorderCameraShape`) ; la position revient au coin bas droit de
chaque nouvelle zone. La caméra s'ouvre sur sa propre file : sur le fil principal, elle fige l'écran.

Bandeau du presse-papiers : `ForkClipboardShelf` est ouvert par tous les points d'entrée de
l'historique (raccourci, menu, barre de commandes, île), avant le renvoi de l'upstream vers sa
fenêtre ou l'île. Il réutilise les fonctions internes de l'upstream (entrées, recherche avec sa propre
surface, copie, épinglage, suppression, vignettes, aperçu) et colle par `TransientPaste` dans l'app qui
était au premier plan. Sa fenêtre prend le clavier sans activer l'app. Réglage désactivé : l'upstream.
Les pinboards sont des groupes nommés et colorés d'éléments **épinglés** de l'upstream, un tableau par
élément : l'épinglage garantit la conservation, le fichier `ForkClipboardBoards.json` (à côté de
l'historique, droits 0600, hors sauvegarde des réglages) ne liste que les identifiants. Supprimer un
tableau rend ses éléments aux épinglés ; un élément désépinglé ailleurs quitte son tableau.
Glisser-déposer : une carte glissée vers une autre app y porte son texte, son image ou son premier
fichier ; déposée sur l'onglet d'un tableau elle y est rangée, sur Épinglés elle quitte son tableau ; dans
un tableau, déposée sur une autre carte elle passe juste avant. Le bandeau reconnaît ses propres cartes
par l'élément d'origine (`ForkClipboardDrag`), jamais par leur contenu : un texte glissé depuis une
autre app n'est pas pris pour une carte.

Gestes sur la barre de titre : un event tap en **écoute seule** sur le défilement et les gestes du trackpad
(`ForkTitleBarGestures`), créé seulement si un des deux réglages est actif, la disposition des fenêtres
disponible et l'Accessibilité accordée. Son rappel ne fait que des calculs, plus une lecture de la liste
des fenêtres au début du geste ; l'Accessibilité et le déplacement viennent après. Aucun événement n'est
avalé : l'app sous le pointeur reçoit aussi le défilement. `WindowLayoutService.apply` gagne un paramètre
`window:` (2 lignes modifiées et une petite extension en fin de fichier, qui lit les vérifications privées
du service) pour agir sur la fenêtre sous le pointeur sans se rabattre sur la fenêtre active.

Sélecteur au trackpad : pas d'event tap. Les trames du trackpad sont lues par une copie, propre au fork,
du pont MultitouchSupport du clic du milieu (`ForkTrackpadSwitcher`), qui ne retire que son propre rappel
à l'arrêt. Une session du sélecteur s'ouvre comme par son raccourci, depuis une extension en fin de
`AppSwitcher.swift` qui touche ses membres privés sans modifier aucune ligne extraite par les tests.
Pendant la session, toute touche de modification la valide, comme au clavier.

Capture défilante horizontale : chaque image est tournée d'un quart de tour dans le sens horaire avant
l'assemblage vertical de l'upstream, puis l'image assemblée est remise droite (`ForkScrollingDirection`,
trois lignes dans `ScreenshotScrollingCapture.swift`). Le menu arme la direction juste avant de lancer
la capture, qui la fixe à sa première image ; une capture lancée autrement reste verticale. Le
défilement automatique, vertical, est exclusif de la direction horizontale.

Style des captures de fenêtre : la sélection de l'upstream rend une fenêtre comme une simple image, et
ses tests recompilent `confirmWindow` avec des types de remplacement (`Tests/generate_sources.py`) :
le raccord n'y peut appeler qu'une fonction de `Fork/Core` sans image. Il y laisse donc une note
(« une fenêtre vient d'être cliquée », valable 3 s), et l'outil de capture, à la réception, applique
l'ombre ou le fond (`ForkWindowCaptureStyler`). Une fenêtre envoyée à la reconnaissance de texte
n'est pas stylée.

Touches affichées : `ForkRecorderKeyCapture` écoute le clavier (moniteur global, écoute seule)
uniquement pendant un enregistrement lancé avec l'option, pauses déduites. Rien n'est écrit sur
disque : à la première ouverture de l'enregistrement dans l'éditeur, une ligne de l'upstream
(`RecorderEditorController.load`) fait ajouter les touches comme textes du montage, en un seul pas
d'annulation. Aucun raccord dans le moteur de rendu : aperçu et export sont ceux des textes. Un
enregistrement envoyé directement en fichier, sans passer par l'éditeur, n'a pas les touches.

Ne pas déranger : macOS ne laisse aucune app changer de mode de concentration. Le fork lance donc deux
raccourcis de l'app Raccourcis (`/usr/bin/shortcuts run`), nommés « <app> – Activer Ne pas déranger »
et « <app> – Désactiver Ne pas déranger » (ou leur version anglaise), que l'utilisateur crée une fois
(bouton « Créer… » des réglages). `ForkRecorderFocusService` observe `ScreenRecorderService.isRecording`,
publié par l'upstream : aucun raccord. Limite assumée : Ne pas déranger est désactivé à la fin même
s'il était actif avant l'enregistrement, faute de pouvoir lire l'état de la concentration.

Amplifier le micro : un test de l'upstream impose que son volume reste borné à 100 %, et le volume d'un
mixage AVFoundation plafonne à 1. Le fork ajoute donc au micro un tap audio (`MTAudioProcessingTap`) qui
multiplie les échantillons, crêtes adoucies au-delà de 0,8 (`ForkRecorderAudioBoost`), posé par une ligne
de `RecorderComposition.audioMix` : l'écoute dans l'éditeur et l'export l'entendent tous deux.

Image tenue sur l'aperçu : pendant un geste, l'aperçu dessine l'image sous le pointeur et la vidéo la
laisse de côté (`ForkRecorderImageVisibility`, lue par le moteur de rendu) ; une fois lâchée, l'aperçu
la garde jusqu'à ce que l'upstream ait reconstruit la vidéo avec sa nouvelle place, puis la lui rend
(`ForkRecorderImageDrag`). Une seule image se voit à tout moment. Avant le geste, la tête de lecture
se place là où l'image est dessinée en entier.

L'image posée sur une vidéo garde le modèle de l'upstream, avec un champ de plus : `forkCenter`, son
centre dans l'image finale, en proportions (0 à 1, origine en haut à gauche). Absent, l'image est
exactement où l'upstream la met : un montage enregistré avant, ou jamais touché à la main, ne change
pas. L'export et l'aperçu lisent la même géométrie (`ForkRecorderImagePlacement`). L'upstream garde
une image à l'intérieur des marges de l'image finale : elle ne grandit donc que jusqu'à les toucher.

La musique ajoutée au montage est un champ de plus du document de montage, `forkMusic` : le chemin
d'une copie du fichier rangée dans le dossier de la prise (supprimée avec elle), son nom, sa durée et
son volume. Elle est ajoutée à la timeline **après** que l'upstream l'a construite et mise à la
vitesse d'export : elle joue donc toujours à sa vitesse. Elle démarre avec la vidéo, est coupée à la
fin de la vidéo si elle est plus longue, s'arrête simplement si elle est plus courte, et se termine
par un fondu d'une seconde. Sa piste porte un identifiant fixe (`ForkRecorderMusic.trackID`) par
lequel le mixage la retrouve. Un montage sans musique s'enregistre et se relit comme avant.

Paroles à quelques secondes près : l'upstream n'accepte une fiche LRCLIB qu'à 2 s de la durée du morceau,
alors que Spotify annonce souvent une durée à quelques secondes de celle d'Apple Music, d'où viennent la
plupart des fiches (« MW2 » de Freeze Corleone : 282,9 s sur Spotify, 288 s pour les cinq fiches). Quand
la recherche stricte ne trouve rien dans une réponse, `ForkLyricsNearbyDuration` repasse sur la même
réponse avec 8 s de marge, en ne gardant que les fiches de l'album que nomme le lecteur ; titre, artistes et
type d'enregistrement restent vérifiés par l'upstream. Ces fiches perdent 1 000 points : une fiche stricte
l'emporte toujours. Aucune requête de plus. Lecteur sans album : pas de second passage.

File d'attente de Spotify : Spotify ne publie que son morceau en cours auprès de macOS (l'adaptateur répond
`queueAvailable: false`) et son dictionnaire AppleScript n'a pas de file. La seule source officielle est
l'API Web, `GET /me/player/queue`, avec une app créée par l'utilisateur sur developer.spotify.com (mode
développement : propriétaire Premium, 5 utilisateurs) et une connexion PKCE, sans secret. Le retour du
navigateur arrive sur `http://127.0.0.1:43821/callback`, écouté seulement entre « Connecter » et la réponse
(5 min au plus). Les jetons sont dans le trousseau (`<bundle id>.spotify-oauth`), jamais dans les préférences
ni la sauvegarde. Quand l'adaptateur répond sans file pour Spotify, `forkReadSpotifyQueue` fait lire la file
(`ForkSpotifyQueueBridge`) et remet à l'upstream une réponse au format de l'adaptateur, que
`NotchQueueSupport.decode` valide comme les autres ; les pochettes (64 px, i.scdn.co) suivent. Lecture
seule : l'API ne sait pas sauter à un morceau de la file. Requêtes seulement page File ouverte : à
l'ouverture, au changement de morceau, sur « Actualiser ». Réglage désactivé par défaut.

## Surface de conflit

Les seules lignes modifiées dans des fichiers de l'upstream :

| Fichier | Changement |
|---|---|
| `build.sh` | 7 lignes : `source Fork/build-hooks.zsh`, `fork_brand_sources`, le helper compilé depuis le miroir, `fork_brand_bundle_resources`, la condition qui donne une identité propre à toutes les variantes, `BRAND_DIR` pour l'icône adaptative, `fork_test_sources` |
| `Sources/Vorssaint/Services/Update/UpdateService.swift` | 5 fois `AppInfo.isDeveloperBuild` → `AppInfo.neverSelfUpdates` |
| `Tools/MakeIcon.swift` | 3 lignes : lecture de `BRAND_DIR` |
| `Sources/Vorssaint/main.swift` | 1 ligne : `ForkBootstrap.run()` |
| `Sources/Vorssaint/UI/Settings/SettingsView.swift` | 1 ligne : `ForkAttributionView()` |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift` | 1 ligne : `ForkCaptureExclusions.windowIDs(…)` |
| `Sources/Vorssaint/UI/Settings/ScreenCaptureSettings.swift` | 4 lignes : la page simplifiée en tête, la page d'origine derrière « Tous les réglages » |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift` | 3 lignes : `ForkCaptureSound.play()`, les fenêtres des cartes exclues des captures, le style de la fenêtre capturée (dans `receiveUnifiedCapture` : un test de l'upstream exige que `route` commence par `beginLatestCapture`) |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift` | 2 lignes : l'image modifiée repart en carte à la fermeture, et pas de question « abandonner les modifications ? » |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift` | 1 ligne modifiée : pas de bandeau d'aide sur les sélections lancées par le menu de capture ; 1 ligne ajoutée : la note « une fenêtre vient d'être cliquée » |
| `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift` | 2 lignes modifiées (`apply(_:window:)`) et une extension de 11 lignes en fin de fichier (`forkTarget`) |
| `Sources/Vorssaint/UI/Settings/WindowLayoutSettings.swift` | 1 ligne : `ForkTitleBarGestureSection()` |
| `Sources/Vorssaint/Services/Switcher/AppSwitcher.swift` | Une extension de 32 lignes en fin de fichier : ouvrir, avancer, valider et annuler une session sans clavier |
| `Sources/Vorssaint/UI/Settings/SwitcherSettings.swift` | 1 ligne : `ForkSwitcherGestureRow(…)` |
| `Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift` | 2 lignes : le bandeau du fork en tête de `toggleHistoryWindow` et de `showHistoryWindow` |
| `Sources/Vorssaint/UI/Settings/ClipboardSettings.swift` | 1 ligne : `ForkClipboardSettingsSection()` |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotScrollingCapture.swift` | 3 lignes modifiées : la première image, les suivantes et l'image assemblée passent par `ForkScrollingDirection` |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotPinController.swift` | 2 lignes : `ForkPinControls.install(…)` dans l'initialiseur de l'image épinglée |
| `Sources/Vorssaint/Services/Recorder/RecorderExporter.swift` | 5 lignes : le nombre de canaux du son exporté, lu puis écrit ; la musique comptée comme un son à exporter, ajoutée à la timeline, puis au mixage |
| `Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift` | 1 ligne modifiée : la valeur par défaut de l'anneau de clic |
| `Sources/Vorssaint/Services/Recorder/RecorderCaptureEngine.swift` | 1 ligne modifiée : le micro ouvert par l'enregistrement |
| `Sources/Vorssaint/Services/Recorder/RecorderImageOverlay.swift` | 2 lignes ajoutées (`forkCenter`, la position libre ; `forkTurn`, miroir et rotation) et 1 modifiée (la taille maximale) |
| `Sources/Vorssaint/Services/Recorder/RecorderComposer.swift` | 2 lignes modifiées : l'endroit où l'image est dessinée, puis son miroir et sa rotation ; 1 ligne ajoutée : une image tenue sur l'aperçu n'est pas dessinée dans la vidéo |
| `Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift` | 4 lignes : `ForkRecorderImageHandles(…)` sur l'aperçu, le bouton et la piste de la musique, la ligne « Amplifier » du micro |
| `Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift` | 4 lignes de plus pour la musique : le champ `forkMusic`, sa lecture, et sa prise en compte dans deux comparaisons ; 3 pour l'amplification du micro |
| `Sources/Vorssaint/Services/Recorder/RecorderComposition.swift` | 1 ligne : le tap d'amplification du micro |
| `Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift` | 5 lignes : l'aperçu reconstruit rend l'image tenue à la vidéo et se redessine ; les touches de l'enregistrement ajoutées en textes au premier chargement ; la musique ajoutée à ce que joue l'aperçu, et à son mixage (deux endroits) |
| `Sources/Vorssaint/UI/Recorder/RecorderInspector.swift` | 1 ligne modifiée : choisir l'une des neuf positions abandonne la position libre |
| `Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift` | 2 lignes : un commentaire et `ForkPreviewCards.present(…)` |
| `Sources/Vorssaint/Services/Notch/NotchLyricsService.swift` | 1 ligne ajoutée et 1 modifiée dans `search` : les paroles à quelques secondes près (`ForkLyricsNearbyDuration`), classées après toute fiche stricte |
| `Sources/Vorssaint/UI/Settings/NotchSettings.swift` | 2 lignes : `ForkLyricsSettingsRow()` sous « Paroles en ligne », `ForkSpotifyQueueSettingsRows()` sous la file d'attente |
| `Sources/Vorssaint/Services/Notch/NotchMusicService.swift` | 1 ligne dans `receiveQueue` (`forkReadSpotifyQueue`) et une extension de 15 lignes en fin de fichier, qui touche ses membres privés de file |
| `Sources/Vorssaint/UI/Notch/NotchQueueView.swift` | 1 ligne : `ForkSpotifyConnectButton(playback:)` dans la page vide |
| `Sources/Vorssaint/Core/Defaults.swift` | Le bloc du fork en tête de `registeredDefaults` : un commentaire, puis une ligne par préférence |
| `Tests/MetricsTests.swift` | 1 ligne : la suite `fork` |

`CLAUDE.md` est suivi par ajout forcé : le `.gitignore` de l'upstream l'ignore et n'est pas modifié.

`Fork/check.sh` vérifie que chacune de ces lignes est toujours là, une seule fois.

## Signature

Hublot est signé avec le certificat **Developer ID Application: ARTHUR CISSAC**, équipe
`8222G9B2DZ`. `build.sh` le choisit de lui-même ; il active le runtime durci et un horodatage
Apple, donc **chaque build demande le réseau**, et aucun débogueur ne peut s'attacher à l'app signée.

Pourquoi c'est important : macOS rattache les autorisations (Accessibilité, Enregistrement de
l'écran) à la signature. Tant que l'équipe et le bundle id ne changent pas, elles sont conservées
d'un build à l'autre.

- **Le certificat expire le 1er février 2027.** Le renouveler avant, dans la même équipe (compte
  Apple Developer actif requis), puis l'installer dans le trousseau. Rien à modifier dans le dépôt :
  les autorisations et la confiance du helper suivent l'équipe, pas le certificat.
- **Garde.** Sans Developer ID valide de cette équipe, `build.sh` s'arrête avant de compiler. Sans
  cette garde il basculerait sans rien dire sur une identité locale, puis sur une signature ad hoc :
  l'app installée changerait de signature, perdrait ses autorisations et serait refusée par son helper.
- **Échappatoire.** `FORK_ALLOW_LOCAL_SIGNING=1 ./build.sh --dev` autorise la signature locale pour
  un build Developer **non installé**, pour travailler sans le certificat. Elle ne couvre jamais
  `--install`. Les autorisations données à un build signé ainsi ne se reportent pas sur un build
  correctement signé.
- `./Fork/check.sh` prévient quand le certificat expire dans moins de 30 jours.
- Pas de notarisation : Hublot n'est pas distribué.

## Garder le fork à jour

```sh
git fetch upstream
git switch main
git rebase upstream/main        # rerere rejoue les résolutions de conflit déjà faites
./Fork/check.sh                 # les invariants du fork tiennent-ils toujours ?
./build.sh --dev                # build sans avertissement
./build/HublotDeveloper --selftest
./build.sh --test
```

Puis rebaser la branche de lot en cours sur `main`.

En cas de conflit, il porte presque toujours sur une des lignes de « Surface de conflit » : garder
la version de l'upstream et remettre l'appel du fork. `./Fork/check.sh` dit lequel manque.

Ce que `Fork/check.sh` détecte après un rebase :

- un nouveau chemin de mise à jour ajouté par l'upstream (garde `isDeveloperBuild` non convertie) ;
- un appel du fork perdu dans `build.sh`, `main.swift`, `SettingsView.swift` ou `MakeIcon.swift` ;
- une chaîne de l'upstream qui ferait renommer du code ;
- un déplacement du littéral d'équipe dont dépend le helper des ventilateurs ;
- un certificat absent, expiré ou proche de l'expiration.

Un rebase réécrit l'historique de `main` : le pousser demande `--force-with-lease`, et, comme tout
push, un accord explicite.

## GitHub

- **GitHub Actions est désactivé pour tout le dépôt** (Settings › Actions › General › « Disable
  actions »). Les trois workflows de l'upstream restent dans le dépôt sans être modifiés : `ci.yml`
  (casserait, il appelle `./build/Vorssaint`), `release.yml` et `issue-fix-status.yml` (un bot
  quotidien sans garde de dépôt). Il n'y a pas de CI : les tests tournent en local.
- `.github/README.md` est l'avis de fork affiché sur la page du dépôt, à la place du `README.md`
  de l'upstream, qui n'est pas modifié.
- `gh` vise ce dépôt par défaut (`gh repo set-default ArthurCissac/hublot`) : dans un fork, il
  viserait sinon l'upstream.

## Cohabitation avec le Vorssaint officiel

- Les deux apps peuvent être installées côte à côte. **Elles ne doivent pas tourner ensemble** :
  mêmes raccourcis globaux, mêmes interceptions d'événements, donc chaque action se déclencherait
  deux fois. Hublot affiche une alerte dans ce cas, au lancement et quand l'officiel s'ouvre ensuite.
- L'alerte ne concerne pas la variante Developer de Hublot, faite pour tourner à côté de la
  quotidienne. Pendant un test, désactiver dans l'une des deux les raccourcis qu'elles partagent.
- `./build.sh --install` installe dans `/Applications/Hublot.app` et n'arrête que le processus
  `Hublot`. Il ne touche jamais à `/Applications/Vorssaint.app`. Il supprime en revanche, s'ils
  existent, deux anciens bundles de l'upstream d'avant son renommage : `Vorss.app` et
  `Vorssaint Utils.app`.
- Deux éléments système sont partagés tant que l'officiel reste installé :
  `/etc/sudoers.d/vorssaint-clamshell` (veille capot fermé) et les verrous
  `/var/run/vorssaint-fan-control.*` (ventilateurs). Remettre les ventilateurs en automatique dans
  une app avant de les piloter depuis l'autre.
- `Tools/uninstall.sh` désinstalle l'app **officielle**, pas Hublot.

## Migration des réglages

Le script reprend les réglages du Vorssaint officiel avec la sauvegarde intégrée à l'app. Seules
les préférences voyagent : ni l'historique du presse-papiers, ni le bloc-notes.

1. Dans le Vorssaint officiel : ventilateurs en automatique, « Ouvrir à la connexion » décoché,
   puis quitter l'app.
2. `Fork/migrate-settings.sh export`
3. `./build.sh --install` (ne pas ouvrir Hublot)
4. `Fork/migrate-settings.sh import`
5. Ouvrir Hublot et redonner les autorisations macOS : nouvel identifiant, donc tout est à redonner.
6. `Fork/migrate-settings.sh clean`
7. Retirer le Vorssaint officiel des éléments de connexion (Réglages Système › Général › Ouverture)
   et ne plus le lancer.

L'export force trois préférences à « non » : l'ouverture à la connexion (sinon les deux apps
démarreraient ensemble) et les deux partages en ligne.

À régler de nouveau à la main dans Hublot, car la sauvegarde exclut l'état propre à la machine :
les dossiers d'enregistrement des captures et des vidéos, les dossiers de fonds d'écran.

## Icône

`Fork/Brand/` contient le logo monochrome, l'icône d'app et la source de l'icône adaptative.
Ils sont produits par `swift Fork/Tools/MakePlaceholderBrand.swift`, qui dessine un hublot à partir
d'une géométrie écrite dans le script : aucun élément graphique de Vorssaint n'est lu. L'icône est
provisoire ; pour la changer, modifier le script (ou remplacer les fichiers) puis rebuilder.

## Licence et marques

- `LICENSE` et tous les en-têtes SPDX et de copyright de l'upstream sont conservés.
- Les fichiers ajoutés par le fork sont sous GPL-3.0-or-later, avec leur propre copyright.
- L'app affiche le copyright de Vorssaint, indique qu'elle est un fork modifié et donne le lien
  vers ces sources.
- `TRADEMARKS.md` demande à un fork de changer de nom, d'icône, de bundle id, d'identité de
  signature, de flux de mise à jour et de tout ce qui suggérerait un lien officiel : c'est l'objet
  de ce qui précède.
- « Hublot » est aussi une marque horlogère : à revoir avant toute diffusion.

## Restes connus

- Les liens vers le site, le Discord et la page de dons pointent toujours vers Vorssaint, mais
  leurs libellés ont été renommés par la passe (`AppInfo.swift`).
- Les images et GIF de `Resources/` et le `CHANGELOG.md` embarqué sont ceux de l'upstream.
- Les boutons de feedback sont visibles et leur envoi échoue (voir plus haut).
- Les deux interrupteurs de partage en ligne restent visibles dans les Réglages.
- `Tools/make-dmg.sh` et `Tools/notarize.sh` supposent `Vorssaint.app` : inutilisables tels quels,
  et inutiles ici.
- Le certificat local « Vorssaint Utils Signing » créé par `Tools/setup-signing.sh` existe toujours
  dans le trousseau. Il ne sert qu'à l'échappatoire `FORK_ALLOW_LOCAL_SIGNING`.

## Commandes

```sh
./build.sh --dev                     # build de la variante Developer
./build.sh --dev --install           # build et installation de la variante Developer
./build/HublotDeveloper --selftest   # selftest
./build.sh --test                    # tous les tests
./build.sh --test-suite=NOM          # une suite (./build.sh --list-tests pour la liste)
./build.sh --test-suite=fork         # les tests propres au fork
./Fork/check.sh                      # invariants du fork
```
