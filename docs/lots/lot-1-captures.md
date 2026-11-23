# Lot 1 : CleanShot, petits gains sur les captures

Plan court et questions, rédigés le 21/11/2026. Plan validé le même jour : les cinq
recommandations sont retenues (voir « Décisions »). L'avancement est suivi dans
`docs/HUBLOT-PLAN.md`.

Chemins relatifs à `Sources/Vorssaint/`.

## Décisions (21/11/2026)

1. Icônes : retirées **de l'image seulement**, l'écran n'est pas modifié.
2. Fenêtre : ombre ou fond intégrés dès la capture, avec une ombre dessinée.
3. Ratios : libre, 1:1, 4:3, 3:2, 16:9. Tailles fixes : 1280 × 720, 1920 × 1080 et une taille
   personnalisée. Touche A pour changer de ratio.
4. Défilante horizontale : dans ce lot, en dernier.
5. Textes : français et anglais seulement, dans le catalogue du fork. Règle adaptée dans `CLAUDE.md`.

Resté sans réponse : la présence de widgets sur le bureau.

### Écarts par rapport au plan, constatés en codant 1a

- **Préférences** : un seul bloc dans `Core/Defaults.swift` (les valeurs par défaut) au lieu de
  deux. Les clés sont déclarées dans un fichier du fork, et aucune ligne n'est nécessaire dans
  `SettingsBackupSupport` : la sauvegarde reprend d'elle-même toute préférence enregistrée.
- **Tests** : deux raccords non prévus, d'une ligne chacun. `build.sh` ajoute les sources du fork
  à la liste compilée par les tests, et `Tests/MetricsTests.swift` déclare la suite `fork`.
  Ils servent à tous les lots suivants.
- **Watch** : cette fonction de l'île lit l'écran par le même chemin que les captures. Elle garde
  les icônes, sinon elle ne verrait plus un fichier arriver sur le bureau.

## Hypothèses prises (à contredire si besoin)

- L'éditeur d'annotation n'est pas modifié.
- Chaque nouveauté a son interrupteur, réglé par défaut comme dans ton CleanShot.
- Les icônes masquées pendant un **enregistrement vidéo** passent au lot 7 : le filtre de
  l'enregistreur est construit une fois au démarrage et demande une autre technique.
- Branche `lot-1-captures`, un commit par sous-lot, dans l'ordre 1a, 1b, 1c, 1d.

## Ce que Vorssaint fait déjà

| Besoin | État | Où |
|---|---|---|
| Masquer icônes et widgets pendant la capture | Non. Seul existe un interrupteur manuel qui redémarre le Finder | `Services/QuickTools/QuickTogglesService.swift:236-240` |
| Fenêtre : ombre, fond | Partiel. Le fond existe, mais dans l'éditeur seulement | `Services/QuickTools/ScreenshotService.swift:977-990` |
| Tout-en-un : ratio, taille fixe, mémoire | Partiel. Carré avec Maj, dernière zone gardée en mémoire vive | `Services/QuickTools/ScreenshotSelectionController.swift:150` |
| Défilante horizontale | Partiel. Verticale seulement | `Services/QuickTools/ScreenshotScrollingCapture.swift` |

## Ce que l'étude a appris

1. **Toutes les captures d'image passent par un même filtre.** Une seule fonction dresse la liste
   des fenêtres à exclure de l'image (`ScreenshotCaptureEngine.swift:129-149`), pour le plein
   écran, la zone, l'image figée du sélecteur et la défilante. Les fenêtres du bureau font
   partie de ce que le système propose, donc on peut les **retirer de l'image sans rien changer
   à l'écran**.
2. **La fenêtre des icônes est identifiable** : elle appartient au Finder, au niveau « icônes du
   bureau » (sonde du 21/11 sur ce Mac).
3. **Aucun widget n'était affiché** pendant la sonde : leur propriétaire reste inconnu.
4. **Une app tierce affiche une fenêtre plein écran au-dessus du fond d'écran.** Recouvrir le bureau avec
   le fond d'écran du système masquerait ce que tu vois vraiment. C'est un argument de plus
   contre la technique de la fenêtre de recouvrement.
5. **En mode figé, l'écran est photographié dès l'ouverture du sélecteur**
   (`ScreenshotSelectionController.swift:236-239`). Toute technique qui modifie l'écran devrait
   donc agir avant, et ajouterait un délai au déclenchement.
6. **Une capture ne sait pas d'où elle vient** (zone, fenêtre, plein écran). Il faut l'ajouter
   pour n'appliquer un fond qu'aux fenêtres (`ScreenshotSelectionController.swift:19-26`).
