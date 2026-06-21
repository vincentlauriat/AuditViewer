# Démarrage rapide

Ce guide vous mène de zéro à votre premier audit terminé. **Aucun bagage technique requis.** Si un terme vous paraît inconnu, consultez le [glossaire](glossaire.md).

---

## Ce dont vous avez besoin

Le moteur d'AuditViewer fonctionne *à l'intérieur* d'un assistant IA. Vous avez besoin de **l'un** de ceux-ci :

- **[Claude Code](https://claude.com/claude-code)** — recommandé, supporte toutes les fonctionnalités.
- **Gemini** (l'assistant de codage IA de Google) — supporté en mode « solo ».

C'est la seule exigence absolue. L'interface web et l'application Mac sont **optionnelles** pour lire vos audits plus facilement — vous pouvez les ignorer au départ.

---

## Étape 1 — Installer le moteur d'audit

Téléchargez (ou clonez) ce projet, ouvrez un terminal dans son dossier, et lancez :

```bash
./install.sh
```

Voilà. Cela signale à votre assistant IA la nouvelle commande `/audit-report`. Vous utilisez Gemini ? Lancez plutôt `./install.sh --gemini`.

Pour vérifier que c'est bien installé, ouvrez votre assistant et tapez :

```bash
/audit-report --help
```

Vous devriez voir un écran d'aide qui liste les options.

---

## Étape 2 — Lancer votre premier audit

Choisissez n'importe quel sujet — une entreprise, un produit, un marché, une technologie — et demandez-le :

```bash
/audit-report Notion
```

Voici ce qui se passe, et ce que vous verrez :

1. **Reconnaissance.** L'IA fait quelques recherches rapides pour comprendre votre sujet (Est-ce « Notion » la sociétéde logiciels ? Quel marché ? Quels concurrents ?).
2. **Confirmation.** Elle vous montre ce qu'elle a trouvé et vous demande : *« Dois-je lancer la recherche complète ? »* C'est votre occasion de la rediriger avant qu'elle ne passe du temps. Choisissez **Lancer**.
3. **Recherche.** Elle enquête sur chaque angle — historique, marché, technologie, tarification, concurrence, finances, perspectives — en recueillant et datant les sources au fur et à mesure.
4. **Vérification des faits.** Elle re-vérifie les chiffres les plus importants auprès de sources indépendantes et signale toute contradiction.
5. **Assemblage.** Elle écrit le résumé exécutif et fusionne tout dans un seul rapport complet.

Quand c'est terminé, vous aurez un nouveau dossier nommé `audit-notion/` contenant tous les documents.

> **Conseil — aller plus vite ou plus en profondeur :**
> - `/audit-report Notion --depth quick` — une version légère et rapide (~10 sources).
> - `/audit-report Notion --depth full` — l'approche complète par défaut (~30+ sources).
> - `/audit-report Notion --brief` — juste un résumé d'une page, rien d'autre.

---

## Étape 3 — Lire le résultat

Ouvrez le dossier `audit-notion/`. Commencez par **`00_RESUME_EXECUTIF.md`** (le résumé exécutif) pour un aperçu d'une page, puis plongez dans n'importe quel chapitre qui vous intéresse. **`RAPPORT_COMPLET.md`** est le rapport complet, prêt à partager ou à imprimer.

Tous les fichiers Markdown (`.md`) s'ouvrent dans n'importe quel éditeur de texte, sur GitHub, ou dans un lecteur Markdown. Mais les visualiseurs ci-dessous le rendent encore plus agréable.

---

## Étape 4 (optionnel) — Utiliser les visualiseurs

### Visualiseur web — consulter et lancer des audits dans votre navigateur

Si vous avez [Node.js](https://nodejs.org/) installé :

```bash
cd web
npm install
npm run dev
```

Ouvrez **http://localhost:5173**. Vous pouvez parcourir vos audits, en regarder un s'exécuter **en direct**, répondre aux questions de l'IA, et même lancer un nouvel audit depuis un formulaire — plus besoin de terminal après cela.

Vous voulez juste voir à quoi ça ressemble, avec des données d'exemple incluses dans le projet ?

### Application macOS — une expérience de lecture native

Sur un Mac (macOS 15+) avec la chaîne d'outils Swift :

```bash
cd mac
./build.sh
open build/AuditViewer.app
```

L'application Mac ajoute une vue Markdown enrichie et une **carte de style Obsidian** qui montre comment vos audits se connectent via les sources partagées et les personnes.

### Lecteur iOS / iPadOS — vos audits en déplacement

Une application native **en lecture seule** pour iPhone et iPad. Compilez-la depuis les sources (iOS 17+, Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)) :

```bash
cd mac
xcodegen generate
xcodebuild -scheme AuditViewerIOS -destination 'generic/platform=iOS Simulator' build
```

Au premier lancement, touchez **Choisir le dossier Research…** et sélectionnez votre dossier `Research` dans l'app **Fichiers** (iCloud Drive ou « Sur mon iPhone »). L'app le mémorise et vous laisse parcourir la synthèse, les dimensions, les sources et le rapport complet de chaque audit.

### Lecteur Apple TV (tvOS) — vos audits sur grand écran

Une application native **en lecture seule** pour Apple TV, pensée pour présenter un audit en réunion, en présentation ou en salle de conseil. L'Apple TV n'a ni sélecteur de fichiers, ni iCloud Drive, ni stockage local : c'est donc votre **Mac qui partage son dossier `Research` sur le réseau local**, et l'Apple TV s'y connecte pour lire les audits. Aucun cloud, tout reste chez vous.

Compilez la cible `AuditViewerTVOS` depuis les sources (tvOS 17+, Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)) :

```bash
cd mac
xcodegen generate
./tvos/build.sh
```

Cela compile et lance le viewer dans le simulateur tvOS. Pour l'installer sur une vraie Apple TV appairée à Xcode par Wi-Fi, passez son identifiant : `./tvos/build.sh <UDID>`.

Au premier lancement :

1. Côté Mac, ouvrez l'application macOS et activez le réglage **Partager sur le réseau local** (désactivé par défaut) ; un indicateur confirme que le partage est actif.
2. Côté Apple TV, autorisez l'accès au **réseau local** lorsque l'app le demande.

L'Apple TV découvre alors automatiquement votre Mac sur le réseau (via Bonjour) et, s'il n'y en a qu'un, s'y connecte sans configuration. Vous pouvez parcourir la liste des audits, la synthèse, les dimensions, les sources et le rapport complet, le tout à la télécommande Siri.

---

## Options courantes en un coup d'œil

| Vous voulez… | Ajoutez ceci |
|---|---|
| Le rapport en français | `--lang fr` |
| Un audit plus rapide et léger | `--depth quick` |
| Juste un résumé d'une page | `--brief` |
| Une analyse SWOT dédiée | `--swot` |
| Un chapitre ESG / développement durable | `--esg` |
| Un chapitre RH & culture | `--rh` |
| Une section « sources à surveiller » | `--watch` |
| Voir chaque recherche en direct | `--verbose` |

Combinez-les librement, par exemple `/audit-report "Mistral AI" --depth full --swot --verbose`.

---

## Où aller ensuite

- Curieux de *pourquoi* les rapports sont fiables ? → [Fonctionnement](fonctionnement.md)
- Vous avez besoin d'idées pour votre situation ? → [Cas d'usage](cas-usage.md)
- Vous êtes bloqué sur quelque chose ? → [FAQ](faq.md)
