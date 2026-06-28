# TODOS — Contrat machine v1 (P0 + P1)

## P0 — Contrat machine
- [x] 1. Helper `_emit.py` (émission fiable via argv)
- [x] 2. `_events.jsonl` versionné + émission par dimension en parallel
- [x] 3. `_control.json` (cancel/pause/resume/rerun) + points de contrôle
- [x] 4. Cycle de vie `_question.json`/`_answer.json` (atomique, timeout 30 min → cancel)
- [x] 5. `_manifest.json` final canonique
- [x] 6. `_sources.json` + `_data.json` générique (kpis[])

## P1 — Bugs & cohérence
- [x] 7. Années dynamiques dans les requêtes
- [x] 8. Assemblage conditionnel du rapport
- [x] 9. Mode update en app-mode
- [x] 10. Conflits d'options (`--brief` exclusif)
- [x] 11. Slug déterministe
- [x] 12. Numérotation à trous documentée (manifest = source de vérité)

## Validation
- [x] Snippets Python valides (py_compile + smoke test slug/emit/ctl/ask OK)
- [x] Émission JSONL robuste aux apostrophes/accents (lignes JSON valides)
- [ ] Commit + PR sur feat/app-mode-contract

## Test bout-en-bout (fait)
- [x] Audit Notion réel en --app-mode → fixtures `viewer-fixtures/notion/`
- [x] Contrat validé : 39 events valides, manifest complete, data/sources structurés

