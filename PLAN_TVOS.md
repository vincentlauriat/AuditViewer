# PLAN — Viewer tvOS (Apple TV) — lecteur d'études en lecture seule

Étude de faisabilité validée le 2026-06-21. Décisions retenues :
- **Ingestion des données** : Bonjour + serveur HTTP sur le réseau local (Mac = serveur, Apple TV = client). Offline-LAN, pas de cloud.
- **Périmètre** : reader-only, calqué sur l'app iOS P0 (synthèse, dimensions, KPIs, sources). Pas de création/màj d'audit, pas de CLI `claude`, pas de Sparkle.

## Pourquoi pas iCloud / Files (rappel du blocage)
tvOS n'expose **ni** le Files picker (`UIDocumentPicker`/`.fileImporter`), **ni** les documents iCloud Drive (ubiquity container), **ni** de stockage local persistant (seul `Caches/` purgeable existe). Toute la couche d'accès iOS (`ResearchFolderBookmark`, `ResearchVaultReader`, security-scoped bookmark) est donc **inutilisable** et remplacée par un transport réseau.

## Architecture cible

```
┌─ Mac (app AuditViewer) ──────────┐         LAN          ┌─ Apple TV (AuditViewerTVOS) ─┐
│  researchRoot (~/Documents/      │  Bonjour _auditviewer │  NWBrowser → découvre le Mac │
│  Research/) en lecture seule     │  ._tcp                │  Client HTTP → fetch JSON/md │
│  NWListener (Network.framework)  │ ───────────────────▶  │  AuditStoreTVOS (@Observable)│
│  sert un contrat REST read-only  │   HTTP GET            │  Vues 10-foot + focus engine │
└──────────────────────────────────┘                      └──────────────────────────────┘
```

### Contrat REST (aligné sur le backend Express V1 déjà conçu)
Serveur en lecture seule, garde-fou path-traversal sur tous les chemins :
- `GET /api/audits` → liste des dossiers `audit-*/` (slug + titre depuis `_manifest.json`).
- `GET /api/audit/{slug}/manifest` → `_manifest.json`.
- `GET /api/audit/{slug}/data` → `_data.json`.
- `GET /api/audit/{slug}/sources` → `_sources.json`.
- `GET /api/audit/{slug}/file?name=...` → un `.md` (validation : nom simple, pas de `..`, extension `.md`).

## Phases

### Phase 1 — Serveur Mac (Bonjour + HTTP read-only)
Nouveau fichier `mac/Sources/LANServer.swift` dans l'app macOS :
- `NWListener` (Network.framework) sur un port éphémère, parseur HTTP minimal (GET seul).
- Publication Bonjour `_auditviewer._tcp` (nom = nom de la machine).
- Sert `KeychainStore.researchRoot` (ou son repli) via le contrat REST ci-dessus, **lecture seule**.
- Garde-fou path-traversal (réutiliser la logique éprouvée du backend Express V1).
- Activation depuis un réglage/menu macOS : « Partager les audits sur le réseau local » (off par défaut).
- Indicateur d'état (actif / nb de clients) dans l'UI macOS.

### Phase 2 — Target tvOS + transport réseau
- `project.yml` : ajouter le target `AuditViewerTVOS` (platform: tvOS, deploymentTarget 17.0), sur le modèle exact de la section iOS (lignes 71-123) — **sans** entitlements iCloud, **sans** Sparkle.
- `tvos/Sources/` :
  - Modèles partagés : réutiliser `AuditEvent`, `AuditManifest`, `AuditMeta`, `AuditOptions`, `ModelsIOS` (copie ou référence croisée depuis `ios/Sources`/`Sources`).
  - `BonjourBrowser.swift` : `NWBrowser` qui découvre les serveurs `_auditviewer._tcp`, résout host:port.
  - `AuditAPIClient.swift` : `URLSession` typé sur le contrat REST.
  - `AuditStoreTVOS.swift` : `@MainActor @Observable`, état (serveurs trouvés, audit sélectionné, contenu chargé).
- `tvos/build.sh` : build simulateur tvOS + appareil (sur le modèle de `ios/build.sh`).

### Phase 3 — UI 10-foot (réutilisation iOS reskinnée)
- Écran de connexion : liste des Mac découverts en Bonjour (focusable télécommande).
- Liste des audits + détail en `TabView` (Synthèse / Dimensions / Sources), repris d'`AuditDetailView`.
- Rendu markdown : réutiliser `DimensionView` (WKWebView via `UIViewRepresentable` + HTML inline) — compatible tvOS, CSS adapté grand écran (grandes polices, contraste, marges TV-safe).
- `KPIGridView` / `SourcesView` repris ; retirer `UIApplication.shared.open` (ouvrir une URL n'a pas de sens sur TV).
- Navigation **focus engine** (pas de scroll tactile) : vérifier focusabilité de chaque liste/onglet.

### Phase 4 — Build, signing, test appareil
- Génération XcodeGen + build du target tvOS (simulateur d'abord).
- Test bout-en-bout : Mac partage → Apple TV découvre → ouvre un audit réel → 3 onglets + rapport markdown.
- Signing appareil (même `DEVELOPMENT_TEAM` KFLACS69T9).

## Réutilisation vs nouveau code
| Réutilisé quasi tel quel | Nouveau (tvOS) | Nouveau (Mac) |
|---|---|---|
| Modèles (`AuditEvent`, `AuditManifest`, `AuditMeta`, `AuditOptions`, `ModelsIOS`) | `BonjourBrowser`, `AuditAPIClient`, `AuditStoreTVOS` | `LANServer` (NWListener + Bonjour) |
| `DimensionView` (WKWebView + HTML inline) | UI connexion + focus 10-foot | Réglage « Partager sur le réseau » |
| `KPIGridView`, `SourcesView` (sans `open(url)`) | `tvos/build.sh`, target XcodeGen | Indicateur d'état serveur |

## Estimation
- Phase 1 (serveur Mac) : ~2 j
- Phase 2 (target + transport) : ~2 j
- Phase 3 (UI 10-foot) : ~2-3 j
- Phase 4 (build/signing/test) : ~1 j
- **Total ~7-8 j**

## Risques / points ouverts
- Parseur HTTP maison minimal côté Mac : garder le périmètre strict (GET only) pour limiter la surface.
- `WKWebView` sur tvOS : confirmer le rendu HTML inline sur appareil réel (pas seulement simulateur).
- Sécurité LAN : serveur read-only, mais envisager un appairage simple (code à l'écran) si réseau non fiable — différé (P1).
- Pas de persistance tvOS : tout est re-fetch à chaque lancement (acceptable, audits légers).
