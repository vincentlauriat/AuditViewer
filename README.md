# SkillAuditReport

Dépôt de gestion du skill Claude Code **`audit-report`** — recherche exhaustive sur un sujet et génération d'un dossier d'audit complet (marché, concurrence, financier, technique, historique, futur, tarification), comme un cabinet de conseil stratégique.

## Contenu

```
skills/
  audit-report/
    SKILL.md        # Définition du skill (instructions d'exécution)
install.sh          # Installe/lie le skill dans ~/.claude/skills
```

## Le skill en bref

`/audit-report <sujet> [options]` produit un dossier `audit-{sujet}/` contenant un résumé exécutif, 7 dimensions d'analyse (historique, marché, technique, tarification, concurrence, financier, futur), un fact-check croisé, un rapport fusionné et des données structurées (`_data.json`).

Dimensions optionnelles : `--swot`, `--esg`, `--rh`. Modes d'exécution : `--mode parallel|sequential|solo`. Voir l'aide complète via `/audit-report --help`.

## Installation

Ce dépôt est la **source de vérité** du skill. Sur la machine de développement, `~/.claude/skills/audit-report` est un lien symbolique vers `skills/audit-report/` de ce dépôt : éditer le `SKILL.md` ici met à jour le skill instantanément.

Pour installer sur une autre machine :

```bash
git clone git@github.com:vincentlauriat/SkillAuditReport.git
cd SkillAuditReport
./install.sh            # crée le symlink ~/.claude/skills/audit-report
./install.sh --copy     # copie le skill au lieu de créer un lien
```

## Développement

1. Éditer `skills/audit-report/SKILL.md`.
2. Tester dans Claude Code : `/audit-report Notion --depth quick`.
3. Commiter et pousser.

## Licence

Voir [LICENSE](LICENSE).
