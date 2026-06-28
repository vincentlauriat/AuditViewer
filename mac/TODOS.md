# TODO — Audit Viewer

## État

✅ **Réaligné sur le contrat machine v1** du skill `audit-report`
(branche `feat/realign-contrat-v1`). P0 + P1 + P2 implémentés, `swift build`
et `./build.sh` verts. Reste la vérification visuelle (GUI) — cf. PLAN.md.

## Fait ✅

### Partie A — Output complet du skill
- [x] Entrée **Vérification des faits** (`_factcheck.md`, id -3)
- [x] Entrée **Chiffres-clés** (`_data.json` → markdown récursif, id -4)
- [x] Entrée **Sources** (index agrégé des URLs par domaine, id -5, badge de comptage)
- [x] Renommage de l'entrée méta en **Reconnaissance** (`_recon.json`, id -2)
- [x] Export `.docx` adapté aux nouvelles entrées
- [x] Découverte des sections fiabilisée (ordre stable, pas de collision d'id)

### Partie B — Carte canvas façon Obsidian
- [x] `GraphBuilder` : modèles + scan des sources + graphe local + graphe global
- [x] `GraphWebView` (WKWebView) + assets `Sources/WebGraph/{graph.html,graph.js}`
- [x] Moteur force-directed vanilla JS (pan/zoom/drag, survol, thèmes)
- [x] Bascule toolbar **Document/Carte** + **Audit courant/Global**
- [x] Clic de nœud → navigation (section → document ; audit → chargement)
- [x] `build.sh` copie `webgraph/` ; `Package.swift` exclut `Sources/WebGraph`

### Vérifications
- [x] `swift build` OK · `./build.sh` OK · app démarre
- [x] `node --check Sources/WebGraph/graph.js` OK

### Partie C — Réalignement contrat v1 (branche `feat/realign-contrat-v1`)
- [x] **P0** — Décodage events v1 (`AuditEvent` : `ts`/`v`, `init(from:)` tolérant
      → `.unknown`, payloads v1, repli legacy `t`/`step`). `applyEvent` gère
      `progress`/`dimension_done`/`question`/`audit_canceled`/`error`. Barre de
      progression chiffrée (`progress.pct`) dans `LiveProgressView`/`AuditProgressView`.
- [x] **P1** — `runAudit` : `--output` explicite + sujet/chemin quotés, slug v1
      (NFKD→ASCII), surveillance du dossier déterministe, `findNewAuditDir`/call sites alignés.
- [x] **P2** — `AuditManifest` (statut/dimensions/options + fallback scan),
      `_sources.json` → tableau (tag/date/⚠/dimensions, fallback scan),
      `_data.json` `kpis[]` → tableau KPI dédié (fallback `renderJSON`),
      `_control.json` cancel a minima (`cancelAudit()`).

## Reste à faire 🔜

- [ ] **Vérification visuelle GUI** du réalignement v1 (cf. PLAN.md § Validation) :
      audit `--app-mode` réel suivi en live (timeline + barre %), rendu des tableaux
      Sources/Chiffres-clés sur un audit v1, non-régression sur un audit legacy.
- [ ] **Bugs d'affichage précis** — à lister par Vincent, puis corriger
      (passe de revue ciblée sur `WebView`/`render.js`/`SidebarView`/`ContentView`).
- [ ] **Vérification visuelle de la carte** — non pilotée pendant le dev (extension Chrome non connectée) :
      ouvrir `audit-adcytherix`, tester pan/zoom/drag, clics de nœuds, vues locale et globale, thème clair/sombre.

## App macOS — Deux modes d'ouverture des audits (2026-06-29) ✅
- [x] Mode direct `⌘O` (inchangé) : ouvre un dossier d'audit précis, ouverture immédiate
- [x] Mode racine `⇧⌘O` : sélectionne un dossier racine → liste plein écran (titre, date, sources, profondeur, badge de statut) → clic ouvre l'audit → « ‹ Audits » pour revenir
- [x] `AuditEntry.swift` + `AuditListView.swift` créés ; `AuditStore` étendu : `audits`/`browseMode`/`browseRoot` + `openRootFolder`/`loadRoot`/`backToList`/`discoverAudits`/`loadEntry`
- [x] Détection des sous-dossiers audit : présence de `_manifest.json` ou `00_RESUME_EXECUTIF.md`
- [x] Dossier racine mémorisé dans le Keychain (`researchRoot`)
- [x] Chargement parallélisé (`withTaskGroup`) — évite le gel ~30 s sur dossier iCloud dataless
- [x] Entrée menu Fichier + bouton écran d'accueil (raccourci `⇧⌘O`)

## Idées / améliorations possibles

- [ ] Invalider `globalGraphCache` à la création d'un nouvel audit (actuellement persistant par session).
- [ ] Recherche/filtre dans la carte (mettre en avant un nœud par nom).
- [ ] Graphe global asynchrone si le scan de nombreux audits devient lent.
- [ ] Hiérarchie markdown plus fine dans **Chiffres-clés** (niveaux d'imbrication de `_data.json`).
