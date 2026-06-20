# AuditViewer — Application macOS

> **Nouveau ici ?** Ceci est l'**application Mac native** d'AuditViewer : la façon la plus confortable de **lire, comparer et explorer vos audits**, avec un rendu soigné et une carte des liens entre vos dossiers. Si vous découvrez le projet, commencez par la **[documentation générale](../docs/README.md)** ([🇬🇧 README](../README.md) · [🇫🇷 README](../README.fr.md)) : elle explique ce qu'est un audit et comment en produire un.
>
> La suite de ce document s'adresse à ceux qui veulent **compiler l'app depuis les sources**.

---

## ⬇️ Télécharger

[![Télécharger pour macOS](https://img.shields.io/badge/Télécharger-macOS%2015%2B-blue?logo=apple&style=for-the-badge)](https://github.com/vincentlauriat/AuditViewer/releases/latest)

1. Téléchargez le `.dmg` depuis la **[dernière release](https://github.com/vincentlauriat/AuditViewer/releases/latest)**.
2. Ouvrez-le et glissez **AuditViewer** dans **Applications**.
3. Lancez l'app. Elle est **signée et notarisée par Apple** — aucun avertissement Gatekeeper.

L'app se **met à jour automatiquement** (Sparkle) : les nouvelles versions sont proposées au lancement, ou via **AuditViewer ▸ Rechercher les mises à jour…**.

> Prérequis pour lancer des audits depuis l'app : le CLI `claude` (voir [Prérequis](#prérequis)).

---

Application macOS (SwiftUI) pour consulter, comparer et explorer les dossiers d'audit
produits par le skill Claude Code **`audit-report`**.

Elle lit un dossier `audit-{sujet}/` contenant des sections markdown et des métadonnées,
affiche chaque section avec un rendu markdown riche (code, math, mermaid), et propose une
**carte des liens façon Obsidian** entre les sections et entre les audits.

---

## Fonctionnalités

- **Lecture des rapports** — sidebar des sections (`00_RESUME_EXECUTIF.md` → `RAPPORT_COMPLET.md`),
  rendu markdown dans un `WKWebView` (markdown-it + highlight.js + KaTeX + Mermaid).
- **Output complet du skill** — entrées dédiées pour :
  - **Reconnaissance** (`_recon.json`) — secteur, acteurs clés, mots-clés, sources consultées
  - **Vérification des faits** (`_factcheck.md`)
  - **Chiffres-clés** (`_data.json`, rendu en markdown)
  - **Sources** — index agrégé de toutes les URLs citées, groupées par domaine
- **Carte canvas (Obsidian-like)** — graphe force-directed interactif (pan / zoom / drag) :
  - **Audit courant** : sujet → sections → reliées par sources partagées et acteurs clés communs
  - **Global** : tous les audits du dossier `Research`, reliés par leurs sources/acteurs partagés
- **Lancer / mettre à jour un audit** depuis l'app (exécute `claude -p "/audit-report …"`),
  avec console temps réel et suivi d'événements (`_events.jsonl`).
- **Diff** entre deux versions d'un même audit après mise à jour.
- **Export Word** (`.docx`) de la section courante via `pandoc`.
- Recherche dans le document, zoom, thème clair/sombre suivant le système.

---

## Prérequis

- macOS 14+ (cible SwiftPM : macOS 15)
- Swift 6 / Xcode toolchain
- `claude` CLI (pour lancer des audits depuis l'app) — détecté dans `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`
- `pandoc` (pour l'export `.docx`) — optionnel
- Le projet voisin **`MarkdownViewer`** doit être présent à côté pour fournir le bundle de rendu web
  (voir [ARCHITECTURE.md](ARCHITECTURE.md))

## Build

```bash
./build.sh
open build/AuditViewer.app
```

`build.sh` compile en release, assemble le `.app`, puis copie les ressources web :
- `../MarkdownViewer/MarkdownViewer/Resources/web` → rendu markdown
- `Sources/WebGraph` → carte des liens

Pour installer : `cp -r build/AuditViewer.app /Applications/`

> `swift build` seul compile le binaire mais **ne bundle pas** les ressources web :
> utiliser `./build.sh` pour une app fonctionnelle.

## Utilisation

1. **⌘O** : ouvrir un dossier `audit-…` (par défaut sous `~/Documents/Research/`).
2. Naviguer dans les sections via la sidebar.
3. Basculer **Document / Carte** dans la barre d'outils ; en mode Carte, choisir
   **Audit courant** ou **Global**.
4. **⌘N** : lancer un nouvel audit ; **↻** (toolbar) : mettre à jour l'audit ouvert.

Raccourcis : `⌘F` recherche · `⌘G` / `⇧⌘G` suivant/précédent · `⌘±` / `⌘0` zoom.

---

## App iOS / iPadOS (lecture seule)

La cible **`AuditViewerIOS`** (`ios/Sources/`) est un **lecteur natif** pour iPhone et iPad,
construit depuis le même dépôt. Périmètre lecture seule : liste des audits + 4 onglets
(Synthèse/KPIs, Dimensions, Sources, Rapport Markdown). Pas de lancement d'audit, pas de
carte des liens — ces fonctions restent sur Mac/Web.

**Accès aux fichiers** : l'app ouvre le dossier `Research` existant via le sélecteur
**Fichiers** (`UIDocumentPicker`, `UTType.folder`) et mémorise un **security-scoped
bookmark** (`ResearchFolderBookmark`) — iCloud Drive ou « Sur mon iPhone ». Repli :
`Documents/Research` du bac à sable, exposé dans Fichiers (`UIFileSharingEnabled` +
`LSSupportsOpeningDocumentsInPlace` + iCloud Documents). Les fichiers iCloud sont
téléchargés à la demande via `NSFileCoordinator` + `startDownloadingUbiquitousItem`.

**Build** (iOS 17+, nécessite Xcode complet) — via le script `ios/build.sh` :

```bash
ios/build.sh                 # build simulateur (vérification de compilation)
ios/build.sh <device-udid>   # build signé + install + lancement sur l'appareil
                             # UDID via : xcrun devicectl list devices
```

> ⚠️ **Builder hors iCloud.** Le dépôt vit sous `~/Documents` (synchronisé iCloud) : macOS
> stampe l'attribut étendu `com.apple.provenance` sur les produits de build, et `codesign`
> le refuse (« resource fork, Finder information, or similar detritus not allowed »).
> `ios/build.sh` builde donc vers un `derivedDataPath` **hors `~/Documents`** (`$TMPDIR`).
> Si tu lances `xcodebuild` à la main, fais de même (`-derivedDataPath /tmp/...`).

> La target iOS est définie dans `project.yml` (sans Sparkle, macOS only). Comme pour le
> Mac, **`ios/Info.plist` et `ios/AuditViewerIOS.entitlements` sont générés par XcodeGen** —
> éditer `project.yml`, pas ces fichiers.

> Première install sur un appareil : accepter le **Program License Agreement** sur
> developer.apple.com, **enregistrer l'UDID** de l'appareil dans le portail, et activer le
> **Mode développeur** sur l'iPhone (Réglages › Confidentialité et sécurité).

---

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — structure du code et flux de données
- [TODOS.md](TODOS.md) — état d'avancement et reste à faire
- [CLAUDE.md](CLAUDE.md) — consignes pour les agents IA travaillant sur ce dépôt
