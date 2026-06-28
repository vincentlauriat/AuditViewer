# PLAN — Durcissement du contrat machine du skill `audit-report` (P0 + P1)

Objectif : rendre le skill pilotable et observable depuis l'AuditViewer, en remplaçant
la couche `--app-mode` best-effort par un **contrat machine v1 déterministe et versionné**.
Ce document fait aussi office de **spécification du contrat** partagée entre le skill et le Viewer.

## P0 — Contrat machine (bloquants Viewer)

### 1. Helper d'émission fiable — `_emit.py`
Écrit une fois dans `OUTPUT_DIR` au démarrage si `APP_MODE`. Prend le type d'event +
des paires `--clé valeur` en argv (pas d'interpolation dans le source → robuste aux
apostrophes/sauts de ligne). Ajoute `v` et `ts` automatiquement. Append une ligne JSON
dans `_events.jsonl`.

### 2. `_events.jsonl` — flux d'événements versionné (append-only)
Champs communs : `v` (=1), `ts` (ISO8601 UTC), `type`.
Types :
- `audit_start` `{subject, depth, mode, options, output_dir}`
- `phase_start` / `phase_done` `{phase, label}` — phases : `recon`, `research`, `factcheck`, `swot`, `summary`, `assembly`, `finalize`
- `dimension_start` / `dimension_done` `{dimension, label, status, sources_count?, summary?}` — dimensions : `historique, marche, technique, tarification, concurrence, financier, futur, esg, rh`
- `progress` `{done, total, pct}`
- `search` `{query}` *(verbose)*
- `source` `{url, title, tag}` *(verbose)*
- `file_written` `{file}`
- `question` `{id}` — une question attend dans `_question.json`
- `answer` `{id, value}`
- `error` `{phase?, dimension?, message}`
- `audit_complete` `{files_count, sources_count, status}`
- `audit_canceled` `{reason}`

**Clé** : en `--mode parallel`, le **contexte principal** émet `dimension_start`/`dimension_done`
autour de chaque dispatch d'agent (les sous-agents restent muets) → l'UI n'est jamais aveugle.

### 3. `_control.json` — canal UI → skill (pilotage)
L'UI écrit `{v, action, dimension?}`. Le skill le **relit aux points de contrôle**
(après chaque dimension, avant assemblage) puis le **consomme** (supprime).
Actions : `cancel`, `pause`, `resume`, `rerun` (+ `dimension`).
- `cancel` → arrêt propre, `audit_canceled`, manifest partiel `status: canceled`.
- `pause`/`resume` → boucle d'attente bornée.

### 4. Cycle de vie question/réponse durci
- Skill écrit `_question.json` `{v, id, text, options}` + émet `question`.
- UI écrit `_answer.json` **atomiquement** (tmp + rename).
- Skill poll, lit, **supprime `_answer.json` ET `_question.json`**, émet `answer`.
- **Timeout défini** : défaut 30 min → à expiration, comportement = `cancel` + `error{message:"timeout"}`.

### 5. `_manifest.json` — index canonique final
`{v, subject, subject_type, slug, output_dir, audit_date, depth, mode, options,
status, dimensions[{key,file,status,sources_count}], files[{name,kind}],
sources_count, data_file, sources_file, report_file}`.
Statuts : `complete | partial | canceled`.

### 6. Sorties structurées
- `_sources.json` : `{v, sources:[{id,url,title,tag,date,dimensions[],stale}]}`.
- `_data.json` **générique** : `{v, subject, subject_type, as_of, kpis:[{key,label,value,unit,period,source_id,estimated}], financials?, market?}` — tableau `kpis` flexible + sections typées optionnelles (fin du schéma figé « énergie » avec `capacity_mw`).

## P1 — Bugs & cohérence