7. **Le calcul de la sélection est une fonction pure et testée**
   (`ScreenshotSupport.swift:904-922`) : y ajouter un ratio est simple.
8. **La défilante horizontale est une généralisation, pas une réécriture.** Le moteur de
   correspondance (environ 450 lignes testées) peut rester intact si on lui présente les images
   tournées d'un quart de tour.

## Plan

### 1a. Icônes du bureau hors de l'image

- **Technique** : ajouter la fenêtre des icônes du Finder à la liste des fenêtres exclues.
  L'image montre le bureau sans icônes ; l'écran, lui, ne change pas.
- **Avantages** : instantané, aucun clignotement, rien à restaurer après une annulation ou un
  plantage, et ce qui est derrière les icônes (cette fenêtre tierce comprise) est conservé tel quel.
- **Code** : un nouveau fichier du fork avec la règle de décision, pure et testée, et un appel
  d'une à deux lignes dans `ScreenshotCaptureEngine.swift:129-149`.
- **Réglage** : « Capturer sans les icônes du bureau », activé.
- **Limite** : l'image figée du sélecteur n'affiche plus les icônes non plus, puisque c'est la
  même image. Les captures de fenêtre ne sont pas concernées : le bureau n'y figure pas.
- **Widgets** : même technique dès que leur fenêtre est identifiée. Il faut un widget posé sur
  le bureau pour relancer la sonde.

### 1b. Capture de fenêtre : ombre et fond

- **Origine de la capture** : un champ de plus sur la capture, renseigné « fenêtre » au clic sur
  une fenêtre (`ScreenshotSelectionController.swift:741-746`).
- **Trois rendus** au choix : brut (aujourd'hui), ombre sur fond transparent, ou fond (marge,
  couleur, dégradé, image) repris des préréglages existants de l'éditeur.
- **Où** : juste après la capture, avant l'aperçu, la copie et l'enregistrement, pour que tous
  montrent la même image. Un appel d'une ligne dans `ScreenshotService.swift`, le reste dans un
  nouveau fichier.
- **Rendu** : par le moteur existant (`ScreenshotRenderer.swift:946-996`). Le choix du
  remplissage n'existe aujourd'hui que dans l'éditeur (`ScreenshotEditorController.swift:320-339`) :
  il sera recopié dans le fichier du fork plutôt que d'ouvrir l'éditeur.
- **Ombre** : dessinée au rendu, pas captée auprès du système. La capture de fenêtre actuelle
  recadre sur le cadre de la fenêtre et n'emporte aucune ombre.
- **Réglages** : le rendu choisi, et le préréglage de fond à utiliser.

### 1c. Sélection : ratio, taille fixe, zone mémorisée

- **Ratio** : la fonction de sélection reçoit un ratio facultatif, dont le carré de Maj devient
  un cas particulier. Tests ajoutés à côté des existants (`Tests/ScreenshotFeatureTests.swift:677-690`).
- **Taille fixe** : un clic pose un cadre de la taille choisie, un glisser le déplace.
- **Mémoire** : la dernière zone est écrite dans les préférences avec l'identité de l'écran et sa
  taille, relue au lancement, et ignorée si l'écran a changé. La clé est exclue de la sauvegarde
  des réglages, comme tout état propre à la machine.
- **Interface** : un sélecteur de ratio dans la barre d'aide du mode tout-en-un, sur le modèle
  des interrupteurs audio qui y figurent déjà
  (`ScreenshotSelectionController.swift:2223-2249`), et une touche pour faire défiler les ratios.
  La touche A est libre.
- **À étudier pendant le code** : quand les contrôles sont affichés dans l'île, ils sont rendus
  ailleurs. La première version peut s'y limiter à la touche et à l'affichage du ratio.

### 1d. Capture défilante horizontale

- **Technique** : tourner les images d'un quart de tour avant l'assemblage, puis tourner le
  résultat dans l'autre sens. Le moteur de correspondance n'est pas touché.
- **Code** : environ six points dans `ScreenshotScrollingCapture.swift`, et le défilement
  automatique, qui n'émet aujourd'hui que du défilement vertical
  (`ScreenshotAutomaticScroller.swift:53-68`).
- **Choix de l'axe** : à définir. Une touche, ou une détection au premier mouvement.
- **Tests** : la suite existante exécute la vraie boucle sur des pages fictives ; on y ajoute des
  pages horizontales.

### Transversal

- **Préférences** : regroupées en deux blocs repérés dans `Core/Defaults.swift`, plutôt que
  dispersées, pour limiter les conflits de rebase.
