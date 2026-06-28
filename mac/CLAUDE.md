# CLAUDE.md — Audit Viewer

Consignes pour les agents IA travaillant sur ce dépôt. Lire aussi [ARCHITECTURE.md](ARCHITECTURE.md).

## Contexte

App macOS SwiftUI (SwiftPM) qui affiche les dossiers d'audit produits par le skill `audit-report`.
Le contenu dépend **directement du schéma de sortie de ce skill** (noms de fichiers, structure JSON).

## Langue
Communiquer et documenter en **français**. Les libellés d'UI sont en français.

## Build & vérification
Deux systèmes de build coexistent :
- **Dev rapide (SwiftPM)** : `swift build` pour vérifier la compilation, puis **`./build.sh`** pour un
  `.app` fonctionnel (`swift build` seul ne copie pas les bundles `web/` et `webgraph/`). Sparkle est
  ABSENT de ce build (`#if canImport(Sparkle)` → faux), l'app se lance sans auto-update.
- **Release distribuable (XcodeGen + Sparkle)** : `xcodegen generate` puis `xcodebuild`, orchestrés par
  **`Scripts/release.sh <version>`** (signe, notarise, DMG, Sparkle, appcast). Voir aussi la doc de
  distribution.
- Vérifier le lancement : `open build/AuditViewer.app`.

## Pièges spécifiques à ce projet
- **`Info.plist` est GÉNÉRÉ par XcodeGen** depuis `project.yml` (bloc `info.properties`). **Ne pas
  l'éditer à la main** — modifier `project.yml` puis `xcodegen generate`. La version se change via
  `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` dans `project.yml`.
- **Ressources web vendorisées** : `Resources/web/` est une **copie** du bundle de rendu de MarkdownViewer
  (MIT), embarquée pour rendre le repo autonome. Ne pas y mettre de code spécifique à AuditViewer ; tout
  asset propre à AuditViewer va dans `Resources/webgraph/` (bundle `webgraph/`).
- **`Resources/webgraph/`** (carte des liens, vanilla JS) et **`Resources/web/`** sont déclarés en
  *folder references* dans `project.yml` et copiés dans `Contents/Resources/{web,webgraph}` — noms
  attendus par `WebView.swift` / `GraphWebView.swift` (`Bundle.main.resourceURL`).
- **Sparkle** : intégration isolée dans `Sources/Updater.swift`, entièrement sous `#if canImport(Sparkle)`.
  Clé EdDSA partagée avec les autres apps (compte keychain `MarkdownViewer`).
- **Sections virtuelles** = id négatifs (-1 à -5), gérées dans `AuditStore.loadSection` et `SidebarView`.
  Les sections réelles statiques sont id 0-11 (`Models.swift`), les dynamiques 100+.
- **Dépendance au skill** : si les noms de fichiers (`00_*.md`, `_factcheck.md`, `_data.json`,
  `_recon.json`) ou leurs structures changent côté skill, réaligner `auditSections` (`Models.swift`),
  la détection dans `loadAuditDir`, `AuditMeta`, et `GraphBuilder`.
- **Trois cibles** : ce dépôt build **macOS** (app complète), **iOS/iPadOS** (`ios/`, lecteur lecture
  seule) et **tvOS** (`tvos/`, lecteur Apple TV lecture seule). Les trois sont déclarées dans
  `project.yml` ; iOS et tvOS sont sans Sparkle. tvOS partage `Sources/AuditManifest.swift`.
- **Piège tvOS — *focus engine*** : sur tvOS, une `ScrollView`/`List` ne défile et n'est atteignable
  que si elle **contient des éléments focusables**. Le contenu textuel pur (rendu Markdown natif
  SwiftUI dans `tvos/Sources/`, **pas** de `WKWebView`) doit être **enveloppé pour devenir focusable**,
  sinon il est inaccessible à la télécommande.
- **Piège iOS — placeholders iCloud** : les dossiers/fichiers du dossier Research choisi peuvent être
  *visibles mais non téléchargés* (dataless ; un dossier entièrement évincé apparaît parfois comme fichier
  caché `.audit-x.icloud`). `startDownloadingUbiquitousItem` est **asynchrone** : le déclencher sans
  attendre fait échouer le listing/lecture qui suit → audits manquants ou « aucun audit ». `ResearchVaultReader`
  télécharge donc de façon **bloquante** (`downloadAndWait`, polling du statut), liste la racine via
  `NSFileCoordinator`, sans `.skipsHiddenFiles`, et résout les noms `.icloud` → nom réel.
- **Piège tvOS — ingestion réseau** : tvOS n'a ni Files picker, ni iCloud Drive, ni stockage local
  persistant. L'Apple TV lit via HTTP le dossier `Research` partagé par le Mac (`Sources/LANServer.swift` :
  `NWListener` + Bonjour `_auditviewer._tcp`, serveur GET-only lecture seule, anti *path-traversal*).
  Réglage **« Partager sur le réseau local »** *off* par défaut. Un audit **sans `_manifest.json`**
  (legacy) est servi via l'endpoint `/files`. Déclarer `NSBonjourServices` +
  `NSLocalNetworkUsageDescription`, **pas** d'entitlements iCloud, dans `project.yml`.

## Conventions de code
- Concurrence Swift 6 stricte : `AuditStore` est `@MainActor @Observable` ; respecter `Sendable`
  pour tout ce qui traverse les frontières d'acteur (cf. `LineAccumulator`, `Task.detached` pour les diffs).
- Suivre le style existant : commentaires en français, `// MARK:` pour les sections, libellés FR.
- Communication WKWebView : Swift→JS via `evaluateJavaScript`, JS→Swift via `WKScriptMessageHandler`.
- Ne pas ajouter de dépendances externes pour le rendu : le bundle carte est **vanilla JS sans dépendance**
  (offline). Garder cette contrainte.

## Débogage
- Corriger la cause racine, pas les symptômes. Ne pas masquer une erreur par du logging.
- Le `WKWebView` a `developerExtrasEnabled` : inspecter via l'inspecteur Web pour les soucis de rendu.

## Git
- Ne jamais push sur `main` directement ; créer une feature branch (sauf instruction contraire).
- Demander la stratégie git avant tout push ; confirmer avant tags/releases. Commits conventionnels.
