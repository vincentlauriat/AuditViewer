# Cas d'usage

AuditViewer est utile dès que vous avez besoin de comprendre quelque chose *en profondeur et rapidement*. Voici des scénarios concrets, groupés selon votre profil.

---

## Pour les décideurs et analystes

### Diligence raisonnable avant un investissement
Vous envisagez de financer — ou d'acheter des actions dans — une entreprise. Avant la réunion, vous voulez avoir une vision complète : comment elle gagne de l'argent, qui sont ses concurrents, si les chiffres tiennent la route.

```bash
/audit-report "Mistral AI" --depth full --swot
```

Vous obtenez l'historique, le dimensionnement du marché, la technologie, les finances, une cartographie concurrentielle et une analyse SWOT dédiée — chaque chiffre sourcé et daté. Ce qui prenait autrefois deux jours de recherche documentaire devient une pause café.

### Surveillance concurrentielle
Vous devez suivre les mouvements d'un concurrent, ses changements de tarification et sa feuille de route.

```bash
/audit-report "Figma" --focus pricing --watch
```

L'option `--watch` ajoute une liste structurée « sources à suivre » pour continuer à surveiller l'évolution après l'audit. Relancer l'audit plus tard génère un **changelog** montrant exactement ce qui a changé.

### Étude de marché
Vous entrez sur un nouveau marché ou en dimensionnez un.

```bash
/audit-report "the European EV charging market" --depth full
```

Taille du marché (TAM/SAM/SOM), taux de croissance, régulation, géographie et principaux acteurs, condensés en un seul dossier.

### Présenter un audit en réunion ou en conseil
Vous devez exposer les conclusions d'un audit à un comité, un conseil d'administration ou une équipe, sans partager d'écran ni jongler avec un PDF. Lancez le **lecteur Apple TV (tvOS)** : il lit directement les audits partagés par votre Mac sur le réseau local, et vous parcourez à la télécommande la synthèse, les dimensions, les sources et le rapport complet sur le grand écran de la salle. Tout reste en local, rien ne transite par un cloud — pratique pour des sujets confidentiels en salle de conseil.

---

## Pour les curieux non-spécialistes

### Comprendre une entreprise avant de la rejoindre
Vous avez un entretien d'embauche ? Entrez informé.

```bash
/audit-report "Datadog" --rh
```

L'option `--rh` ajoute un chapitre RH et culture (tendances d'effectifs, sentiment Glassdoor, direction de recrutement) en plus du tableau commercial standard — exactement ce que vous voudriez savoir avant de signer.

### Prendre une décision d'achat confiante
Vous choisissez un outil, une voiture, un service ? Obtenez une vision impartiale et claire du paysage.

```bash
/audit-report "Tesla Model Y" --depth quick
```

Un passage rapide qui cartographie le produit, sa tarification et ses alternatives — sans le vernis marketing.

### Simplement apprendre correctement sur un sujet
Une technologie, une tendance, une industrie dont vous entendez parler partout.

```bash
/audit-report "retrieval-augmented generation" --lang fr
```

Une introduction structurée qui va bien au-delà d'une simple recherche, avec des sources que vous pouvez consulter pour approfondir.

---

## Pour les développeurs et contributeurs

### Construire votre propre visualiseur ou automatisation
Le skill émet un **[contrat machine](../../ARCHITECTURE.md)** documenté et versionné : un flux d'événements en direct, un canal de contrôle et des sorties JSON structurées. Tout ce qui lit ces fichiers peut afficher ou piloter un audit — tableaux de bord, bots Slack, pipelines CI, votre propre interface.

### Intégrer des audits dans un produit
Lancez des audits en mode sans interface (le backend web le fait déjà avec `claude -p`), suivez la progression via le flux d'événements et consommez les sorties structurées `_data.json` / `_sources.json` pour alimenter votre propre base de données ou vos templates de rapport.

### L'exécuter où vous travaillez
Claude Code, Gemini ou tout assistant capable de mapper les concepts génériques d'outils que le skill décrit. Le contrat est identique sur toutes les plateformes — seul le moteur d'exécution change.

---

## Un motif à connaître : maintenir vos audits à jour

Parce que chaque audit vit dans son propre dossier et enregistre comment il a été créé, vous pouvez **le relancer des semaines plus tard** sur le même sujet. Le skill détecte l'audit existant et propose de le *mettre à jour* — produisant un `CHANGELOG.md` qui vous dit exactement ce qui a changé depuis la dernière fois. Idéal pour les revues trimestrielles ou le suivi d'un concurrent qui bouge vite.

---

Besoin d'aide pour démarrer ? → [Démarrage](demarrage.md) · [FAQ](faq.md)
