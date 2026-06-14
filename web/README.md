# AuditViewer — Visualiseur web

> **Nouveau ici ?** Ce dossier est l'**interface web** d'AuditViewer : une application qui tourne dans votre navigateur pour **lancer des audits, suivre leur progression en direct et lire les rapports** — sans jamais toucher au terminal après l'installation. Si vous découvrez le projet, commencez plutôt par la **[documentation générale](../docs/README.md)** ([🇬🇧 README](../README.md) · [🇫🇷 README](../README.fr.md)) : elle explique ce qu'est un audit et comment l'obtenir.
>
> Démarrage express : `npm install` puis `npm run dev`, et ouvrez <http://localhost:5173>. La suite de ce document est une **référence technique** pour les développeurs.

---

Interface de **visualisation et de pilotage** des audits produits par le skill
`audit-report` (contrat machine v1).

> V1 = visualisation seule (lecture d'un dossier d'audit, suivi live via SSE).
> V2 = pilotage : lancer un audit depuis l'UI (runner headless `claude -p`),
> répondre aux questions, et contrôler le runner (pause / reprise / annulation),
> plus un **répertoire des audits configurable** depuis l'UI.

## Architecture

- **Backend** Node + Express (`server/`) — scanne `AUDITS_ROOT`, sert `_manifest.json` / `_data.json`
  / `_sources.json` / les `.md`, et **tail `_events.jsonl` en SSE** (suivi temps réel).
- **Frontend** Vite + React (`web/`) — sidebar des audits, header + barre de progression,
  onglets Synthèse (KPIs + résumé), Dimensions, Sources, Timeline (events live), Rapport.
- **Types partagés** (`shared/contract.ts`) — calqués sur le contrat décrit dans `../PLAN.md`.

## Démarrer

```bash
cd web
npm install
npm run dev          # backend :3001 + frontend :5173 (proxy /api)
```

Puis ouvrir http://localhost:5173. Par défaut, `AUDITS_ROOT` pointe sur `~/Documents/Research`.

Pointer ailleurs (override par variable d'env, prioritaire) :

```bash
AUDITS_ROOT=/chemin/vers/dossier-parent-daudits npm run dev:server
```

## V2 — Répertoire des audits configurable

Un **seul** dossier racine (`auditsRoot`) sert à la fois à la **lecture**
(scan/affichage) et à l'**écriture** (un nouvel audit est créé dans
`<auditsRoot>/audit-<slug>`).

Résolution par ordre de priorité :

1. variable d'env `AUDITS_ROOT` (si définie, **prioritaire et non modifiable** depuis l'UI) ;
2. fichier de config local `.auditviewer.config.json` (`{ "auditsRoot": "/chemin/absolu" }`, gitignore) ;
3. défaut : `~/Documents/Research`.

Endpoints :

- `GET /api/config` → `{ auditsRoot, source: "env"|"file"|"default", editable }`.
- `PUT /api/config` `{ auditsRoot }` → résout en absolu, crée le dossier
  (mkdir récursif), vérifie l'accès en écriture, persiste atomiquement et
  applique à chaud. Refuse avec **409** si `AUDITS_ROOT` est imposé par l'env.

Côté UI : bouton **⚙ Réglages** en bas de la sidebar. Si imposé par l'env, le
champ est en lecture seule avec la mention « imposé par AUDITS_ROOT ».

## V2 — Pilotage (runner `claude -p`)

Le backend lance le skill en sous-process headless :

```
claude -p "/audit-report <SUBJECT> [flags] --app-mode --output <DIR>"
```

`<DIR>` = `<auditsRoot>/audit-<slug>`, où `<slug>` est calculé de façon
**déterministe** (réplique TS de la règle Python du skill : NFKD → ASCII →
non-alphanum `-` → trim/compression → minuscules). Le binaire est surchargeable
via la variable d'env **`CLAUDE_BIN`** (défaut `claude`). Un échec de spawn
renvoie une erreur HTTP claire, sans crash du serveur.

Endpoints de pilotage :

- `POST /api/audits/launch` `{subject, depth?, mode?, lang?, options?[]}` →
  crée le dossier, spawn le runner (detached, stdout/stderr → `<DIR>/_runner.log`),
  mémorise le PID. Renvoie `{slug, pid}`. **409** si le slug est déjà en cours.
- `POST /api/audit/:slug/answer` `{value, id?}` → écrit `_answer.json`
  **atomiquement** (`.tmp` + rename), format `{v:1, id, value}`.
- `POST /api/audit/:slug/control` `{action, dimension?}` → écrit `_control.json`
  atomiquement `{v:1, action, dimension?}`. Pour `cancel`, tue aussi le process.
- `GET /api/audit/:slug/question` → contenu de `_question.json`, ou `{question:null}`.
- `GET /api/audit/:slug/status` → `{running, pid?}`.

Côté UI : bouton **« + Nouvel audit »** (formulaire sujet/depth/mode/options
SWOT·ESG·RH) → lance et bascule sur la timeline live ; **modale de question**
déclenchée par l'event SSE `question` (disparaît à l'event `answer`) ; **barre
de contrôle** (Pause / Reprendre / Annuler) quand un audit tourne.

## Vérifications

```bash
npm run typecheck    # tsc front + serveur
npm run build        # build de production
```

### Test du câblage sans audit réel (fake runner)

Le pilotage se teste de bout en bout **sans appel réseau coûteux** en pointant
`CLAUDE_BIN` sur un faux runner shell qui écrit les helpers et émet quelques
events. Exemple de runner (parse `--output DIR`, émet `audit_start`, pose une
`question`, attend `_answer.json`, émet `answer` puis `audit_complete` + écrit
`_manifest.json`) :

```bash
ROOT=$(mktemp -d)
AUDITS_ROOT="$ROOT" CLAUDE_BIN=/chemin/fake-claude.sh PORT=3097 \
  ./node_modules/.bin/tsx server/index.ts &

# 1) launch -> {slug, pid}
curl -s -X POST localhost:3097/api/audits/launch \
  -H 'Content-Type: application/json' -d '{"subject":"Test","depth":"quick"}'
# 2) la question apparaît
curl -s localhost:3097/api/audit/audit-test/question
# 3) on répond (écrit _answer.json atomiquement)
curl -s -X POST localhost:3097/api/audit/audit-test/answer \
  -H 'Content-Type: application/json' -d '{"value":"update","id":"q1"}'
# 4) SSE diffuse audit_start/question/answer/audit_complete ;
#    status passe à {"running":false} et l'audit apparaît dans /api/audits.
```

Le pilotage `pause`/`cancel` se vérifie de la même façon : `POST /control`
écrit `_control.json` (atomique) et, pour `cancel`, tue le groupe de processus
du runner.
