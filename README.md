# SkillAuditReport

Dépôt de gestion du skill **`audit-report`** — recherche exhaustive sur un sujet et génération d'un dossier d'audit complet (marché, concurrence, financier, technique, historique, futur, tarification), comme un cabinet de conseil stratégique.

Ce skill est compatible avec **Claude Code** et **Gemini Code Assist / Antigravity**.

![Audit-Report : votre partenaire de conseil stratégique IA](images/Audit-Report__AI_Strategic_Consulting.png)

## Contenu

```
skills/
  audit-report/
    SKILL.md        # Définition du skill (instructions d'exécution)
install.sh          # Installe/lie le skill pour Claude ou Gemini
```

## Le skill en bref

`/audit-report <sujet> [options]` produit un dossier `audit-{sujet}/` contenant un résumé exécutif, 7 dimensions d'analyse (historique, marché, technique, tarification, concurrence, financier, futur), un fact-check croisé, un rapport fusionné et des données structurées (`_data.json`).

*   **Claude Code :** Supporte l'orchestration multi-agents en `--mode parallel` ou `--mode sequential` (via l'outil `Agent`).
*   **Gemini / Antigravity :** S'exécute de manière optimale en `--mode solo` (toutes les recherches et écritures sont réalisées séquentiellement dans le contexte principal de l'agent, tirant parti de son très grand contexte).

Dimensions optionnelles : `--swot`, `--esg`, `--rh`. Voir l'aide complète via `/audit-report --help`.

## Installation

Ce dépôt est la **source de vérité** du skill. Sur la machine de développement, un lien symbolique est créé vers ce dépôt : éditer le `SKILL.md` ici met à jour le skill instantanément.

### Pour Claude Code

```bash
./install.sh            # Crée le symlink dans ~/.claude/skills/audit-report
./install.sh --copy     # Copie le skill au lieu de créer un lien
```

### Pour Gemini Code Assist / Antigravity

```bash
./install.sh --gemini   # Crée le symlink dans ~/.gemini/config/skills/audit-report
./install.sh --gemini --copy # Copie le skill au lieu de créer un lien
```

## Développement

1. Éditer `skills/audit-report/SKILL.md`.
2. Tester dans votre environnement (Claude : `/audit-report Notion --depth quick` ; Gemini : demander l'exécution du skill `audit-report`).
3. Commiter et pousser.

## Contrat Machine V1

Le skill implémente un **contrat machine déterministe et versionné** : flux d'événements en temps réel (`_events.jsonl`), canal de pilotage bidirectionnel (`_control.json`), cycle question/réponse durci et sorties structurées canoniques (`_manifest.json`, `_data.json`, `_sources.json`).

![SkillAuditReport — Contrat Machine V1](images/SkillAuditReport___Contrat_Machine_V1.png)

Ce contrat garantit que l'AuditViewer (ou tout autre outil de pilotage) peut observer et contrôler le skill sans ambiguïté. Voir [ARCHITECTURE.md](ARCHITECTURE.md) pour le détail des flux.

## Licence

Voir [LICENSE](LICENSE).

