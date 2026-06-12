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

## Hors périmètre (Viewer, étape suivante)
Runner headless (`claude -p` vs Agent SDK), rendu markdown, UI de pilotage.
Décision pressentie : Agent SDK pour le streaming, `_events.jsonl` + `_control.json` en canal fichier de secours.

