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
