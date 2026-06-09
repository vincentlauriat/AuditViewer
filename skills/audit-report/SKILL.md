---
name: audit-report
description: "Recherche exhaustive sur un sujet et génération d'un dossier d'audit complet (marché, concurrence, financier, technique, historique, futur, tarifaire) — comme un cabinet conseil."
trigger: /audit-report
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - WebFetch
  - WebSearch
  - AskUserQuestion
  - Agent
  - Workflow
---

# /audit-report

Génère un dossier d'audit complet sur n'importe quel sujet — entreprise, produit, technologie, marché, secteur — comme un cabinet de conseil stratégique.

```bash
/audit-report Apple
/audit-report "Tesla Model Y"
/audit-report "marché des LLM" --lang fr
/audit-report Notion --depth quick
/audit-report "OpenAI" --depth full --mode solo
/audit-report "Secteur fintech France"
```

## Ce que produit ce skill

Un dossier `audit-{sujet}/` contenant :

| Fichier | Contenu |
|---|---|
| `00_RESUME_EXECUTIF.md` | Synthèse 1 page — décisions clés, chiffres-clés, verdict |
| `01_HISTORIQUE.md` | Genèse, évolution, jalons, pivots, incidents majeurs |
| `02_MARCHE.md` | TAM/SAM/SOM, tendances, géographie, réglementation |
| `03_TECHNIQUE.md` | Architecture, stack, produit, fonctionnalités, différenciateurs |
| `04_TARIFICATION.md` | Modèles de prix, tiers, comparaison sectorielle, évolution |
| `05_CONCURRENCE.md` | Mapping concurrentiel, parts de marché, positionnement, SWOT |
| `06_FINANCIER.md` | Revenus, financement, valorisation, métriques clés, burn rate |
| `07_FUTUR.md` | Roadmap, signaux faibles, risques, opportunités, scénarios |
| `RAPPORT_COMPLET.md` | Rapport fusionné, paginé, prêt à distribuer |
| `BRIEF.md` | *(si `--brief`)* Synthèse 1 page — 5 faits, 3 forces, 3 risques, verdict |
| `08_ESG.md` | *(si `--esg`)* Bilan carbone, objectifs net zéro, notations ESG, controverses |
| `09_SWOT.md` | *(si `--swot`)* Matrice SWOT complète avec implications stratégiques |
| `10_RH.md` | *(si `--rh`)* Effectifs, culture, Glassdoor, recrutements, organisation |
| `_data.json` | Chiffres clés structurés (`kpis[]` générique + sections optionnelles) — lu par l'UI |
| `_sources.json` | Index structuré des sources (URL, tag, date, fraîcheur) — lu par l'UI |
| `_manifest.json` | Index canonique des artefacts produits + statut — référence pour l'AuditViewer |
| `CHANGELOG.md` | *(mode mise à jour)* Ce qui a changé depuis la version précédente |

