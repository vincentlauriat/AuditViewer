# Glossaire

Définitions en langage simple de chaque terme que vous pourriez rencontrer dans ce projet. Classées par ordre alphabétique.

---

**Audit** — Ici, un dossier de recherche complet sur un sujet : un ensemble de documents couvrant l'historique, le marché, la technologie, la tarification, la concurrence, les finances et les perspectives. Ce n'est pas un audit financier/comptable au sens strict — c'est plus proche de ce qu'un cabinet de conseil appelle une « analyse approfondie ».

**Claude Code** — L'assistant IA d'Anthropic pour le terminal et les éditeurs. L'environnement recommandé pour exécuter le skill `audit-report`. <https://claude.com/claude-code>

**Contrat machine** — La structure fixe et versionnée que le skill utilise pour sa sortie, afin que les visualiseurs (et tout autre outil) puissent lire et piloter les audits de façon fiable. Comprend le flux d'événements, le canal de contrôle et les fichiers JSON structurés. Spécification complète dans [ARCHITECTURE.md](../../ARCHITECTURE.md). C'est un sujet pour développeurs — vous n'éditez jamais ces fichiers à la main.

**Dimension** — Un angle d'analyse. Les sept dimensions standard sont l'Historique, le Marché, la Technologie, la Tarification, la Concurrence, les Finances et les Perspectives. Optionnelles : ESG, RH.

**Données périmées** — Information de plus d'un an, signalée par ⚠️ pour vous inviter à la traiter avec prudence.

**Dossier d'audit** — Le résultat d'une exécution, par exemple `audit-tesla/`. Il contient les chapitres du rapport (Markdown) et quelques fichiers de données structurées. Il vous appartient entièrement : ce ne sont que des fichiers sur votre disque.

**ESG** — *Environmental, Social, and Governance* (environnement, social, gouvernance). Une grille pour évaluer la durabilité et l'éthique d'une entreprise (empreinte carbone, gouvernance, controverses). Ajoutée avec `--esg`.

**Fact-check (vérification des faits)** — Une passe de vérification qui recontrôle les chiffres les plus importants auprès d'au moins deux sources indépendantes et signale les contradictions. Produit `_factcheck.md`.

**Gemini** — L'assistant IA de Google. Pris en charge via le mode « solo » ; installation avec `./install.sh --gemini`.

**Manifest (`_manifest.json`)** — Un petit fichier d'index qui liste tout ce qu'un audit a produit, ainsi que son état final. La « table des matières » que les applications lisent pour comprendre un audit.

**Markdown (`.md`)** — Un format de texte simple pour les documents. S'ouvre dans n'importe quel éditeur, sur GitHub ou dans un lecteur Markdown. Tous les chapitres d'audit sont en Markdown.

**Mode (`--mode`)** — La façon dont la recherche est menée. `parallel` = plusieurs sous-agents de recherche en même temps (le plus rapide). `sequential` = un par un (plus de recoupements). `solo` = aucun sous-agent, une seule exécution continue (utilisé automatiquement sur Gemini).

**Node.js** — L'environnement d'exécution nécessaire au visualiseur web. Téléchargement gratuit sur <https://nodejs.org/>.

**Profondeur (`--depth`)** — Le niveau de détail de la recherche. `quick` = plus rapide, ~10 sources, 4 dimensions. `full` = le réglage par défaut, ~30+ sources, 7 dimensions.

**Reconnaissance** — La première passe rapide où l'IA cadre votre sujet avant la recherche approfondie, et confirme le périmètre avec vous. Enregistrée dans `_recon.json`.

**Résumé exécutif** — L'aperçu d'une page en tête de chaque audit (`00_RESUME_EXECUTIF.md`) : faits clés, chiffres marquants et verdict. À lire en premier.

**Skill** — Une commande prête à l'emploi pour un assistant IA. `audit-report` est le skill qui anime tout ce projet ; vous le déclenchez avec `/audit-report`.

**Slug** — Une version simplifiée et compatible avec les noms de fichiers de votre sujet, utilisée pour nommer le dossier. « Société Générale » devient `societe-generale`. Calculé de la même façon à chaque fois, afin que les outils puissent le prédire.

**Source (tag de)** — Un libellé apposé sur chaque source indiquant sa fiabilité : **[Officielle]** (documents officiels, communiqués, pages Relations Investisseurs), **[Analyste]** (cabinets de recherche), **[Presse]** (médias).

**SSE (Server-Sent Events)** — Le mécanisme technique par lequel le visualiseur web reçoit les mises à jour en direct pendant l'exécution d'un audit. Vous n'interagissez pas directement avec lui ; c'est ce qui fait apparaître la progression en temps réel.

**SWOT** — *Strengths, Weaknesses, Opportunities, Threats* (Forces, Faiblesses, Opportunités, Menaces) : un cadre stratégique classique. Ajouté comme chapitre dédié avec `--swot`.

**TAM / SAM / SOM** — Trois manières de dimensionner un marché. **TAM** (*Total Addressable Market*) = le marché total. **SAM** (*Serviceable Available Market*) = la part que vous pourriez réalistement servir. **SOM** (*Serviceable Obtainable Market*) = la part que vous pourriez réalistement conquérir. Vocabulaire standard de l'analyse de marché.

**Verbose (`--verbose`)** — Une option qui affiche chaque recherche et chaque source au fil de l'audit, au lieu du seul résultat final.

**Visualiseur** — L'une des deux applications optionnelles pour lire et lancer les audits : le **visualiseur web** (navigateur) et l'**application macOS** (Mac natif). Les deux sont optionnelles — les audits restent lisibles comme de simples fichiers sans elles.