- **7. Années dynamiques** : `YEAR=$(date +%Y)`, `PREV=$((YEAR-1))`. Requêtes utilisent `{YEAR-1} {YEAR}` au lieu de `2024 2025` codés en dur.
- **8. Assemblage conditionnel** : TOC + fusion de `RAPPORT_COMPLET.md` n'incluent que les fichiers présents (gère `--depth quick`).
- **9. Mode update en app-mode** : variante `_question.json` pour « mettre à jour / repartir de zéro ».
- **10. Conflits d'options** : `--brief` est exclusif des dimensions optionnelles (`--swot/--esg/--rh` ignorés avec avertissement).
- **11. Slug déterministe** : minuscules, translittération ASCII (sans accents), non-alphanum → `-`, compression/trim des tirets. Snippet Python canonique. Dossier = `audit-{slug}`.
- **12. Numérotation à trous** documentée (l'UI lit `_manifest.json`, pas la numérotation).
- **13. Mappings d'outils génériques** : Remplacement des références directes aux outils de Claude (`Write`, `Edit`, `WebSearch`, `WebFetch`, `AskUserQuestion`) par des concepts génériques pour permettre le mapping automatique par d'autres modèles.
- **14. Mode Solo Intelligent** : Règles d'auto-fallback pour le `--mode solo` dans les environnements ne supportant pas de sous-agents textuels (ex: Gemini Code Assist / Antigravity).
- **15. Script d'installation multi-plateforme** : Mise à jour de `install.sh` avec le flag `--gemini` pour l'installation locale.

## P2 (différé)
- `datetime.utcnow()` → `datetime.now(timezone.utc)` (fait au passage dans `_emit.py`).
- Estimation de coût/temps pré-lancement.

## Versioning du contrat
Tous les artefacts JSON portent `"v": 1`. Toute évolution incrémente `v`.

## P3 (récemment complété — 2026-06-24)
- [x] **macOS app: KPIs fullscreen viewer** — New "Chiffres clés" tab in main toolbar
      - Added `.kpis` case to `AuditStore.ViewMode`
      - Fullscreen view with 4-column responsive grid layout
      - Removed right-side KPI sidebar (simplified UI)
      - Clean modal/tab-based access to key performance indicators
      - Animation fixes for view transitions

## P4 (récemment complété — 2026-06-26)
- [x] **macOS app: Export PDF + DOCX avec page de garde professionnelle**
      - Bouton « Exporter en PDF » dans la toolbar (à côté de l'export Word)
      - Page de garde marine (titre, sous-titre de section, date d'extraction, nb de sources) — PDF et DOCX
      - `PDFExporter` : impression WebKit hors-écran (`printOperation` + `NSWindow` invisible +
        `runModal` async) → PDF A4 **vectoriel paginé**, sans freeze ni fichier multi-GB
      - Conversion pandoc avec `markdown-yaml_metadata_block` désactivé (les blocs `---`…`---` du
        rapport complet cassaient le parsing YAML → markdown brut dans un cadre gris)
- [x] **macOS app: cartes encadrées pour l'écran « Chiffres clés »**
      - `KPICellView` : coins arrondis continus, bordure fine selon le thème, ombre douce,
        barre d'accent latérale (bleu / orange si estimé), badge « estimé » en capsule

## Hors périmètre (Viewer, étape suivante)
Runner headless (`claude -p` vs Agent SDK), rendu markdown, UI de pilotage.
Décision pressentie : Agent SDK pour le streaming, `_events.jsonl` + `_control.json` en canal fichier de secours.
Prochaines vues macOS : possibilité d'un mode sidebar KPI si demande utilisateur (actuellement fullscreen via onglet dédié).

---

# P5 — Deux modes d'ouverture des audits (macOS) — ✅ complété (2026-06-28)

## Objectif
Ajouter à l'app macOS un **second mode d'ouverture**, en plus du mode actuel :
1. **Mode direct (existant)** — on pointe un dossier d'audit précis (`⌘O`) → ouverture immédiate.
2. **Mode racine (nouveau)** — on pointe un dossier **racine** contenant plusieurs audits → **liste plein écran**
   (comme iOS) → clic sur un audit → vue détail actuelle → bouton **« ‹ Audits »** pour revenir à la liste.

## Décisions d'UX (validées)
- **Navigation** : liste plein écran + bouton retour (transition nette, calquée iOS).
- **Détection d'un audit** : tout sous-dossier de la racine contenant `_manifest.json` **ou**
  `00_RESUME_EXECUTIF.md` (robuste, indépendant du préfixe `audit-`).

## Points d'ancrage
1. **`Sources/AuditEntry.swift`** (nouveau) — `struct AuditEntry: Identifiable, Sendable` côté macOS
   (mêmes champs qu'iOS `ios/Sources/AuditStoreIOS.swift:6`, non partagé entre cibles).
2. **`Sources/AuditStore.swift`** — nouveaux membres `audits: [AuditEntry]`, `browseMode: Bool`,
   `browseRoot: URL?` ; méthodes `openRootFolder()`, `loadRoot(_:)`, `backToList()`,
   `static discoverAudits(root:)` (FileManager natif, pas d'iCloud), `static loadEntry(dir:)`
   (slug sans présumer du préfixe `audit-`).
3. **`Sources/AuditListView.swift`** (nouveau) — liste plein écran des `store.audits`, ligne inspirée
   d'`AuditRowView` iOS (`ios/Sources/AuditListView.swift:129`) : titre, date, sources, profondeur, badge statut.
   En-tête : racine + bouton « Changer de dossier… ». Clic → `store.loadAuditDir(entry.dir)`.
4. **`Sources/ContentView.swift`** — routage 3 états : `auditDir != nil` → détail (+ bouton « ‹ Audits »
   si `browseMode`) ; `auditDir == nil && browseMode` → `AuditListView()` ; sinon → `EmptyStateView()`.
5. **`Sources/EmptyStateView.swift`** — 3e bouton « Ouvrir un dossier racine… » (`openRootFolder`).
6. **`Sources/AuditViewerApp.swift`** — commande menu « Ouvrir un dossier racine… » (`⇧⌘O`).

## Persistance / sandbox
- Réutiliser `KeychainStore.researchRoot` pour mémoriser la dernière racine.
- À vérifier au build : si la cible macOS est sandboxée, le `NSOpenPanel` sur la racine accorde l'accès
  security-scoped à toute la hiérarchie ; ajouter un bookmark seulement si nécessaire.

## Hors périmètre (inchangé)
Mode direct `⌘O`, exécution/annulation, diffs, export PDF/DOCX, carte/graphe, KPIs ; iOS/tvOS.

## Étapes
1. `AuditEntry.swift` → 2. `AuditStore` (état + découverte) → 3. `AuditListView.swift` →
4. `ContentView` (routage + retour) → 5. `EmptyStateView` (bouton) → 6. `AuditViewerApp` (menu) →
7. `swift build` + `./build.sh` + tests manuels.

