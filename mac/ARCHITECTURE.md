# Architecture — Audit Viewer

App SwiftUI macOS, paquet SwiftPM exécutable (`Package.swift`, cible `AuditViewer`, `path: "Sources"`,
`exclude: ["WebGraph"]`). Le rendu de contenu repose sur deux bundles web chargés dans des `WKWebView`
(`file://`), tout le reste est natif SwiftUI + AppKit.

## Vue d'ensemble du flux

```
Dossier audit-{sujet}/ ──► AuditStore (état @Observable, @MainActor)
   *.md, _recon.json,            │
   _data.json, _factcheck.md,    ├─► sections + entrées virtuelles ──► SidebarView (sélection)
   _events.jsonl, _options.json  │
                                 ├─► currentMarkdown ──► WebView (WKWebView, markdown-it)   [mode Document]
                                 │
                                 └─► graphJSON(scope) ─► GraphWebView (WKWebView, canvas)    [mode Carte]
                                          ▲                        │ clic nœud (postMessage)
                                          └── GraphBuilder ◄────────┘
```

## Composants

### État
- **`AuditStore`** (`Sources/AuditStore.swift`) — source de vérité unique (`@Observable`, `@MainActor`).
  Charge un dossier (`loadAuditDir`), résout les sections, lit la section courante (`loadSection`),
  lance/relance les audits (`runAudit`/`rerunAudit`), surveille `_events.jsonl`, calcule les diffs,
  exporte en `.docx`, et construit les données de graphe (`graphJSON`, `handleGraphNodeTap`).
- **`AuditOptions`** (`Sources/AuditOptions.swift`) — options de lancement → flags CLI `/audit-report`
  (persistées dans `_options.json`).
- **`AuditMeta`** (`Sources/AuditMeta.swift`) — décodage de `_recon.json` (`key_players`, `sector`, …).
- **`AuditEvent`** (`Sources/AuditEvent.swift`) — événements `_events.jsonl` (mode `--app-mode`).
- **`Models.swift`** — `AuditSection` + liste statique `auditSections` ; `dynamicSectionBaseId = 100`
  pour les sections découvertes dynamiquement ; `LogEntry`.

### Sections et entrées virtuelles
- Sections réelles : id `0…11` (liste statique), id `100+` (markdown découvert dynamiquement,
  hors fichiers préfixés `_`).
- **Entrées virtuelles** (id négatifs) gérées dans `loadSection` et listées par `SidebarView` :
  | id | entrée | source |
  |----|--------|--------|
  | -1 | Modifications | diff (`DiffEngine`) |
  | -2 | Reconnaissance | `_recon.json` → `generateMetaMarkdown` |
  | -3 | Vérification des faits | `_factcheck.md` |
  | -4 | Chiffres-clés | `_data.json` → `generateDataMarkdown` (rendu JSON récursif) |
  | -5 | Sources | scan des `.md` → `generateSourcesMarkdown` |

### Vues
- **`AuditViewerApp`** — point d'entrée `@main`, scènes `WindowGroup` + `Settings`, menus/raccourcis
  (postent des `Notification` consommées par les vues).
- **`ContentView`** — `NavigationSplitView` (sidebar + détail). Le pane détail bascule entre
  `WebView` (Document) et `GraphWebView` (Carte) selon `store.viewMode` ; toolbar avec pickers
  segmentés **Document/Carte** et **Audit courant/Global**.
- **`SidebarView`** — `List` liée à `store.selectedSectionId` ; sélectionner une section ramène
  au mode Document.
- **`WebView`** (`Sources/WebView.swift`) — `NSViewRepresentable` autour d'un `WKWebView` chargeant
  `web/index.html`. Injecte le markdown via `window.renderMarkdown(...)`, gère le thème, la recherche
  (`WKFindConfiguration`) et l'ouverture des liens externes.
- **`GraphWebView`** (`Sources/GraphWebView.swift`) — `NSViewRepresentable` chargeant
  `webgraph/graph.html`. Injecte le graphe via `window.renderGraph(<json>)`, reçoit les clics de nœuds
  via un `WKScriptMessageHandler` nommé `graph` → `store.handleGraphNodeTap(...)`.
- Autres : `EmptyStateView`, `FindBar`, `LiveProgressView`/`AuditProgressView`, `LogsView`,
  `NewAuditSheet`/`UpdateAuditSheet`/`QuestionSheet`, `SettingsView`, panels (`*PanelController`).

