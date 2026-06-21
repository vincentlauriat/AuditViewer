---
name: auditv
description: "Lit et explore en mode terminal (CLI) les dossiers d'audit générés par /audit-report : liste de tous les audits, fiche synthèse (KPIs), rendu markdown coloré de n'importe quelle dimension (00–10, ESG/SWOT/RH inclus), et recherche plein-texte. Pendant CLI léger de l'application AuditViewer et du TUI audit-view."
trigger: /auditv
allowed-tools:
  - Bash
  - Read
---

# /auditv

Lecteur **CLI** des dossiers d'audit produits par `/audit-report`. C'est le pendant terminal léger de
l'application **AuditViewer** (GUI macOS) : il lit les mêmes dossiers `audit-{slug}/` et leurs
artefacts machine (`_manifest.json`, `_data.json`, fichiers `NN_*.md`).

> **Complémentaire du TUI `audit-view`** (`~/.local/bin/audit-view`) : celui-ci ouvre **un** audit en
> plein écran (navigation immersive section par section, `n` = lancer un nouvel audit). `auditv` couvre
> ce que le TUI ne fait pas : **vue d'ensemble du parc, recherche transverse, fiche KPIs, toutes les
> sections (ESG/SWOT/RH incluses), et sortie pipeable**. Les deux cohabitent.

Le moteur est un script Python **sans aucune dépendance** (`auditv.py`, stdlib uniquement) : il
fonctionne aussi bien lancé directement au terminal que via ce skill dans une session Claude. Si
`glow` ou `bat` sont installés, ils sont utilisés automatiquement pour le rendu ; sinon le script
applique son propre rendu ANSI (titres, tableaux, couleurs des tags `[Officielle]`/`[Analyste]`/`[Presse]`, ⚠️).

## Commandes

```bash
auditv                       # liste tous les audits du répertoire (slug, sujet, type, date, sources, état)
auditv <sujet|slug>          # fiche synthèse : en-tête + KPIs (_data.json) + verdict + dimensions dispo
auditv <slug> <dimension>    # rendu markdown d'une dimension
auditv --search <terme>      # recherche plein-texte dans tous les audits
auditv --search <terme> <slug>   # recherche limitée à un audit
```

`<dimension>` accepte :
- un **numéro** : `00`–`10` (`00`=résumé, `01`=historique, `02`=marché, `03`=technique,
  `04`=tarification, `05`=concurrence, `06`=financier, `07`=futur, `08`=ESG, `09`=SWOT, `10`=RH) ;
- un **nom** (insensible casse/accents) : `marche`, `technique`, `swot`, `futur`, `rh`… ;
- un **mot-clé spécial** : `report` (RAPPORT_COMPLET), `changelog`, `factcheck`.

La résolution du sujet est **tolérante** : `auditv databr` ouvre l'audit `databricks`,
`auditv "Tesla Model Y"` ouvre `tesla-model-y`. En cas d'ambiguïté, les candidats sont listés.

### Options

- `--root <chemin>` : dossier contenant les `audit-*/` (défaut : répertoire courant, fallback `~/Documents/Research`).
- `--raw` : markdown brut, sans couleurs ni mise en forme (idéal pour piper / copier).
- `--internal` : forcer le rendu ANSI interne même si `glow`/`bat` sont présents.
- `--no-color` : désactiver les couleurs (auto-désactivées hors terminal interactif).

### Exemples

```bash
auditv                       # vue d'ensemble
auditv mlx                   # fiche de l'audit MLX
auditv mlx 05                # dimension Concurrence, rendue en couleur
auditv mlx swot              # idem via alias (= 09)
auditv mlx report | less -R  # rapport complet dans un pager
auditv --search "Core AI"    # où "Core AI" apparaît, tous audits confondus
auditv --search gemini mlx   # recherche limitée à l'audit MLX
```

## Installation (usage 100 % terminal autonome)

Pour appeler `auditv` directement depuis n'importe quel terminal, ajouter un alias au shell
(adapter le chemin si le repo AuditViewer est ailleurs) :

```bash
echo "alias auditv='python3 \"$HOME/Documents/GitHub/AuditViewer/skills/auditv/auditv.py\"'" >> ~/.zshrc
source ~/.zshrc
```

Le script requiert seulement **Python 3.8+** (aucun `pip install`). Lancé sans alias :

```bash
python3 ~/Documents/GitHub/AuditViewer/skills/auditv/auditv.py mlx
```

> Note : `auditv` (ce CLI) et `audit-view` (le TUI) sont deux commandes distinctes et indépendantes.

---

## Instructions d'exécution (quand invoqué via `/auditv` dans Claude)

Lorsque l'utilisateur invoque `/auditv [args]` :

1. Localiser le script : il se trouve dans **le répertoire de base de ce skill**, sous le nom
   `auditv.py` (chemin canonique : `~/Documents/GitHub/AuditViewer/skills/auditv/auditv.py`).
2. Exécuter via **Bash** :
   ```bash
   python3 "<base_dir>/auditv.py" --root "$(pwd)" [args]
   ```
   - Transmettre les arguments de l'utilisateur tels quels.
   - Passer `--root "$(pwd)"` pour que les audits du répertoire de travail courant soient trouvés
     (le script retombe sur `~/Documents/Research` si le cwd ne contient pas d'audits).
   - Ne pas ajouter `--no-color` : la couleur est gérée automatiquement par le script (désactivée
     hors TTY, donc la sortie reste propre dans la session).
3. Afficher la sortie du script à l'utilisateur. Si l'utilisateur pose ensuite une **question de
   fond** sur le contenu d'un audit (synthèse, comparaison, « que dit la dimension X »), lire le
   fichier concerné avec **Read** (ou `auditv <slug> <dim> --raw`) et répondre — le script sert
   à *afficher*, Claude sert à *raisonner* sur le contenu.
4. Si aucun argument n'est fourni, lancer la **liste** (`python3 ".../auditv.py" --root "$(pwd)"`).

> Le skill ne modifie jamais les dossiers d'audit : il est strictement en lecture seule.
