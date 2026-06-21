# FAQ

Réponses courtes aux questions les plus fréquentes. Toujours bloqué ? Ouvrez une *issue* sur le dépôt.

---

### Qu'est-ce qu'AuditViewer exactement ?
Un outil qui transforme une simple demande — comme `/audit-report Tesla` — en un dossier de recherche complet et sourcé sur n'importe quelle entreprise, produit, marché ou technologie. Il s'accompagne de visualiseurs optionnels (une application web, une application macOS, un lecteur iOS/iPadOS et un lecteur Apple TV) pour lire et lancer les audits confortablement. Voir [Comment ça marche](fonctionnement.md).

### Faut-il être technicien pour l'utiliser ?
Non. Si vous savez installer une application et taper une commande, vous pouvez lancer un audit. Le [guide de démarrage](demarrage.md) ne suppose aucune connaissance préalable. Les visualiseurs vous permettent ensuite de tout faire depuis une interface graphique.

### Qu'est-ce que je dois installer ?
Au minimum, un assistant IA dans lequel le skill s'exécute : **[Claude Code](https://claude.com/claude-code)** (recommandé) ou **Gemini**. Le visualiseur web nécessite en plus [Node.js](https://nodejs.org/) ; l'application Mac nécessite macOS 15+ et la chaîne d'outils Swift ; le lecteur iOS/iPadOS nécessite iOS 17+ et se compile depuis les sources avec Xcode ; le lecteur Apple TV nécessite tvOS 17+, se compile aussi depuis les sources, et a besoin que le Mac partage son dossier `Research` sur le réseau local. Tous les visualiseurs sont optionnels.

### Est-ce que ça coûte quelque chose ?
Le projet lui-même est gratuit et open source ([licence MIT](../../LICENSE)). Lancer des audits consomme votre quota chez votre assistant IA (Claude Code ou Gemini), qui a sa propre tarification. Un audit « quick » consomme bien moins de ressources qu'un audit « full ».

### Combien de temps prend un audit ?
Généralement quelques minutes. Un audit `--depth quick` (~10 sources, 4 dimensions) est plus rapide ; un audit `--depth full` (~30+ sources, 7 dimensions) est plus approfondi. Vous voyez la progression à chaque instant.

### Peut-on faire confiance aux chiffres ?
Le skill est conçu pour être fiable : chaque chiffre porte un **lien vers sa source et une date**, les sources sont étiquetées **Officielle / Analyste / Presse**, les données périmées sont signalées, les estimations sont indiquées comme telles, et les chiffres clés sont **recoupés avec au moins deux sources indépendantes**. Le skill a pour consigne de ne jamais inventer un chiffre. Cela dit, considérez-le comme un excellent premier jet : pour une décision à fort enjeu, vérifiez vous-même les affirmations critiques à l'aide des sources fournies.

### Dans quelles langues le rapport peut-il être rédigé ?
Par défaut, le rapport est rédigé en **anglais** ; ajoutez `--lang fr` pour le français. L'IA lit les sources dans n'importe quelle langue et rédige le rapport dans celle que vous demandez.

### Quels sujets fonctionnent le mieux ?
Les entreprises, produits, marchés, technologies et secteurs — tout ce qui a une présence publique. Les sujets bien connus donnent les audits les plus riches. Les sujets très obscurs ou privés produiront des rapports plus minces, et le skill vous dira quand une donnée n'est pas publiquement disponible plutôt que de la deviner.

### Et si mon sujet est ambigu (par exemple « Jaguar ») ?
L'étape de reconnaissance le détecte. Si le nom correspond vraiment à plusieurs choses sans rapport, l'IA vous demande laquelle vous visez avant de lancer le travail approfondi.

### Puis-je me concentrer sur un seul aspect ?
Oui. Utilisez `--focus <aspect>` (par exemple `--focus financials`) pour approfondir un angle, ou `--brief` pour n'obtenir qu'un résumé d'une page. Vous pouvez aussi ajouter les chapitres `--swot`, `--esg` ou `--rh`.

### Puis-je mettre à jour un audit plus tard ?
Oui. Relancez le même sujet : le skill détecte l'audit existant et vous propose de le **mettre à jour** — puis produit un `CHANGELOG.md` de ce qui a changé. Idéal pour un suivi dans le temps.

### Où mes audits sont-ils stockés ?
Dans un dossier par audit (par exemple `audit-tesla/`), au sein du répertoire d'audits que vous avez choisi (par défaut `~/Documents/Research`). Ce sont de simples fichiers Markdown et JSON qui vous appartiennent entièrement — lisibles partout, avec ou sans les visualiseurs.

### Puis-je consulter mes audits sur Apple TV ?
Oui, avec le **lecteur Apple TV (tvOS 17+)**, en lecture seule — idéal pour présenter un audit sur grand écran en réunion ou en salle de conseil. Comme l'Apple TV n'a ni sélecteur de fichiers, ni iCloud Drive, ni stockage local, c'est votre **Mac qui partage son dossier `Research` sur le réseau local** : activez le réglage **Partager sur le réseau local** dans l'application macOS, autorisez le **réseau local** sur l'Apple TV, et celle-ci découvre puis se connecte automatiquement à votre Mac (via Bonjour). Tout reste sur votre réseau, sans cloud. Le lecteur tvOS se compile depuis les sources avec Xcode (cible `AuditViewerTVOS`).

### Les visualiseurs envoient-ils mes données quelque part ?
Non. Les visualiseurs lisent les dossiers d'audit sur votre propre machine. Le lecteur Apple TV lit les audits que votre Mac partage sur le **réseau local** uniquement — rien ne sort de votre réseau. Les seuls appels externes sont les recherches web que votre assistant IA effectue pendant l'investigation.

### Ça marche avec Claude — est-ce que ça marche avec Gemini ?
Oui. Le skill détecte quand les sous-agents ne sont pas disponibles et bascule automatiquement en mode « solo », en produisant le même rapport. Installez avec `./install.sh --gemini`.

### En quoi est-ce différent de demander simplement à ChatGPT/Claude « parle-moi de X » ?
Une réponse de chat provient de la mémoire du modèle et mêle le fait à l'approximation. Un audit interroge le **web en direct**, source et date chaque chiffre, recoupe les plus importants, et livre un **document structuré multi-chapitres** que vous pouvez partager. C'est la différence entre une réponse à l'oral et un rapport de recherche.

### Je suis développeur — puis-je construire dessus ?
Tout à fait. Le skill écrit un **[contrat machine](../../ARCHITECTURE.md)** documenté et versionné (flux d'événements, canal de contrôle, JSON structuré). Lisez ces fichiers pour afficher, piloter ou intégrer les audits dans vos propres outils.

### Comment signaler un bug ou contribuer ?
Ouvrez une *issue* ou une *pull request* sur le dépôt. Les notes propres à chaque composant se trouvent dans [`web/README.md`](../../web/README.md), [`mac/README.md`](../../mac/README.md) et [`skills/audit-report/SKILL.md`](../../skills/audit-report/SKILL.md).
