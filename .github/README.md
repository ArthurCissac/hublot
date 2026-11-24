# Hublot

Utilitaire macOS tout-en-un : captures et enregistrement d'écran, historique du presse-papiers,
gestes de fenêtres au trackpad, une fenêtre Entretien (nettoyage, antivirus, maintenance, carte
du disque) et une Dynamic Island dans l'encoche, avec musique et paroles, Todoist, météo,
déploiements Vercel, bruit de fond et traduction. Fork non officiel de [Vorssaint](https://github.com/vorssaint/vorssaint-utils),
sous licence GPL-3.0-or-later.

> **Ce n'est pas Vorssaint.** Hublot n'est ni publié, ni soutenu, ni approuvé par l'auteur de
> Vorssaint. Pour l'app d'origine, ses versions et sa documentation, voir le
> [projet d'origine](https://github.com/vorssaint/vorssaint-utils).

## Télécharger

1. Prenez le fichier `Hublot-….dmg` de la dernière version dans
   [Releases](https://github.com/ArthurCissac/hublot/releases).
2. Ouvrez-le et glissez **Hublot** dans **Applications**.
3. Au premier lancement, macOS demande les autorisations utiles (Accessibilité, Enregistrement de
   l'écran…) selon les fonctions que vous activez.

Requis : macOS 14 ou plus récent, Mac avec puce Apple. L'app est signée et notarisée par Apple.

Depuis la version 0.2, Hublot se met à jour tout seul : il vérifie chaque jour s'il existe une
nouvelle version, montre ce qui change, vérifie sa signature puis l'installe. Si vous avez la 0.1,
installez la dernière version une fois à la main.

## Vie privée

Aucune mesure d'audience, aucun compte Hublot. Les intégrations facultatives ne contactent que le
service concerné, uniquement quand vous les activez : Todoist, Vercel et la file d'attente de
Spotify avec votre propre accès, rangé dans le trousseau du Mac ; la météo (Open-Meteo), les
paroles (LRCLIB), les taux de change (BCE) et les signatures de l'antivirus (ClamAV), sans compte.
La traduction et le bruit de fond fonctionnent sur le Mac, sans réseau.

## Code source

Tout ce qui est propre au fork vit dans [`Fork/`](../Fork) et
[`Sources/Vorssaint/Fork/`](../Sources/Vorssaint/Fork). [`FORK.md`](../FORK.md) explique le
fonctionnement du fork. Le [`README.md`](../README.md) d'origine est conservé tel quel et décrit
l'app d'origine.

---

# Hublot (English)

An all-in-one macOS utility: screenshots and screen recording, clipboard history, trackpad window
gestures, a Care window (cleaning, antivirus, maintenance, disk map) and a Dynamic Island in the
notch with music and lyrics, Todoist, weather, Vercel deployments, background sounds and
translation. An
unofficial fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils), under the
GPL-3.0-or-later license.

> **This is not Vorssaint.** Hublot is not published, supported or endorsed by Vorssaint's
> author. For the original app, its releases and its documentation, see the
> [original project](https://github.com/vorssaint/vorssaint-utils).

**Download:** take `Hublot-….dmg` from the latest [release](https://github.com/ArthurCissac/hublot/releases),
open it and drag **Hublot** to **Applications**. macOS 14 or later, Apple silicon. Signed and
notarized. Since version 0.2, Hublot updates itself: it checks daily for a new version, shows what
changed, verifies its signature and installs it. If you have 0.1, install the latest version once by
hand.

**Privacy:** no analytics, no Hublot account. Optional integrations only reach their own service,
only while turned on: Todoist, Vercel and the Spotify queue with your own access, kept in the Mac's
Keychain; weather (Open-Meteo), lyrics (LRCLIB), exchange rates (ECB) and antivirus signatures
(ClamAV) without an account. Translation and background sounds work on the Mac, offline.