## AuditViewer V1 — Visualisation (en cours)
- [x] Backend Express : /api/audits, manifest/data/sources/file, SSE events
- [x] Frontend Vite/React : sidebar, header+progress, onglets Synthèse/Dimensions/Sources/Timeline/Rapport
- [x] Composants : Kpis, Sources, Timeline, Markdown ; types partagés contrat v1
- [x] npm install + typecheck + build (verts)
- [x] Vérif endpoints sur fixtures Notion (audits/manifest/data/sources/file/SSE + garde-fou path-traversal)
- [ ] Commit + PR
- [ ] Vérif visuelle navigateur (à faire par l'utilisateur ou via screenshot)

## AuditViewer V2 — Pilotage + config (fait)
- [x] Runner headless : `claude -p` (binaire surchargeable via `CLAUDE_BIN`)
- [x] Répertoire des audits configurable depuis l'UI (env > fichier > défaut)
  - [x] `AUDITS_ROOT` dynamique (scan + garde-fou path-traversal recalculés à chaud)
  - [x] `GET`/`PUT /api/config` (mkdir récursif, vérif écriture, persistance atomique, 409 si env)
  - [x] Panneau Réglages ⚙ (champ pré-rempli, lecture seule si imposé par env)
- [x] `POST /api/audits/launch` (slug déterministe TS, spawn detached, log `_runner.log`, 409 si en cours)
- [x] `POST /api/audit/:slug/answer` (`_answer.json` atomique `{v,id,value}`)
- [x] `POST /api/audit/:slug/control` (`_control.json` atomique ; `cancel` tue le process)
- [x] `GET /api/audit/:slug/question` + `GET /api/audit/:slug/status`
- [x] UI : bouton « Nouvel audit » + formulaire, modale de question (SSE), barre de contrôle
- [x] typecheck + build verts
- [x] Test du câblage via faux `CLAUDE_BIN` : launch→SSE→answer→complete OK,
      control/cancel OK, garde-fou path-traversal OK (answer/control/question = 404)
- [ ] Vérif visuelle navigateur (à faire par l'utilisateur)
- [ ] Test avec un audit réel `claude -p` (à faire par l'utilisateur)

## Skill — correctifs notés
- [x] event `audit_start --options` : CSV ou vide (jamais `none`) — précisé dans SKILL.md
- [x] Durcissement launch : sujet quoté/échappé (anti-injection d'arguments) + validation

## Compatibilité Multi-Plateforme (Claude & Gemini)
- [x] 1. Rendre SKILL.md agnostique des outils propriétaires (concepts génériques)
- [x] 2. Implémenter le fallback automatique --mode solo si pas de support d'Agent (Gemini)
- [x] 3. Mettre à jour install.sh avec support --gemini (symlinks dans ~/.gemini/config/skills)
- [x] 4. Tester de bout en bout l'audit Yealink en mode solo sur Gemini (OK)

## App tvOS (Apple TV) — Lecteur d'études (lecture seule) — étude validée, voir PLAN_TVOS.md
Ingestion : Bonjour + HTTP LAN (Mac = serveur). Périmètre : reader-only.
- [x] Phase 1 — Serveur Mac `LANServer.swift` (NWListener + Bonjour `_auditviewer._tcp`, REST read-only de researchRoot, garde-fou path-traversal par énumération, toggle dans Réglages + indicateur d'état). Testé : logique métier + serveur réseau réel (URLSession) + 3 cas path-traversal → 404. `swift build` vert.
- [x] Phase 2 — Target `AuditViewerTVOS` (project.yml, tvOS 17, Bonjour/local-network plist) + `BonjourBrowser`/`EndpointResolver` + `AuditAPIClient` + `AuditStoreTVOS` + vue squelette + `tvos/build.sh`. Build simulateur tvOS vert. Transport client↔serveur testé bout-en-bout (audits/manifest/sources/file décodés). Reste à valider sur simulateur/appareil : découverte Bonjour réelle + résolution endpoint.
- [x] Phase 3 — UI 10-foot : navigation liste → détail (TabView Synthèse/Dimensions/Sources/Rapport). Rendu Markdown **natif SwiftUI** (pas WKWebView : scroll télécommande non fiable) gérant titres/paragraphes/listes/tableaux/citations/code. KPIs + sources + badges. Build simulateur + déploiement Apple TV verts.
- [x] Phase 4 — Build/test/signing appareil
  - [x] Build simulateur + test : découverte Bonjour OK (screenshot), serveur LAN validé curl réel (audits/manifest/file, traversal→404)
  - [x] Auto-connexion si 1 seul serveur (UX 10-foot)
  - [x] Icône d'app tvOS (brand assets opaques 2 couches, depuis AppIcon.icns) — requise pour install appareil
  - [x] Apple TV « Salon (2) » appairée à Xcode (Wi-Fi)
  - [x] `./tvos/build.sh <UDID>` : build signé + install + launch sur l'Apple TV (OK)
  - [x] Sur appareil : découverte + résolution Bonjour + chargement des 25 audits réels OK
        (la résolution échouait dans le simulateur — artefact simulateur, confirmé OK sur appareil)

## App tvOS — correctifs post-livraison
- [x] Défilement à la télécommande : tout contenu consultable rendu **focusable**
      (Markdown, KPIs, chips, sources) — sinon ScrollView/onglet inatteignable sur tvOS
- [x] Rendu Markdown en `VStack` (non lazy) pour que les blocs hors écran soient focusables
- [x] Onglets Synthèse + Sources enveloppés dans `NavigationStack` (focus depuis la barre d'onglets)
- [x] Audits sans `_manifest.json` (legacy) / « résumé seul » : endpoint serveur `/files`,
      repli du fichier de Rapport, Dimensions construites depuis les fichiers, titre prettifié

## App macOS — KPI fullscreen viewer (2026-06-24)
- [x] Add `.kpis` case to `AuditStore.ViewMode`
- [x] Create dedicated fullscreen KPI view with 4-column grid layout
- [x] Add "Chiffres clés" tab to main toolbar picker (Document / Carte / Chiffres clés)
- [x] Remove right-side KPI sidebar + toggle button (simplify UI)
- [x] Animation fixes for view mode transitions
- [x] Build + compile verification (exit code 0)
- [ ] Visual verification on macOS: open OneStream audit + test "Chiffres clés" tab
- [ ] Commit + PR: KPI fullscreen mode feature

## App macOS — Export PDF/DOCX + cartes KPI (2026-06-26)
- [x] Export PDF de la section courante (bouton toolbar `doc.richtext`)
- [x] Page de garde professionnelle (titre, sous-titre, date d'extraction, nb de sources) — PDF **et** DOCX
- [x] DOCX : métadonnées via `--metadata` CLI (page de titre Word)
- [x] PDF : pandoc `--to html5` (fichier temp, anti-deadlock pipe) + `buildPDFHTML` (CSS @page A4)
- [x] `PDFExporter` réécrit : `WKWebView.printOperation` + `NSWindow` hors-écran + `runModal` async
      (remplace `WKWebView.pdf()` qui produisait des fichiers multi-GB rastérisés 2x)
- [x] Fix freeze : `NSPrintOperation.run()` synchrone → `runModal(…didRun:)` asynchrone
- [x] Fix crash SIGTRAP : `PrintDelegate` `nonisolated` (callback AppKit sur thread d'arrière-plan)
- [x] Fix rapport complet en markdown brut (cadre gris) : `--from markdown-yaml_metadata_block`
      (blocs `---`…`---` pris pour du YAML → exit 64 → fallback `<pre>`) — vérifié exit 0 / 163 Ko HTML
- [x] Écran « Chiffres clés » : chaque KPI dans une carte encadrée (bordure, ombre, barre d'accent, capsule estimé)
- [x] Build + relance app à chaque étape (vert)
- [ ] Vérif visuelle utilisateur : export PDF du rapport complet (pagination A4) + cartes KPI en thèmes clair/sombre

## App iOS / iPadAS — Lecteur d'études (lecture seule)
- [x] Target `AuditViewerIOS` buildable (project.yml : info.properties + entitlements iCloud)
- [x] Accès au dossier Research via sélecteur Fichiers + security-scoped bookmark persistant
      (`ResearchFolderBookmark`), avec repli `Documents/Research` exposé dans Fichiers
- [x] UX sélecteur : bouton état vide + bouton toolbar (`.fileImporter` dossier)
- [x] `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` + `NSUbiquitousContainers`
- [x] Build simulateur verte (Swift 6 strict, 0 erreur) + lancement vérifié (état vide OK)
- [ ] Vérif sur appareil réel : ouvrir le vrai dossier Research iCloud, téléchargement à la demande
- [ ] Vérif visuelle d'un audit réel (liste + 4 onglets + rapport markdown) iPhone & iPad

