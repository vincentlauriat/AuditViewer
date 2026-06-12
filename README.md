# AuditViewer — Mono-repo

Ce dépôt regroupe trois projets autour du skill **`audit-report`** :

| Dossier | Rôle |
|---|---|
| `skills/audit-report/` | Skill d'audit IA (Claude Code / Gemini) |
| `web/` | Interface web de visualisation et de pilotage (Node + React) |
| `mac/` | App macOS native (SwiftUI) |

Les audits produits par le skill suivent le **contrat machine v1** (`_events.jsonl`, `_manifest.json`, `_data.json`, `_sources.json`) — `web/` et `mac/` lisent ce contrat.

![Audit-Report : votre partenaire de conseil stratégique IA](images/Audit-Report__AI_Strategic_Consulting.png)

---

## 1 — Skill `audit-report`

`/audit-report <sujet> [options]` produit un dossier `audit-{sujet}/` avec résumé exécutif, 7 dimensions d'analyse, fact-check et données structurées.

```bash
./install.sh            # symlink dans ~/.claude/skills/audit-report
./install.sh --gemini   # symlink dans ~/.gemini/config/skills/audit-report
./install.sh --copy     # copie au lieu de lien
```

Voir [`skills/audit-report/SKILL.md`](skills/audit-report/SKILL.md) pour la référence complète.

## 2 — Viewer web (`web/`)

Interface de visualisation et de pilotage des audits.

```bash
cd web
npm install
npm run dev    # backend :3001 + frontend :5173
```

Pour les fixtures de dev incluses dans ce dépôt :

```bash
AUDITS_ROOT=../viewer-fixtures npm run dev
```

Voir [`web/README.md`](web/README.md) pour les détails (V2 pilotage, endpoints, fake runner…).

## 3 — App macOS (`mac/`)

Client natif SwiftUI (macOS 15+) qui lit les mêmes dossiers d'audit.

```bash
cd mac
swift build              # compilation rapide
./build.sh               # build complet (copie les bundles web)
open build/AuditViewer.app
```

Voir [`mac/README.md`](mac/README.md) et [`mac/ARCHITECTURE.md`](mac/ARCHITECTURE.md).

---

## Contrat Machine V1

Le skill implémente un contrat déterministe et versionné : flux d'événements temps réel, canal de pilotage bidirectionnel, cycle question/réponse et sorties structurées canoniques.

![SkillAuditReport — Contrat Machine V1](images/SkillAuditReport___Contrat_Machine_V1.png)

Voir [ARCHITECTURE.md](ARCHITECTURE.md) pour le détail des flux.

## Fixtures de développement

`viewer-fixtures/` contient l'audit Notion de référence (contrat machine v1 complet), utilisable immédiatement via `AUDITS_ROOT=../viewer-fixtures`.

## Licence

Voir [LICENSE](LICENSE).