### Graphe — `GraphBuilder` (`Sources/GraphBuilder.swift`)
- Modèles `Codable` : `GraphNode { id, label, type, sectionId?, auditPath?, weight }`,
  `GraphEdge { source, target, kind }`, `GraphData`.
- `scanSources(in:)` — regex `[label](http…)` sur les `.md` → domaines cités.
- `buildLocalGraph` — nœud `subject` central, un nœud `section` par section existante (arête de
  rayonnement), un nœud `source` par domaine, un nœud `entity` par acteur clé (relié aux sections
  qui le mentionnent).
- `buildGlobalGraph(root:)` — un nœud `audit` par dossier `audit-*`, nœuds `source`/`entity`
  **partagés par ≥ 2 audits** → met en évidence les liens inter-audits.
- Encodé en JSON par `AuditStore.graphJSON(for:)` (caché par périmètre).

### Rendu web
- **`graph.js`** (`Sources/WebGraph/`) — moteur force-directed **vanilla JS** sur `<canvas>`
  (aucune dépendance, 100 % offline) : répulsion O(n²) + ressorts + gravité centrale ; pan/zoom/drag,
  survol mettant en évidence les voisins, libellés adaptatifs, thèmes clair/sombre.
  API : `window.renderGraph(data)`, `window.setTheme(theme)` ; clics → `webkit.messageHandlers.graph`.

## Stockage / ressources

- **Dossiers d'audit** : `~/Documents/Research/audit-{slug}/` (racine configurable via `KeychainStore.researchRoot`).
- **Bundle markdown** (`web/`) : **partagé** avec le projet voisin `MarkdownViewer`, copié par `build.sh`
  depuis `../MarkdownViewer/MarkdownViewer/Resources/web`. ⚠️ Ne pas modifier les assets là-bas pour
  AuditViewer — ils servent aussi à l'autre app.
- **Bundle carte** (`webgraph/`) : **propre à AuditViewer**, `Sources/WebGraph/`, copié par `build.sh`.

## Communication WKWebView ↔ Swift

| Sens | Mécanisme |
|------|-----------|
| Swift → JS (markdown) | `evaluateJavaScript("window.renderMarkdown(<json>)")` |
| Swift → JS (graphe) | `evaluateJavaScript("window.renderGraph(<json>)")` (JSON = littéral JS valide) |
| Swift → JS (thème) | `window.setTheme('dark'|'light')` |
| JS → Swift (clic nœud) | `WKScriptMessageHandler` nommé `graph` |
| Lancement d'audit | `Process` exécutant `claude --output-format stream-json -p "/audit-report …"` ; stdout parsé ligne à ligne |
| Suivi d'audit | `DispatchSource` sur `_events.jsonl` + polling de `_question.json` |

## Partage réseau local — `LANServer` (`Sources/LANServer.swift`)