**Artefacts du contrat machine** *(si `--app-mode`)* : `_events.jsonl` (flux d'événements versionné),
`_control.json` (pilotage UI → skill : cancel/pause/rerun), `_question.json`/`_answer.json` (dialogue),
`_emit.py`/`_ctl.py`/`_ask.py` (helpers). Voir « Mode --app-mode : contrat machine v1 ».

## Options

- `--depth quick` : recherche accélérée, ~10 sources, rapport condensé
- `--depth full` : recherche exhaustive (défaut), ~30+ sources, rapport complet
- `--lang fr|en` : langue du rapport (défaut : fr)
- `--output <path>` : dossier de sortie (défaut : `./audit-{sujet}/`)
- `--focus <aspect>` : approfondir un aspect (ex: `--focus financier`)
- `--verbose` : afficher le détail de chaque étape — requêtes lancées, sources retenues, résultats intermédiaires
- `--mode parallel` : lancer tous les agents de recherche en parallèle (défaut)
- `--mode sequential` : lancer les agents un par un, avec résumé intermédiaire entre chaque
- `--mode solo` : aucun sous-agent — le skill effectue lui-même toutes les recherches et écritures en séquence, dans un seul contexte (meilleure cohérence des synthèses, idéal pour les audits où les dimensions se croisent)
- `--swot` : générer une analyse SWOT dédiée (`09_SWOT.md`) après la recherche par dimension — synthèse croisée Forces / Faiblesses / Opportunités / Menaces avec implications stratégiques
- `--brief` : produit uniquement un `BRIEF.md` d'une page (5 faits, 3 forces, 3 risques, verdict 2 lignes) — skip les étapes 3-4
- `--esg` : ajoute une dimension ESG/Durabilité (`08_ESG.md`) après les 7 dimensions standard
- `--rh` : ajoute une dimension RH/Culture (`10_RH.md`) (Glassdoor, LinkedIn, culture, recrutements)
- `--watch` : inclut une section "Sources à surveiller" dans le rapport (5-8 URLs à bookmarker)
- `--app-mode` : mode intégration application — émet des événements JSON dans `_events.jsonl` et gère les questions via `_question.json` / `_answer.json` au lieu de `AskUserQuestion`
- `--help` : afficher la documentation complète du skill et stopper

---

## Instructions d'exécution

### Mode --app-mode : contrat machine v1

Quand `APP_MODE=true`, le skill expose un **contrat machine versionné** (`"v": 1`) permettant à
une application (AuditViewer) d'**observer** et de **piloter** l'audit via des fichiers dans `$OUTPUT_DIR`.
Tous les artefacts JSON portent le champ `"v": 1`.

**Spécification de référence** : `PLAN.md` à la racine du dépôt du skill décrit chaque artefact.

#### Installation des helpers (une seule fois, au tout début si APP_MODE)

Pour garantir une émission **fiable** (robuste aux apostrophes, accents, sauts de ligne), écrire trois
helpers Python dans `$OUTPUT_DIR` via le tool `Write`, puis les appeler partout au lieu d'interpoler du JSON.

`$OUTPUT_DIR/_emit.py` — émet un événement (type + paires `--clé valeur` en argv) :
```python
import sys, json, os, datetime
out = os.environ.get("AUDIT_OUT") or os.path.dirname(os.path.abspath(__file__))
a = sys.argv[1:]
ev = {"v": 1,
      "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
      "type": a[0] if a else "unknown"}
i = 1
while i < len(a):
    ev[a[i].lstrip("-")] = a[i + 1] if i + 1 < len(a) else ""
    i += 2
with open(os.path.join(out, "_events.jsonl"), "a", encoding="utf-8") as f:
    f.write(json.dumps(ev, ensure_ascii=False) + "\n")
```

`$OUTPUT_DIR/_ctl.py` — consomme une commande de pilotage si présente (imprime l'action ou rien) :
```python
import sys, json, os
out = os.environ.get("AUDIT_OUT") or os.path.dirname(os.path.abspath(__file__))
p = os.path.join(out, "_control.json")
if os.path.exists(p):
    try:
        c = json.load(open(p, encoding="utf-8"))
    except Exception:
        c = {}
    os.remove(p)  # consommé
    act = c.get("action", "")
    if act:
        print(act + ((":" + c["dimension"]) if c.get("dimension") else ""))
```

`$OUTPUT_DIR/_ask.py` — écrit une question, attend une réponse atomique, applique un timeout :
```python
import sys, json, os, time
out = os.environ.get("AUDIT_OUT") or os.path.dirname(os.path.abspath(__file__))
qid, text, opts_csv = sys.argv[1], sys.argv[2], sys.argv[3]
timeout = int(sys.argv[4]) if len(sys.argv) > 4 else 1800  # 30 min
options = []
for tok in opts_csv.split("|"):
    val, _, lab = tok.partition("=")
    options.append({"value": val, "label": lab or val})
q = {"v": 1, "id": qid, "text": text, "options": options}
qp, ap = os.path.join(out, "_question.json"), os.path.join(out, "_answer.json")
json.dump(q, open(qp, "w", encoding="utf-8"), ensure_ascii=False)
deadline = time.time() + timeout
while time.time() < deadline:
    if os.path.exists(ap):
        try:
            ans = json.load(open(ap, encoding="utf-8"))
        except Exception:
            time.sleep(0.3); continue  # écriture partielle, on réessaie
        os.remove(ap)
        if os.path.exists(qp):
            os.remove(qp)  # question consommée
        print(ans.get("value", ""))
        sys.exit(0)
    time.sleep(0.5)
# timeout → on retire la question et on signale l'expiration
if os.path.exists(qp):
    os.remove(qp)
print("__timeout__")
```

Définir `AUDIT_OUT` pour tous les appels : `export AUDIT_OUT="$OUTPUT_DIR"`.

#### Événements `_events.jsonl` (append-only, une ligne JSON par event)

Émettre via `python3 "$OUTPUT_DIR/_emit.py" <type> [--clé valeur ...]`. Types :
- `audit_start` `--subject … --depth … --mode … --options … --output_dir …`
- `phase_start` / `phase_done` `--phase <recon|research|factcheck|swot|summary|assembly|finalize> --label …`
- `dimension_start` / `dimension_done` `--dimension <clé> --label … [--status done --sources_count N --summary …]`
  (dimensions : `historique, marche, technique, tarification, concurrence, financier, futur, esg, rh`)
- `progress` `--done N --total M --pct P`
- `search` `--query …` *(si `--verbose`)*
- `source` `--url … --title … --tag <Officielle|Analyste|Presse>` *(si `--verbose`)*
- `file_written` `--file …`
- `question` `--id …` / `answer` `--id … --value …`
- `error` `[--phase …] [--dimension …] --message …`
- `audit_complete` `--files_count N --sources_count M --status complete`
- `audit_canceled` `--reason …`

**Émission par dimension (clé)** : en `--mode parallel`, le **contexte principal** émet
`dimension_start` juste avant de dispatcher chaque agent et `dimension_done` dès qu'un fichier de
dimension est écrit — les sous-agents restent muets, mais l'UI suit la progression en continu.
Émettre aussi un `progress` après chaque dimension terminée.

#### Pilotage `_control.json` (UI → skill)

Aux **points de contrôle** (après chaque dimension, et avant l'assemblage), lire une éventuelle commande :
```bash
ACTION=$(python3 "$OUTPUT_DIR/_ctl.py")
```
- `cancel` → émettre `audit_canceled --reason user`, écrire `_manifest.json` avec `status: canceled`, s'arrêter proprement.
- `pause` → boucler en relisant `_ctl.py` jusqu'à recevoir `resume` (ou `cancel`).
- `rerun:<dimension>` → relancer uniquement la dimension nommée (surtout utile en post-audit).

#### Questions interactives (remplace `AskUserQuestion` quand APP_MODE)

```bash
ANSWER=$(python3 "$OUTPUT_DIR/_ask.py" confirm_research \
  "Reconnaissance terminée — lancer la recherche approfondie ?" \
  "launch=Lancer la recherche|adjust=Ajuster le focus|cancel=Annuler")
python3 "$OUTPUT_DIR/_emit.py" answer --id confirm_research --value "$ANSWER"
```
La valeur (`launch`, `adjust`, `cancel`) détermine la suite. **`__timeout__`** (pas de réponse dans le
délai, défaut 30 min) est traité comme `cancel` : émettre `error --message timeout` puis arrêter proprement.

### Étape 0 — Parse des arguments

**Si `--help` est présent** : afficher immédiatement le bloc de documentation suivant, puis s'arrêter sans lancer d'audit.

```
╔══════════════════════════════════════════════════════════════════╗
║                     /audit-report — Aide                        ║
╚══════════════════════════════════════════════════════════════════╝

USAGE
  /audit-report <sujet> [options]

EXEMPLES
  /audit-report Apple
  /audit-report "Mistral AI" --depth full --swot --verbose
  /audit-report Voltalia --mode sequential --esg --rh --watch
  /audit-report "marché des LLM" --brief
  /audit-report Notion --depth quick --swot

FICHIERS PRODUITS
  00_RESUME_EXECUTIF.md   Synthèse 1 page — faits clés, verdict
  01_HISTORIQUE.md        Histoire, jalons, pivots, acquisitions
  02_MARCHE.md            TAM/SAM/SOM, tendances, réglementation
  03_TECHNIQUE.md         Stack, produit, brevets, différenciateurs
  04_TARIFICATION.md      Prix, modèles de monétisation, comparatifs
  05_CONCURRENCE.md       Mapping concurrentiel, parts de marché
  06_FINANCIER.md         Revenus, financement, valorisation, métriques
  07_FUTUR.md             Roadmap, signaux faibles, scénarios
  RAPPORT_COMPLET.md      Rapport fusionné prêt à distribuer
  _recon.json             Métadonnées de reconnaissance (conservé)
  _data.json              Chiffres clés structurés (machine-readable)
  _factcheck.md           Vérification croisée des données clés
  BRIEF.md       --brief  Synthèse 1 page (remplace le rapport complet)
  08_ESG.md      --esg    ESG, bilan carbone, gouvernance, controverses
  09_SWOT.md     --swot   Matrice SWOT + implications stratégiques
  10_RH.md       --rh     Effectifs, Glassdoor, culture, recrutements
  CHANGELOG.md   (auto)   Différences vs version précédente si mise à jour

OPTIONS
  --depth quick|full      Profondeur de recherche (défaut : full)
  --lang fr|en            Langue du rapport (défaut : fr)
  --output <path>         Dossier de sortie (défaut : ./audit-{sujet}/)
  --focus <aspect>        Approfondir un aspect spécifique
  --mode parallel|seq|solo  Agents en parallèle, séquentiels, ou sans sous-agents (défaut : parallel)
  --verbose               Détail de chaque étape et source consultée
  --swot                  Ajoute 09_SWOT.md avec implications stratégiques
  --brief                 Produit uniquement BRIEF.md (1 page)
  --esg                   Ajoute 08_ESG.md (durabilité, gouvernance)
  --rh                    Ajoute 10_RH.md (culture, Glassdoor, RH)
  --watch                 Section "Sources à surveiller" dans le rapport
  --help                  Afficher cette aide

QUALITÉ
  • Chaque donnée chiffrée est sourcée (URL + date)
  • Sources taguées [Officielle] / [Analyste] / [Presse]
  • Données > 1 an signalées ⚠️
  • Vérification croisée des 5-10 chiffres clés (_factcheck.md)
  • Sources dédupliquées dans l'index final
```

Extraire depuis les args :
- `SUBJECT` : le sujet à auditer (obligatoire)
- `DEPTH` : `quick` ou `full` (défaut : `full`)
- `LANG` : langue (défaut : `fr`)
- `OUTPUT_DIR` : dossier de sortie (défaut : `./audit-{sujet-slug}/`)
- `FOCUS` : aspect à approfondir (optionnel)
- `VERBOSE` : `true` si `--verbose` est présent (défaut : `false`)
- `MODE` : `parallel`, `sequential` ou `solo` (défaut : `parallel`)
- `SWOT` : `true` si `--swot` est présent (défaut : `false`)
- `BRIEF` : `true` si `--brief` est présent (défaut : `false`)
- `ESG` : `true` si `--esg` est présent (défaut : `false`)
- `RH` : `true` si `--rh` est présent (défaut : `false`)
- `WATCH` : `true` si `--watch` est présent (défaut : `false`)
- `APP_MODE` : `true` si `--app-mode` est présent (défaut : `false`)

**Conflits d'options** : `--brief` est **exclusif** des dimensions optionnelles. Si `--brief` est
combiné à `--swot`/`--esg`/`--rh`/`--watch`, ignorer ces dernières et avertir :
`⚠️ --brief ignore --swot/--esg/--rh (mode synthèse 1 page)`.

**Slug déterministe du dossier** : le dossier par défaut est `./audit-{slug}/`, où `{slug}` est calculé
de façon reproductible (l'UI doit pouvoir le prédire) — minuscules, accents retirés, tout caractère
non alphanumérique → `-`, tirets multiples compressés, tirets de bord supprimés :
```bash
SLUG=$(python3 -c "
import sys, unicodedata, re
s = unicodedata.normalize('NFKD', sys.argv[1]).encode('ascii','ignore').decode()
s = re.sub(r'[^a-zA-Z0-9]+','-', s).strip('-').lower()
print(s or 'sujet')
" "$SUBJECT")
OUTPUT_DIR="${OUTPUT_DIR:-./audit-$SLUG}"
```
Exemples : `Tesla Model Y` → `tesla-model-y`, `Société Générale` → `societe-generale`.

**Années dynamiques** : ne jamais coder les années en dur dans les requêtes. Calculer une fois :
```bash
YEAR=$(date +%Y); PREV=$((YEAR-1)); NEXT=$((YEAR+1))
```
Dans toutes les recherches ci-dessous, `{YEAR}` = année courante, `{PREV}` = année précédente,
`{NEXT}` = année suivante. (Les exemples écrits `2024 2025` sont illustratifs — utiliser `{PREV} {YEAR}`.)

**Détection du mode mise à jour** : si `OUTPUT_DIR` existe déjà et contient des fichiers `.md`, demander
quoi faire. **Si `APP_MODE=false`** : via `AskUserQuestion`. **Si `APP_MODE=true`** : via `_ask.py` :
```bash
UPD=$(python3 "$OUTPUT_DIR/_ask.py" update_mode \
  "Un audit existe déjà dans ce dossier — que faire ?" \
  "update=Mettre à jour|scratch=Repartir de zéro|cancel=Annuler")
```
- `update` / "Mettre à jour" → continuer, produire `CHANGELOG.md` en fin d'audit (différences clés)
- `scratch` / "Repartir de zéro" → vider `OUTPUT_DIR` et recommencer
- `cancel` / `__timeout__` → arrêter

Créer le dossier de sortie :
```bash
mkdir -p "$OUTPUT_DIR"
```

**Si `APP_MODE=true`** : créer les helpers `_emit.py`, `_ctl.py`, `_ask.py` dans `$OUTPUT_DIR`
(voir « Mode --app-mode »), exporter `AUDIT_OUT="$OUTPUT_DIR"`, puis émettre l'event de départ.
`OPTIONS_CSV` = liste des options activées séparées par des virgules (ex. `swot,esg`), ou **chaîne
vide** `""` si aucune — ne jamais écrire `none`. Le `_manifest.json` final portera la même info en
tableau JSON (`[]` si aucune), qui reste la source de vérité lue par l'UI.
```bash
OPTIONS_CSV=""   # ex. "swot,esg,rh" selon les flags activés ; vide si aucun
python3 "$OUTPUT_DIR/_emit.py" audit_start --subject "$SUBJECT" --depth "$DEPTH" \
  --mode "$MODE" --options "$OPTIONS_CSV" --output_dir "$OUTPUT_DIR"
```

Annoncer le sujet et le plan à l'utilisateur.

### Étape 1 — Reconnaissance initiale (obligatoire)

Avant de lancer les recherches parallèles, effectuer une reconnaissance rapide pour cadrer le sujet :

1. Lancer 2-3 recherches WebSearch larges pour comprendre le sujet :
   - `"{SUBJECT} overview company market"`
   - `"{SUBJECT} wikipedia history"`
   - `"{SUBJECT} latest news {PREV} {YEAR}"`

2. Lire les 2-3 sources les plus pertinentes pour établir :
   - Le type de sujet (entreprise, produit, secteur, technologie)
   - Les acteurs clés à couvrir
   - La langue principale des sources disponibles
   - Les mots-clés sectoriels à utiliser dans les recherches spécialisées

**Sources primaires en priorité** : si le sujet est une entreprise cotée, chercher en premier la page Relations Investisseurs (IR) officielle et les derniers rapports annuels / communiqués de résultats avant toute source secondaire.

**Indicateur de fraîcheur** : pour toute donnée chiffrée collectée, noter systématiquement la date de publication entre parenthèses — ex : `CA 2024 : 588 M€ *(communiqué mars 2025)*`. Si une donnée clé date de plus d'un an, la signaler explicitement avec `⚠️ donnée ancienne`.

3. Écrire un fichier `_recon.json` dans `$OUTPUT_DIR` avec :
```json
{
  "subject": "...",
  "subject_type": "company|product|market|technology|sector",
  "key_players": ["..."],
  "sector": "...",
  "search_keywords": ["..."],
  "language_sources": "en|fr|mixed"
}
```

**Gestion de l'ambiguïté — après reconnaissance uniquement** : ne jamais supposer qu'un sujet est inconnu ou mal orthographié avant d'avoir cherché. Si les résultats WebSearch identifient clairement le sujet (produit récent, entreprise, technologie), continuer sans poser de question. Ne demander une clarification via `AskUserQuestion` que si les recherches retournent **genuinement** plusieurs entités sans rapport portant le même nom (ex: "Jaguar" pourrait être la marque auto ou l'animal) ET qu'aucune n'est clairement dominante dans les résultats.

**Si `--verbose`** : après chaque WebSearch/WebFetch de l'étape 1, afficher les informations clés retenues et les URLs sélectionnées.

### Confirmation avant recherche approfondie

Une fois `_recon.json` écrit, **toujours** présenter les résultats de la reconnaissance et demander confirmation avant de lancer la recherche complète.

**Si `APP_MODE=false`** (mode Claude Code — défaut) : utiliser `AskUserQuestion` avec ce résumé :

```
Reconnaissance terminée pour : {SUBJECT}

• Type        : {subject_type}
• Secteur     : {sector}
• Acteurs clés: {key_players, séparés par virgule}
• Mots-clés   : {search_keywords}
• Langue srcs : {language_sources}
• Mode        : {MODE} — {DEPTH}

Souhaitez-vous lancer la recherche approfondie ?
```

Options à proposer : "Lancer la recherche" / "Ajuster le focus" / "Annuler"

**Si `APP_MODE=true`** (mode AuditViewer) : écrire `_question.json` et attendre `_answer.json` :

```bash
python3 -c "
import json
recon = json.load(open('$OUTPUT_DIR/_recon.json'))
q = {
  'id': 'confirm_research',
  'text': 'Reconnaissance terminée pour : ' + recon.get('subject','') + '\n\n• Type     : ' + recon.get('subject_type','') + '\n• Secteur  : ' + recon.get('sector','') + '\n• Acteurs  : ' + ', '.join(recon.get('key_players',[])[:4]) + '\n• Langue   : ' + recon.get('language_sources','') + '\n\nSouhaitez-vous lancer la recherche approfondie ?',
  'options': [
    {'value': 'launch', 'label': 'Lancer la recherche'},
    {'value': 'adjust', 'label': 'Ajuster le focus'},
    {'value': 'cancel', 'label': 'Annuler'}
  ]
}
with open('$OUTPUT_DIR/_question.json', 'w') as f: json.dump(q, f, ensure_ascii=False)
"
# Attendre la réponse (timeout 10 min)
ANSWER=$(python3 -c "
import json, time, os
for _ in range(1200):
    if os.path.exists('$OUTPUT_DIR/_answer.json'):
        ans = json.load(open('$OUTPUT_DIR/_answer.json'))
        os.remove('$OUTPUT_DIR/_answer.json')
        print(ans['value'])
        break
    time.sleep(0.5)
" 2>/dev/null)
```

Dans les deux modes, les valeurs possibles sont `launch` (ou "Lancer la recherche"), `adjust`, `cancel` :
- **"Lancer la recherche"** / `launch` → continuer à l'étape 2 telle quelle
- **"Ajuster le focus"** / `adjust` → poser une question de suivi pour préciser les dimensions à approfondir ou exclure, mettre à jour `_recon.json` en conséquence, puis continuer
- **"Annuler"** / `cancel` → arrêter ici, conserver `_recon.json`

### Étape 2 — Recherche par dimension

**Si `--depth quick`** : couvrir les 4 thèmes prioritaires (Historique, Marché, Concurrence, Financier).
**Si `--depth full`** (défaut) : couvrir les 7 dimensions.

Chaque agent reçoit le contexte de reconnaissance (`_recon.json`) et ses instructions spécifiques.

**Tagging des sources (tous les agents)** : pour chaque information citée, indiquer entre crochets la nature de la source :
- `[Officielle]` : communiqués de presse, rapports annuels, sites IR, documentation officielle
- `[Analyste]` : études de marché, notes d'analystes, cabinets de conseil
- `[Presse]` : articles de presse, blogs, médias spécialisés

Toujours inclure l'URL et la date de publication. Exemple : `CA 2024 : 588 M€ [Officielle](https://voltalia.com/ir) *(mars 2025)*`

**Si `--mode parallel`** (défaut) : lancer tous les agents en un seul message avec plusieurs appels `Agent` simultanés.

**Si `--mode sequential`** : lancer chaque agent séquentiellement. Avant chaque agent, annoncer la dimension en cours (ex: `▶ Recherche Historique…`). Après chaque agent, afficher un résumé d'une ligne (ex: `✓ Historique — 12 jalons identifiés, données de 1998 à 2025`) avant de passer au suivant.

**Si `--mode solo`** : ne pas spawner de sous-agents du tout. Le skill effectue lui-même, directement et en séquence, toutes les WebSearch/WebFetch et écritures de fichiers pour chaque dimension. Pour chaque dimension, annoncer `▶ [Dimension]…`, effectuer les recherches (voir instructions de l'agent correspondant ci-dessous — appliquer les mêmes requêtes et le même plan de contenu), écrire le fichier, puis afficher `✓ [Dimension] — résumé d'une ligne`. Les instructions des agents ci-dessous servent de guide de contenu ; en mode solo elles sont exécutées directement sans délégation.

**Si `--verbose`** (applicable à tous les modes) : avant chaque WebSearch ou WebFetch, afficher la requête en cours ; après chaque source consultée, noter le titre, l'URL et les 1-2 informations clés retenues. En mode solo, afficher également les données clés extraites à la fin de chaque dimension.

**Si `APP_MODE=true`** (tous les modes) : émettre les événements de dimension depuis le **contexte
principal** pour que l'UI suive la progression — y compris en `--mode parallel` où les sous-agents
restent muets. Pour chaque dimension de la liste retenue (`DEPTH`), dans l'ordre :
1. avant de dispatcher / commencer : `python3 "$OUTPUT_DIR/_emit.py" dimension_start --dimension <clé> --label "<Label>"`
2. dès que le fichier `NN_*.md` est écrit : `python3 "$OUTPUT_DIR/_emit.py" dimension_done --dimension <clé> --status done` puis émettre `file_written --file NN_*.md` et un `progress --done D --total T --pct P`.
3. **point de contrôle** : lire `ACTION=$(python3 "$OUTPUT_DIR/_ctl.py")` et traiter `cancel`/`pause`/`resume`/`rerun:<dim>` comme spécifié dans « Mode --app-mode ». En `--mode parallel`, vérifier le contrôle après chaque salve d'agents.

Clés de dimension : `historique, marche, technique, tarification, concurrence, financier, futur` (+ `esg`, `rh` si activés).

---

#### Agent HISTORIQUE

**Objectif** : Retracer l'histoire complète du sujet.

Recherches à effectuer :
- `"{SUBJECT} history founded timeline"`
- `"{SUBJECT} milestones pivots major events"`
- `"{SUBJECT} crisis scandal controversy"`
- `"{SUBJECT} acquisitions mergers partnerships"`

Produire `01_HISTORIQUE.md` avec :
- Frise chronologique des jalons majeurs (tableau markdown)
- Contexte de création / genèse
- Phases d'évolution (démarrage, croissance, maturité, crises)
- Pivots stratégiques notables
- Acquisitions / fusions / partenariats importants
- Incidents, controverses, scandales ayant marqué l'histoire
- Sources avec URLs

---

#### Agent MARCHE

**Objectif** : Analyser le marché dans lequel évolue le sujet.

Recherches à effectuer :
- `"{SUBJECT} market size TAM SAM {PREV} {YEAR}"`
- `"{SUBJECT} market trends growth forecast"`
- `"{SUBJECT} market geography regions"`
- `"{SUBJECT} industry regulation compliance"`
- `"{SUBJECT} market report analysts"`

Produire `02_MARCHE.md` avec :
- Taille du marché (TAM / SAM / SOM) avec sources chiffrées
- Taux de croissance (CAGR) et projections
- Segmentation géographique
- Segmentation par vertical / usage
- Tendances structurelles du marché
- Cadre réglementaire et contraintes légales
- Acteurs du marché et parts estimées
- Sources avec URLs et dates

---

#### Agent TECHNIQUE

**Objectif** : Décrire précisément ce qui est proposé sur le plan technique et produit.

Recherches à effectuer :
- `"{SUBJECT} technology stack architecture"`
- `"{SUBJECT} product features capabilities"`
- `"{SUBJECT} technical documentation how it works"`
- `"{SUBJECT} API integrations ecosystem"`
- `"{SUBJECT} patents R&D innovation"`

Produire `03_TECHNIQUE.md` avec :
- Description précise du produit / service / technologie
- Architecture technique (si applicable)
- Stack technologique
- Fonctionnalités principales et différenciateurs
- Intégrations et écosystème
- Propriété intellectuelle, brevets, R&D
- Points forts et points faibles techniques
- Sources avec URLs

---

#### Agent TARIFICATION

**Objectif** : Cartographier précisément les modèles de prix.

Recherches à effectuer :
- `"{SUBJECT} pricing plans tiers {PREV} {YEAR}"`
- `"{SUBJECT} pricing model freemium subscription"`
- `"{SUBJECT} price increase history"`
- `"{SUBJECT} pricing compared to competitors"`
- `"{SUBJECT} enterprise pricing contracts"`

Produire `04_TARIFICATION.md` avec :
- Tableau complet des offres / tiers actuels avec prix
- Modèle de monétisation (freemium, abonnement, usage, licence…)
- Historique des changements de prix
- Comparaison tarifaire avec les concurrents directs
- Offres enterprise / custom pricing
- Conditions contractuelles notables
- Rapport qualité/prix sectoriel
- Sources avec URLs et dates

---

#### Agent CONCURRENCE

**Objectif** : Cartographier l'environnement concurrentiel complet.

Recherches à effectuer :
- `"{SUBJECT} competitors alternatives {YEAR}"`
- `"{SUBJECT} market share vs competitors"`
- `"{SUBJECT} competitive advantage differentiation"`
- `"{SUBJECT} SWOT analysis"`
- `"{SUBJECT} vs {top_competitor} comparison"`

Produire `05_CONCURRENCE.md` avec :
- Tableau des concurrents directs et indirects avec positionnement
- Parts de marché estimées (avec sources)
- Matrice de positionnement (tableau forces/faiblesses vs concurrents)
- Analyse SWOT du sujet principal
- Avantages concurrentiels défendables
- Menaces compétitives émergentes
- Barrières à l'entrée du secteur
- Sources avec URLs

---

#### Agent FINANCIER

**Objectif** : Analyser la situation financière et les métriques clés.

Recherches à effectuer :
- `"{SUBJECT} revenue ARR MRR growth {PREV} {YEAR}"`
- `"{SUBJECT} funding valuation investors"`
- `"{SUBJECT} IPO financials annual report"`
- `"{SUBJECT} profitability EBITDA margin"`
- `"{SUBJECT} financial metrics KPI"`

Produire `06_FINANCIER.md` avec :
- Revenus (CA, ARR/MRR si SaaS) avec évolution annuelle
- Rentabilité (marge brute, EBITDA, résultat net)
- Historique des levées de fonds / valorisations
- Actionnariat et investisseurs clés
- Métriques sectorielles clés (NRR, churn, CAC, LTV…)
- Structure financière (dette, trésorerie)
- Note : indiquer clairement les données estimées vs officielles
- Sources avec URLs et dates

---

#### Agent FUTUR

**Objectif** : Projeter les perspectives d'évolution.

Recherches à effectuer :
- `"{SUBJECT} roadmap future plans {YEAR} {NEXT}"`
- `"{SUBJECT} upcoming features launches"`
- `"{SUBJECT} strategic vision CEO interview"`
- `"{SUBJECT} market outlook predictions analysts"`
- `"{SUBJECT} risks challenges threats"`

Produire `07_FUTUR.md` avec :
- Roadmap connue / annoncée
- Signaux faibles et tendances émergentes
- Opportunités stratégiques identifiées
- Risques et menaces à surveiller
- Scénarios possibles (optimiste / central / pessimiste)
- Avis d'analystes et experts sectoriels
- Sources avec URLs

---

#### Agent ESG *(si `--esg`)*

**Objectif** : Évaluer la dimension environnementale, sociale et de gouvernance.

Recherches à effectuer :
- `"{SUBJECT} ESG rating score MSCI Sustainalytics {PREV} {YEAR}"`
- `"{SUBJECT} carbon footprint emissions net zero target"`
- `"{SUBJECT} sustainability report CSR"`
- `"{SUBJECT} ESG controversy scandal governance"`
- `"{SUBJECT} diversity inclusion social impact"`

Produire `08_ESG.md` avec :
- Notation ESG (MSCI, Sustainalytics, autres agences) avec évolution
- Bilan carbone et objectifs de réduction / net zéro
- Initiatives durabilité notables
- Controverses ESG connues
- Gouvernance (composition du CA, indépendance, diversité)
- Engagements sociaux (diversité, conditions de travail, impact local)
- Sources `[Officielle]` / `[Analyste]` avec dates

---

#### Agent RH / Culture *(si `--rh`)*

**Objectif** : Analyser la dimension humaine et organisationnelle.

Recherches à effectuer :
- `"{SUBJECT} employees headcount growth {PREV} {YEAR}"`
- `"{SUBJECT} Glassdoor review culture CEO approval"`
- `"{SUBJECT} LinkedIn jobs hiring trend"`
- `"{SUBJECT} layoffs restructuring organization"`
- `"{SUBJECT} culture values employer brand"`

Produire `10_RH.md` avec :
- Évolution des effectifs (N-3 à aujourd'hui)
- Note Glassdoor et principaux verbatims (forces / axes d'amélioration)
- Tendance recrutements LinkedIn (croissance / décroissance par fonction)
- Restructurations / licenciements récents
- Culture d'entreprise et valeurs affichées
- Indicateurs diversité & inclusion si disponibles
- Sources avec dates

---

### Étape 2bis — Vérification croisée des chiffres clés *(ignoré si `--brief`)*

Après la recherche par dimension, lancer un agent fact-checker qui :

1. Lit tous les fichiers `.md` produits et extrait les 5-10 affirmations chiffrées les plus importantes (revenus, valorisation, parts de marché, capacité, effectifs…)
2. Pour chaque affirmation, vérifie sur **au minimum 2 sources indépendantes**
3. Signale les contradictions entre sources avec `⚠️ CONTRADICTION :` suivi des deux valeurs et de leurs sources respectives
4. Produit un fichier `_factcheck.md` listant : affirmation vérifiée, sources confirmant, contradictions détectées

Ne modifier pas les fichiers de dimension — `_factcheck.md` est un document de vérification séparé.

### Étape 2b — Analyse SWOT *(si `--swot`)*

Une fois tous les fichiers de dimension produits, lancer un agent de synthèse SWOT qui **lit les fichiers déjà générés** (`01_HISTORIQUE.md` à `07_FUTUR.md`) pour en extraire les éléments SWOT sans relancer de recherches.

L'agent peut effectuer 1-2 WebSearch ciblées uniquement si une information clé manque dans les sections existantes.

Produire `09_SWOT.md` avec la structure suivante :

```markdown
# Analyse SWOT — {SUBJECT}
*Synthèse à partir du rapport d'audit complet — {date}*

## Matrice SWOT

|  | **Facteurs positifs** | **Facteurs négatifs** |
|---|---|---|
| **Internes** | **Forces** | **Faiblesses** |
| | • … | • … |
| **Externes** | **Opportunités** | **Menaces** |
| | • … | • … |

---

## Forces (Strengths)
*Ce que le sujet fait bien / avantages internes durables*

1. **[Titre court]** — [Description 2-3 lignes, source section XX]
…(4-6 points)

## Faiblesses (Weaknesses)
*Lacunes internes, points de vulnérabilité*

1. **[Titre court]** — [Description, source section XX]
…(4-6 points)

## Opportunités (Opportunities)
*Facteurs externes favorables à saisir*

1. **[Titre court]** — [Description, source section XX]
…(4-6 points)

## Menaces (Threats)
*Risques externes, pressions concurrentielles ou réglementaires*

1. **[Titre court]** — [Description, source section XX]
…(4-6 points)

---

## Implications stratégiques

| Stratégie | Description |
|---|---|
| **SO** — Exploiter les forces sur les opportunités | … |
| **ST** — Utiliser les forces pour contrer les menaces | … |
| **WO** — Combler les faiblesses via les opportunités | … |
| **WT** — Réduire l'exposition faiblesses × menaces | … |

---

## Prioritisation

| Élément | Quadrant | Impact | Urgence |
|---|---|---|---|
| … | Force / Faiblesse / Opportunité / Menace | Élevé / Moyen / Faible | Élevée / Moyenne / Faible |
```

**Si `--swot` est utilisé sans lancer de recherche par dimension** (ex: le dossier ne contient pas les fichiers `.md`), l'agent doit effectuer ses propres recherches ciblées sur les 4 quadrants avant de produire `09_SWOT.md`.

### Étape 3 — Génération du résumé exécutif

**Si `--brief`** : au lieu du résumé exécutif complet, produire uniquement `BRIEF.md` :

```markdown
# Brief — {SUBJECT}
*{date} — Sources : ~{n}*

## 5 faits clés
1. …
2. …
3. …
4. …
5. …

## Forces
- …
- …
- …

## Risques
- …
- …
- …

## Verdict
[2 lignes max — positionnement, trajectoire, décision recommandée]
```

Puis passer directement à l'**Étape 5** (compte-rendu). Ne pas produire les autres fichiers.

**Sinon** : continuer avec le résumé exécutif complet ci-dessous.

Une fois tous les fichiers de dimension produits, générer `00_RESUME_EXECUTIF.md` :

Structure du résumé exécutif :
```
# Audit {SUBJECT} — Résumé Exécutif
Date : {date}

## En un coup d'œil
[3-5 bullets avec les faits les plus saillants]

## Chiffres clés
[Tableau compact : revenus, marché, valorisation, concurrents, prix]

## Points forts
[3-5 points, une ligne chacun]

## Points de vigilance
[3-5 points, une ligne chacun]

## Verdict
[Paragraphe de synthèse — positionnement global, trajectoire, recommandation]
```

### Étape 4 — Assemblage du rapport complet

**Assemblage conditionnel** : ne fusionner que les fichiers **réellement présents** dans `$OUTPUT_DIR`
(en `--depth quick`, seules 4 dimensions existent ; ESG/SWOT/RH dépendent des options). Lister
dynamiquement les fichiers existants, dans l'ordre canonique ci-dessous, et n'inclure dans la table des
matières que les sections produites — ne jamais référencer un fichier absent.

```bash
ls "$OUTPUT_DIR" | grep -E '^[0-9]{2}_.*\.md$' | sort
```

Générer `RAPPORT_COMPLET.md` en fusionnant les fichiers présents dans cet ordre :

```
# Rapport d'Audit Complet — {SUBJECT}
**Date** : {date}  
**Profondeur** : {DEPTH}  
**Sources consultées** : {nombre total}

---
[Table des matières — uniquement les sections présentes, avec liens]

---
[Contenu de 00_RESUME_EXECUTIF.md]
[Pour chaque fichier NN_*.md présent, dans l'ordre 01→10 : séparateur + contenu]
  01_HISTORIQUE · 02_MARCHE · 03_TECHNIQUE · 04_TARIFICATION ·
  05_CONCURRENCE · 06_FINANCIER · 07_FUTUR · 08_ESG · 09_SWOT · 10_RH

---
## Index des sources
[Liste consolidée et dédupliquée — voir _sources.json (source de vérité structurée)]
```

### Étape 4b — Génération de `_data.json`

Extraire les chiffres clés structurés de l'ensemble du rapport et les écrire dans `_data.json`.
Le schéma est **générique** : un tableau `kpis` flexible (adapté à tout type de sujet) + des sections
typées **optionnelles** présentes seulement si pertinentes pour le `subject_type`.

```json
{
  "v": 1,
  "subject": "...",
  "subject_type": "company|product|market|technology|sector",
  "as_of": "YYYY-MM-DD",
  "kpis": [
    {"key": "revenue", "label": "Chiffre d'affaires", "value": 588, "unit": "M€",
     "period": "2024", "source_id": 3, "estimated": false}
  ],
  "financials": {"revenue": null, "ebitda": null, "net_income": null, "market_cap": null},
  "market": {"tam": null, "market_share_pct": null},
  "sources_count": null,
  "competitors_count": null
}
```

- `kpis[]` est la **source primaire** lue par l'UI : chaque entrée porte sa `period`, son `unit`, un
  lien `source_id` vers `_sources.json`, et `estimated` (officiel vs estimation).
- Les sections `financials`/`market` sont des **commodités optionnelles** — n'inclure que les champs
  trouvés ; pour un produit/marché, ajouter plutôt des `kpis` ad hoc (`users`, `mau`, `cagr`…).
- Laisser `null` (ou omettre) si la donnée n'a pas été trouvée. **Ne pas inventer de valeur.**

### Étape 4b-bis — Génération de `_sources.json`

Écrire l'index des sources sous forme **structurée** (lue par l'UI pour afficher badges/fraîcheur) :

```json
{
  "v": 1,
  "sources": [
    {"id": 1, "url": "https://…", "title": "…", "tag": "Officielle|Analyste|Presse",
     "date": "YYYY-MM", "dimensions": ["financier", "marche"], "stale": false}
  ]
}
```

- `id` est référencé par `_data.json.kpis[].source_id`.
- `dimensions` liste les sections qui ont cité la source (déduplication : une URL = une entrée).
- `stale: true` si la source date de plus d'un an par rapport à `as_of`.

### Étape 4c — Déduplication des sources + "Sources à surveiller"

Dans `RAPPORT_COMPLET.md`, l'index des sources final doit être **dédupliqué** : si une URL apparaît dans plusieurs sections, ne la lister qu'une fois, en indiquant les sections qui l'ont citée. (`_sources.json` est la source de vérité structurée correspondante.)

**Si `--watch`** (ou toujours recommandé) : ajouter une section finale dans `RAPPORT_COMPLET.md` :

```markdown
## Sources à surveiller

Pour suivre l'évolution de {SUBJECT} :

| Source | Type | URL |
|---|---|---|
| Relations Investisseurs officielle | [Officielle] | … |
| Fil d'actualités sectoriel | [Presse] | … |
| … | … | … |
```

Sélectionner 5-8 sources haute valeur (IR officielle, Bloomberg/Reuters si dispo, analystes clés, régulateurs sectoriels).

### Étape 5 — Compte-rendu final

Afficher un résumé de la session :

```
✓ Audit complet généré : {OUTPUT_DIR}/

Fichiers produits :
  00_RESUME_EXECUTIF.md     — synthèse 1 page
  01_HISTORIQUE.md          — {n} jalons couverts
  02_MARCHE.md              — marché estimé à {TAM}
  03_TECHNIQUE.md           — {n} fonctionnalités documentées
  04_TARIFICATION.md        — {n} offres tarifaires analysées
  05_CONCURRENCE.md         — {n} concurrents cartographiés
  06_FINANCIER.md           — données financières {année}
  07_FUTUR.md               — {n} scénarios prospectifs
  [08_ESG.md                — si --esg]
  [09_SWOT.md               — si --swot]
  [10_RH.md                 — si --rh]
  RAPPORT_COMPLET.md        — rapport fusionné (inclut toutes les sections générées)

Sources consultées : ~{n}
```

Enrichir et conserver le fichier `_recon.json` (ne pas le supprimer) — il documente la reconnaissance initiale et servira à comparer les mises à jour futures. Ajouter les champs de clôture :

```bash
python3 -c "
import json, sys
with open('$OUTPUT_DIR/_recon.json') as f: d = json.load(f)
d['audit_date'] = '$(date +%Y-%m-%d)'
d['depth'] = '$DEPTH'
d['sources_count'] = $TOTAL_SOURCES
with open('$OUTPUT_DIR/_recon.json', 'w') as f: json.dump(d, f, ensure_ascii=False, indent=2)
"
```

Ce fichier contient : `subject`, `subject_type`, `key_players`, `sector`, `search_keywords`, `language_sources`, `audit_date`, `depth`, `sources_count`.

### Étape 5b — Manifest canonique `_manifest.json`

Écrire un **index canonique** des artefacts produits — c'est le fichier que l'AuditViewer lit pour
connaître l'état final de l'audit (ne pas se fier à la numérotation, qui peut comporter des trous quand
seules certaines options sont activées) :

```json
{
  "v": 1,
  "subject": "...",
  "subject_type": "...",
  "slug": "...",
  "output_dir": "...",
  "audit_date": "YYYY-MM-DD",
  "depth": "quick|full",
  "mode": "parallel|sequential|solo",
  "options": ["swot", "esg"],
  "status": "complete|partial|canceled",
  "dimensions": [
    {"key": "historique", "file": "01_HISTORIQUE.md", "status": "done", "sources_count": 12}
  ],
  "files": [
    {"name": "00_RESUME_EXECUTIF.md", "kind": "summary"},
    {"name": "RAPPORT_COMPLET.md", "kind": "report"}
  ],
  "sources_count": 34,
  "data_file": "_data.json",
  "sources_file": "_sources.json",
  "report_file": "RAPPORT_COMPLET.md"
}
```

- `status: complete` si toutes les dimensions attendues ont produit leur fichier ; `partial` si certaines
  ont échoué ; `canceled` si interrompu via `_control.json`.
- `dimensions[]` reflète l'état réel (une dimension manquante a `status: "missing"` ou est absente).

**Si `APP_MODE=true`** : après l'écriture du manifest, émettre l'événement de clôture :
```bash
python3 "$OUTPUT_DIR/_emit.py" audit_complete --files_count "$N_FILES" \
  --sources_count "$TOTAL_SOURCES" --status complete
```
En `--brief`, le manifest a `status: complete` avec `files` réduit à `BRIEF.md`.

---

## Règles qualité

- **Sourcer chaque affirmation chiffrée** avec URL + date de publication.
- **Distinguer clairement** les données officielles des estimations.
- **Ne pas inventer** de chiffres — écrire "données non disponibles publiquement" si une métrique est introuvable.
- **Dater les informations** : toujours indiquer l'année/trimestre des données financières.
- **Langue** : produire tout le rapport dans la langue demandée (`--lang`), même si les sources sont en anglais.
- **Profondeur proportionnelle** : `quick` = 1-2 recherches par dimension, `full` = 4-6 recherches par dimension.
- Si une dimension n'est pas applicable (ex: "tarification" pour un secteur régulé sans prix marché), l'indiquer clairement et adapter le fichier.
