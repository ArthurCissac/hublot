# Changelog

Les changements notables de Hublot, fork non officiel de Vorssaint. Le format suit
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) et les versions suivent
[Semantic Versioning](https://semver.org/). Chaque version publiée a sa section ici :
l'app l'affiche dans « Nouveautés » et dans les notes de version, et la page GitHub de
la version reprend le même texte.

## [0.3.0] - 2026-11-24

### Summary
Une fenêtre Entretien qui réunit le nettoyage, l'antivirus, la maintenance, les applications et la carte du disque, avec un fond animé par outil. L'île gagne Todoist, la météo, les déploiements Vercel, le bruit de fond et la traduction de la sélection.

### Added
- Entretien : une seule fenêtre avec une barre latérale (Analyse en un clic, Nettoyage, Protection, Performance, Applications, Carte du disque). On passe d'un outil à l'autre en un clic ou avec ⌘1 à ⌘6, et une analyse en cours continue. Chaque outil a son fond animé, plus vif pendant le travail.
- Analyse en un clic : nettoyage, protection et maintenance en une seule analyse, rien n'est supprimé avant votre accord. Analyse planifiée chaque semaine, résultats dans l'île.
- Protection : antivirus ClamAV, installé par Homebrew après confirmation, signatures vérifiées chaque jour, nouveaux téléchargements analysés, quarantaine.
- Performance : vider le cache DNS, réparer « Ouvrir avec », libérer la mémoire, réindexer Spotlight.
- Carte du disque : ce qui prend de la place en rectangles proportionnels, à ouvrir, afficher dans le Finder ou mettre à la corbeille.
- Todoist dans l'île et dans un panneau (⌃⌥N) : tâches du jour et en retard, ajout rapide, coche animée, modification, tâche en cours et rappel à l'heure.
- Météo dans l'île : votre ville et jusqu'à six autres, avec Open-Meteo, raccourci ⌃⌥W.
- Déploiements Vercel dans l'île : build en cours, en ligne ou en échec.
- Bruit de fond : pluie, océan, feu, forêt, sons binauraux, musique douce, mélanges, minuteur et Pomodoro, scènes animées dans l'île. Tout est créé par Hublot, sans réseau.
- Traduction de la sélection (⌃⌥⌘T) : le traducteur de macOS, sur le Mac, du français vers l'anglais et des autres langues vers le français.
- Compagnon de l'île : activités au repos, accessoires selon l'heure et la saison, autres styles (chat, fantôme, pixel, blob), petites bulles et météo.
- Mission Control : un × au survol d'une fenêtre, ⌘W, ⌘H et ⌘Q sur la fenêtre survolée, pincer pour quitter son app.
- Capture défilante guidée par le pointeur, avec aperçu en direct ; rognage simplifié dans l'éditeur, avec proportions.
- Touches de volume et de luminosité par pas ronds de 5 % quand l'île affiche le niveau.
- Menu de la barre des menus simplifié, actions rapides en tuiles à ranger soi-même, apps gourmandes à quitter en un clic.
- QR code d'un serveur de développement local, pour l'ouvrir sur un téléphone ; devises dans la barre de commande (taux de la BCE).
- Écran rabattu : les écrans externes se mettent aussi en veille.

### Changed
- Les paroles d'une version un peu plus longue ou plus courte restent synchronisées.
- La section des gestes de fenêtre s'appelle « Gestes sur la barre de titre ».

### Fixed
- ⇧⌘3 et ⇧⌘4 capturent tout de suite : le minuteur du menu ⇧⌘5 ne vaut plus que pour la capture lancée depuis ce menu.
- Deux raccourcis qui partageaient le même identifiant ne se déclenchent plus l'un l'autre.

## [0.2.0] - 2026-11-23

### Summary
Hublot se met désormais à jour tout seul, depuis ses versions publiées sur GitHub. Si vous avez Hublot 0.1, installez cette version une fois à la main : les suivantes arriveront dans l'app.

### Added
- Mises à jour dans l'app : Hublot vérifie chaque jour s'il existe une nouvelle version, montre ce qui change, puis la télécharge, l'installe et se relance. Pour vérifier tout de suite : « Rechercher les mises à jour… » dans le menu de Hublot, ou « Rechercher maintenant » dans la section Mises à jour des réglages.
- Avant d'installer, Hublot vérifie que la nouvelle version est signée par son développeur et validée par Apple.
- Les versions bêta ne sont proposées qu'aux personnes qui cochent « Recevoir les mises à jour bêta ».

### Changed
- À propos indique la version de Hublot et la version de Vorssaint sur laquelle elle repose.
- Les notes de version de l'app montrent désormais les changements de Hublot.

## [0.1.0] - 2026-11-23

### Summary
Première version téléchargeable de Hublot, basée sur Vorssaint 3.4.4.

### Added
- Captures : icônes du bureau masquées pendant la capture, capture de fenêtre avec ombre ou fond, zone de capture déplaçable et redimensionnable, capture défilante, y compris de côté.
- Aperçu après capture en cartes, avec raccourcis et glisser-déposer.
- Presse-papiers : bandeau de grandes cartes et tableaux nommés.
- Fenêtres au trackpad : gestes sur la barre de titre (moitiés, quarts, agrandir, réduire, écran voisin), pincer pour fermer.
- Enregistrement vidéo : son du Mac et micro, caméra, touches affichées, musique et image au montage.
- Dynamic Island : paroles et file d'attente de Spotify.