Composant macOS qui **sert le dossier `Research` en lecture seule sur le réseau local**, afin que le
viewer Apple TV (qui n'a ni Files picker, ni iCloud, ni stockage persistant) puisse consulter les audits.

- **`NWListener`** (Network.framework) sur un port éphémère + publication Bonjour **`_auditviewer._tcp`**
  (nom = nom de la machine) ; parseur HTTP/1.1 minimal **GET seul**.
- Sert `KeychainStore.researchRoot` (ou son repli) ; garde-fou **anti path-traversal par énumération
  réelle** des fichiers.
- Activé via un réglage macOS **« Partager sur le réseau local »** (*off* par défaut) ; indicateur d'état
  (actif / nb de clients) dans l'UI.
- **API REST** (alignée sur le contrat machine v1, mêmes `_manifest.json`/`_data.json`/`_sources.json`) :

  | Route | Réponse |
  |---|---|
  | `GET /api/audits` | liste des dossiers `audit-*/` (slug + titre depuis `_manifest.json`) |
  | `GET /api/audit/{id}/manifest` | `_manifest.json` |
  | `GET /api/audit/{id}/data` | `_data.json` |
  | `GET /api/audit/{id}/sources` | `_sources.json` |
  | `GET /api/audit/{id}/files` | liste des `.md` de l'audit |
  | `GET /api/audit/{id}/file?name=X.md` | un `.md` (validation : nom simple, pas de `..`, extension `.md`) |

## Cible iOS / iPadOS (`ios/Sources/`, lecture seule)

Target SwiftUI **`AuditViewerIOS`** (définie dans `project.yml`, sans Sparkle) qui lit le
même contrat machine v1, sans pilotage (pas de `Process`/`NSOpenPanel`, pas de graphe).

- **`AuditViewerIOSApp`** — `@main`, injecte `AuditStoreIOS` (`@Observable @MainActor`).
- **`AuditListView`** — `NavigationSplitView` (deux colonnes sur iPad, pile sur iPhone) ;
  `.fileImporter([.folder])` pour choisir le dossier `Research`.
- **`AuditDetailView`** — `TabView` 4 onglets : Synthèse (+`KPIGridView`), Dimensions,
  `SourcesView`, Rapport (`DimensionView` → `MarkdownWebView` WKWebView).
- **`ResearchFolderBookmark`** — persiste un **security-scoped bookmark** du dossier choisi
  (UserDefaults), accès maintenu actif pour la durée du process.
- **`ResearchVaultReader`** — découverte des `audit-*/` + lecture via `NSFileCoordinator`
  (téléchargement iCloud à la demande) ; repli `fallbackSandboxRoot` = `Documents/Research`.
- **Accès Fichiers** : `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` +
  `NSUbiquitousContainers` (entitlements iCloud Documents générés par XcodeGen).

> Dépendance au skill identique au Mac : si les noms de fichiers du contrat changent,
> réaligner `AuditManifest`/`AuditMeta`/`ModelsIOS` côté iOS comme `Models.swift` côté Mac.

## Cible tvOS / Apple TV (`tvos/Sources/`, lecture seule)

Target SwiftUI **`AuditViewerTVOS`** (tvOS 17+, définie dans `project.yml`, sans Sparkle ni entitlements
iCloud) pour consulter les audits **sur grand écran** (réunions/présentations). Pas de création/màj,
pas de CLI `claude`.

- **Ingestion par le réseau local** (point d'architecture central) : tvOS n'a ni Files picker, ni iCloud
  Drive, ni stockage local persistant — toute la couche d'accès iOS (`ResearchFolderBookmark`,
  `ResearchVaultReader`, security-scoped bookmark) est donc **inutilisable**. Le Mac partage à la place
  son dossier `Research` via le composant **`LANServer`** (voir plus haut) ; tout est re-fetch à chaque
  lancement (pas de persistance).
- **`BonjourBrowser`** (`NWBrowser`) — découvre les serveurs `_auditviewer._tcp` sur le réseau local.
- **`EndpointResolver`** — résout un service Bonjour en `http://host:port`.
- **`AuditAPIClient`** — client REST typé (`URLSession`) sur le contrat exposé par `LANServer`
  (`/api/audits`, `/api/audit/{id}/manifest|data|sources|files`, `/api/audit/{id}/file?name=X.md`).
- **`AuditStoreTVOS`** — source de vérité (`@Observable @MainActor`) : serveurs trouvés, audit
  sélectionné, contenu chargé.
- **Vues SwiftUI 10-foot** : écran de connexion (liste des Mac découverts, focusable télécommande),
  liste des audits + détail en `TabView` (Synthèse / Dimensions / Sources). Rendu Markdown **natif
  SwiftUI** (pas de `WKWebView` : scroll télécommande non fiable) ; tout le contenu est rendu
  **focusable** pour le focus engine.

> Dépendance au skill identique au Mac, mais via le réseau : si les noms de fichiers du contrat changent,
> réaligner conjointement `LANServer` (Mac) et le client tvOS (`AuditAPIClient` + modèles partagés).

## Build des cibles

XcodeGen (`project.yml`) génère les trois targets ; la cible tvOS partage `Sources/AuditManifest.swift`.

| Cible | Build | iCloud / Sparkle | Clés `Info.plist` notables |
|---|---|---|---|
| `AuditViewer` (macOS) | `build.sh` (SwiftPM) / `Scripts/release.sh` (XcodeGen + Sparkle) | Sparkle (release) | — |
| `AuditViewerIOS` | `ios/build.sh` | entitlements iCloud Documents | `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, `NSUbiquitousContainers` |
| `AuditViewerTVOS` | `tvos/build.sh` | aucun | `NSBonjourServices`, `NSLocalNetworkUsageDescription` |