- **Réglages** : une section du fork insérée par une ligne dans
  `UI/Settings/ScreenshotSettings.swift`, le contenu dans un nouveau fichier.
- **Contrôles** : chaque appel ajouté dans un fichier de l'upstream est vérifié par `Fork/check.sh`.
- **Tests** : suites `screenshots`, `capture`, `settings` ; build sans avertissement ; selftest.
- **Fichiers de l'upstream touchés**, estimation : `ScreenshotCaptureEngine` (2 lignes),
  `ScreenshotSelectionController` (une dizaine), `ScreenshotService` (2), `ScreenshotSettings` (1),
  `Defaults` (2 blocs), `SettingsBackupSupport` (1), et pour 1d `ScreenshotScrollingCapture` et
  `ScreenshotAutomaticScroller` (une dizaine).

## Questions

Réponds par exemple : « 1 ok, 2 ok, 3 B, 4 ok, 5 ok ».

1. **Icônes : les retirer de l'image seulement, ou les faire disparaître aussi à l'écran ?**
   Recommandation : **de l'image seulement** (instantané, sans risque, fidèle à ce que tu vois).
   Option B : les masquer aussi à l'écran comme CleanShot, avec une fenêtre de recouvrement, un
   délai au déclenchement et plus de cas à gérer. Dis-moi aussi si tu as des widgets sur le bureau.

2. **Fenêtre : intégrer le fond ou l'ombre à l'image dès la capture ?**
   Recommandation : **oui**, avec une ombre dessinée. L'aperçu, la copie et le fichier sont alors
   identiques ; l'éditeur reçoit l'image déjà composée.
   Option B : ne l'appliquer qu'à l'export, l'aperçu montrant la fenêtre brute.

3. **Quels ratios et quelles tailles fixes ?**
   Recommandation : **libre, 1:1, 4:3, 3:2, 16:9**, et les tailles **1280 × 720** et
   **1920 × 1080**, plus une taille personnalisée ; touche A pour changer de ratio.
   Donne-moi ta liste si elle diffère.

4. **Défilante horizontale : la faire dans ce lot ?**
   Recommandation : **oui, en dernier** (1d), une fois le reste validé. Tu as fait 194 captures
   défilantes en 2026, mais rien ne dit combien étaient horizontales.
   Option B : la repousser après le lot 2.

5. **Textes des nouveautés : français et anglais seulement ?**
   Recommandation : **oui**, dans un catalogue propre au fork, comme pour la phase 0. Les autres
   langues afficheraient l'anglais. `CLAUDE.md` demande aujourd'hui les 15 langues de l'app, ce
   qui obligerait à modifier à chaque ajout les catalogues de l'upstream, source de conflits à
   chaque rebase. Si tu es d'accord, j'adapterai cette règle dans `CLAUDE.md`.
   Option B : les 15 langues, dans les catalogues de l'upstream.

## Ce qu'il me faut avant de coder

Les captures de CleanShot listées dans [../reference/cleanshot-x.md](../reference/cleanshot-x.md),
en priorité :

- le sélecteur ⇧⌘4 juste après son ouverture, bureau visible ;
- une capture de fenêtre avec ton réglage actuel ;
- le mode tout-en-un avec sa barre et son menu de taille et de ratio ;
- une capture défilante horizontale en cours, si tu t'en sers.

## Tests manuels prévus en fin de lot

1. Plein écran et zone, avec des icônes sur le bureau : aucune icône dans l'image, le bureau
   inchangé à l'écran, l'arrière-plan réel visible dans l'image.
2. Les mêmes sur le second écran, puis dans un autre Space.
3. Annulation par Échap à chaque étape : rien ne change à l'écran.
4. Capture de fenêtre dans les trois rendus, sur une fenêtre claire et une sombre, puis sur une
   fenêtre de Chrome et d'une app Electron.
5. Chaque ratio, puis chaque taille fixe, près d'un bord d'écran.
6. Zone mémorisée : retrouvée après avoir quitté et relancé Hublot ; ignorée après avoir
   débranché l'écran externe.
7. Défilante horizontale sur un tableur et sur une page web large, à la main puis en automatique.
8. Réglages désactivés un par un : le comportement de Vorssaint revient à l'identique.

## Non vérifié

- L'identité des fenêtres de widgets, faute de widget à l'écran pendant la sonde.
- Le rendu exact de l'ombre et du fond de CleanShot : il faut tes captures.
- La stabilité de l'identité d'un écran externe d'un branchement à l'autre.
- Rien n'a été compilé ni exécuté pour ce plan, hormis la sonde des fenêtres du bureau.
