# Tickets upstream sur les gestes trackpad

Résumé des tickets #967, #579, #864 et #3598 de `vorssaint/vorssaint-utils`, lus en entier le
21/11/2026 (corps et tous les commentaires). Ils servent aux lots 4 et 5 de `HUBLOT-PLAN.md`.

Deux précautions de lecture :

- Le propriétaire du dépôt n'a écrit dans aucun de ces fils. Le tri est fait par un
  contributeur, appelé ici « le trieur ». **Rien n'y est décidé ni promis.**
- Le ticket #967 le dit lui-même : rien n'a été exécuté ni mesuré sur du matériel. Tout ce qui
  suit est une piste, pas un résultat.

## Vue d'ensemble

| Ticket | Sujet | État |
|---|---|---|
| #967 | Gestes trackpad et Magic Mouse personnalisés (ticket chapeau) | Ouvert, priorité basse |
| #579 | Mosaïque par gestes sur la barre de titre, façon Swish | Fermé comme doublon de #967 |
| #864 | Balayage à trois doigts pour changer de fenêtre | Fermé, renvoyé vers #967, non implémenté |
| #3598 | Navigation au trackpad dans le sélecteur de fenêtres | Ouvert, sans réponse |

#967 regroupe quatre demandes (gestes multi-doigts, mosaïque façon Swish, Magic Mouse, clic
forcé) et chiffre leur coût. Une proposition de code existe côté upstream (PR #3017), ouverte et
non fusionnée.

## Lot 4 : ce que dit #967 sur la mosaïque par balayage (#579)

C'est la demande que le trieur juge la moins coûteuse.

1. **Pas besoin de lire les doigts.** Un balayage à deux doigts arrive comme un événement de
   défilement ordinaire, marqué « continu », avec des phases qui indiquent le début et la fin
   du geste.
2. **Au début du geste**, tester ce qui se trouve sous le pointeur pour savoir si c'est une
   barre de titre.
3. **Cumuler les déplacements**, et passé un seuil, transmettre le vecteur à la logique de
   direction existante, puis à l'action de disposition existante.
4. **Seul code nouveau** : le test « barre de titre » et l'accumulateur.
5. **Risque nommé** : le test par l'accessibilité est trop lent pour tourner sur le fil de
   l'event tap. Les premiers événements partent donc vers l'app, et le contenu défile un peu
   avant que la fenêtre ne bouge. **Aucune parade n'est proposée.**

Les briques citées existent dans le fork :

| Brique | Emplacement actuel | Remarque |
|---|---|---|
| Du pointeur à la fenêtre | `Services/WindowMaximizer.swift:276-330` (`elementAt`, `topLevelWindow`) | `private` : à extraire |
| Direction en 8 secteurs de 45° | `Services/WindowLayout/WindowGestureSupport.swift:281-345` | Les diagonales donnent les quarts |
| Actions de disposition | `Services/WindowLayout/WindowLayoutSupport.swift:28-38` | Agissent sur la fenêtre active, pas sur celle sous le pointeur |
| Molette ou trackpad ? | `Services/ScrollWheelSupport.swift:353` (`isMouseWheel`) | Pour exclure la molette |
| Test rapide sans accessibilité | `Services/WindowServerTrafficLightHitTest.swift` | Piste pour le risque n° 5 |

**Absent des tickets**, donc à concevoir : la valeur du seuil, la fermeture par pincement,
l'envoi vers l'écran voisin, la réduction (qui n'est pas une action de disposition), et la
parade au défilement qui fuit.

## Lot 5 : ce que dit #967 sur la lecture des doigts

Deux voies sont décrites.

- **Voie A, publique.** Un event tap sur les événements « gesture », convertis en `NSEvent`,
  dont on lit les touchers (`NSTouch` : un par doigt, avec phase, identité et position
  normalisée). Ces événements arrivent tant qu'un doigt touche le pavé.
- **Voie B, privée.** Le framework MultitouchSupport, déjà chargé par Vorssaint pour le clic du
  milieu à trois doigts (`Services/MiddleClick/MiddleClickService.swift:652-758`). Il donne plus
  d'informations mais oblige à supposer la disposition d'une structure interne.

Pour changer de fenêtre, le ticket propose la voie A : un seul détecteur (nombre de doigts,
direction, distance) branché sur le sélecteur existant.

### Les quatre leçons tirées d'AltTab

1. Un tap **actif** sur les événements du pavé bloque le pointeur. D'où le montage : un tap en
   **écoute seule** détecte, et un second tap, actif, n'est activé que lorsque assez de doigts
   sont posés.
2. La conversion en `NSEvent` doit se faire sur le fil principal.
3. La lecture de la position normalisée peut lever une exception (cas d'Universal Control) : il
   faut un petit pont Objective-C pour l'attraper.
4. Pas de rejet de paume possible : le mieux est d'ignorer les touchers immobiles.

### Limites à prévoir

- **On ne bat pas le système.** Avaler un événement n'empêche pas macOS de déclencher son
  propre geste (Mission Control, App Exposé, Launchpad). Un geste déjà pris par macOS doit être
  libéré dans Réglages Système, et l'app doit le dire.
- Deux taps de plus sur le flux du pointeur.
- La liste des appareils multitouch contient aussi la Magic Mouse.

### Ce que demandent #864 et #3598

- #864 : un balayage à trois doigts pour passer d'une fenêtre à l'autre, comme sous Windows.
- #3598 : aller plus loin que l'émulation de ⌘Tab. Trois doigts à gauche ou à droite pour
  l'élément précédent ou suivant, haut ou bas pour changer de rangée, et **relâcher pour
  valider**. Un commentaire précise le comportement attendu : on poursuit le balayage jusqu'à
  la fenêtre voulue, puis on lève les doigts.

Cela suppose un suivi continu du geste, pas un jugement unique au lever des doigts.

## Ce que ça change pour nos lots

**Lot 4**

- La piste du défilement continu est confirmée, et les diagonales de la logique de direction
  existante couvrent les quarts d'écran, le geste le plus utilisé dans Swish
  (voir [reference/swish.md](reference/swish.md)).
- Le pincement n'est pas un événement de défilement : fermer une fenêtre par pincement demande
  de lire les doigts. Une partie du coût du lot 5 se retrouve donc dans le lot 4, sauf à
  choisir un autre geste de fermeture.
- La parade au défilement qui fuit est à inventer, puis à valider sur le Mac. Deux pistes :
  le test rapide sans accessibilité, et un test fait hors du fil du tap.

**Lot 5**

- Voie A, avec le montage « écoute seule, puis tap actif pendant le geste ».
- Vérifier d'abord quels gestes à trois doigts macOS utilise déjà sur ce Mac.
- Prévoir le pont Objective-C : c'est du code d'un autre langage dans un projet construit à la
  main par `build.sh`, donc un point d'intégration à étudier.

## Précision sur une règle de `CLAUDE.md`

La règle « détection en écoute seule, tap actif seulement pendant un geste, réactiver le tap
après `tapDisabledByTimeout` » y est attribuée au ticket #967. Elle rassemble en fait deux
passages distincts : la leçon n° 1 d'AltTab, et la convention déjà suivie par les event taps de
Vorssaint. La règle reste juste.

## Non vérifié

- Les chemins cités dans les tickets datent d'une version antérieure ; ceux du tableau
  ci-dessus viennent de l'exploration du fork, pas des tickets.
- Le contenu de la PR #3017 n'a pas été lu.
- Le ticket dont #3598 a été marqué doublon n'est pas indiqué par GitHub.
