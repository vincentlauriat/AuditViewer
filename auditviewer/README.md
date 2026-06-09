# AuditViewer

Interface de **visualisation** des audits produits par le skill `audit-report` (contrat machine v1).

> V1 = visualisation seule (lecture d'un dossier d'audit, suivi live via SSE).
> Le **pilotage** (lancer/annuler un audit depuis l'UI via un runner headless) est prévu en V2.

## Architecture

- **Backend** Node + Express (`server/`) — scanne `AUDITS_ROOT`, sert `_manifest.json` / `_data.json`
  / `_sources.json` / les `.md`, et **tail `_events.jsonl` en SSE** (suivi temps réel).
- **Frontend** Vite + React (`web/`) — sidebar des audits, header + barre de progression,
  onglets Synthèse (KPIs + résumé), Dimensions, Sources, Timeline (events live), Rapport.
- **Types partagés** (`shared/contract.ts`) — calqués sur le contrat décrit dans `../PLAN.md`.

## Démarrer

```bash
cd auditviewer
npm install
npm run dev          # backend :3001 + frontend :5173 (proxy /api)
```

Puis ouvrir http://localhost:5173. Par défaut, `AUDITS_ROOT` pointe sur `../viewer-fixtures/`
(contient l'audit Notion de référence).

Pointer ailleurs :

```bash
AUDITS_ROOT=/chemin/vers/dossier-parent-daudits npm run dev:server
```

## Vérifications

```bash
npm run typecheck    # tsc front + serveur
npm run build        # build de production
```
