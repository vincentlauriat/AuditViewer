# Architecture — Contrat Machine V1

Le skill `audit-report` communique avec son environnement (AuditViewer, outils de pilotage) via un **contrat machine v1 déterministe et versionné**. Tous les artefacts JSON portent `"v": 1`.

![Schéma du Contrat Machine V1](images/Schéma_du_contrat_machine_v1.png)

## Flux de pilotage en temps réel

### `_events.jsonl` — flux d'événements (append-only)

Le skill émet un flux d'événements JSON ligne par ligne, permettant à l'UI de suivre la progression en temps réel sans polling actif.

Champs communs : `v` (=1), `ts` (ISO8601 UTC), `type`.

| Type | Champs spécifiques | Description |
|---|---|---|
| `audit_start` | `subject, depth, mode, options, output_dir` | Démarrage de l'audit |
| `phase_start` / `phase_done` | `phase, label` | Phases : `recon`, `research`, `factcheck`, `swot`, `summary`, `assembly`, `finalize` |
| `dimension_start` / `dimension_done` | `dimension, label, status, sources_count?, summary?` | Dimensions : `historique`, `marche`, `technique`, `tarification`, `concurrence`, `financier`, `futur`, `esg`, `rh` |
| `progress` | `done, total, pct` | Avancement global |
| `question` | `id` | Une question attend dans `_question.json` |
| `answer` | `id, value` | Réponse consommée |
| `file_written` | `file` | Fichier de sortie produit |
| `error` | `phase?, dimension?, message` | Erreur non-bloquante |
| `audit_complete` | `files_count, sources_count, status` | Fin normale |
| `audit_canceled` | `reason` | Annulation propre |

> En `--mode parallel`, le contexte principal émet `dimension_start`/`dimension_done` autour de chaque dispatch d'agent — les sous-agents restent muets, l'UI n'est jamais aveugle.

### `_control.json` — canal UI → skill (pilotage bidirectionnel)

L'UI écrit `{v, action, dimension?}`. Le skill relit ce fichier aux **points de contrôle** (après chaque dimension, avant assemblage) puis le **consomme** (supprime).

| Action | Comportement |
|---|---|
| `cancel` | Arrêt propre → `audit_canceled` + manifest partiel `status: canceled` |
| `pause` | Boucle d'attente bornée (30 min par défaut) |
| `resume` | Sortie de la boucle de pause |
| `rerun` | Rejoue une dimension spécifique (`dimension` requis) |

### Cycle question/réponse durci

1. Skill écrit `_question.json` `{v, id, text, options}` + émet événement `question`
2. UI écrit `_answer.json` **atomiquement** (écriture tmp + rename)
3. Skill poll, lit, **supprime `_answer.json` ET `_question.json`**, émet `answer`
4. **Timeout** : 30 min par défaut → expiration = `cancel` + `error{message:"timeout"}`

## Sorties structurées canoniques

### `_manifest.json` — index canonique final

```json
{
  "v": 1,
  "subject": "...",
  "subject_type": "...",
  "slug": "...",
  "output_dir": "...",
  "audit_date": "...",
  "depth": "standard",
  "mode": "parallel",
  "options": {},
  "status": "complete | partial | canceled",
  "dimensions": [{ "key": "...", "file": "...", "status": "...", "sources_count": 0 }],
  "files": [{ "name": "...", "kind": "..." }],
  "sources_count": 0,
  "data_file": "_data.json",
  "sources_file": "_sources.json",
  "report_file": "RAPPORT_COMPLET.md"
}
```

### `_sources.json` — bibliographie structurée

```json
{
  "v": 1,
  "sources": [{ "id": "...", "url": "...", "title": "...", "tag": "...", "date": "...", "dimensions": [], "stale": false }]
}
```

### `_data.json` — KPIs et données structurées (schéma générique)

```json
{
  "v": 1,
  "subject": "...",
  "subject_type": "...",
  "as_of": "...",
  "kpis": [{ "key": "...", "label": "...", "value": "...", "unit": "...", "period": "...", "source_id": "...", "estimated": false }],
  "financials": {},
  "market": {}
}
```

## Compatibilité multi-plateforme

| Plateforme | Mode recommandé | Mécanisme |
|---|---|---|
| **Claude Code** | `parallel` ou `sequential` | Outil `Agent` — orchestration multi-agents |
| **Gemini / Antigravity** | `solo` | Contexte unique — grand contexte natif |

Le contrat machine est identique dans les deux cas ; seul le moteur d'exécution interne diffère.
