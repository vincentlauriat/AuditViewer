# Comment ça marche

Un tour d'horizon en langage clair de ce qui se passe entre *« `/audit-report Tesla` »* et *« voici votre dossier »*. Pas de code, pas de jargon — et quand un terme technique est inévitable, il renvoie au [glossaire](glossaire.md).

---

## L'idée centrale

Voyez AuditViewer comme **un analyste de recherche junior infatigable**. Vous lui donnez un sujet ; il accomplit le même travail méthodique qu'un bon analyste — chercher largement, lire les sources importantes, noter d'où vient chaque fait, recouper les chiffres clés — et vous remet un rapport propre et structuré.

La différence avec un simple chatbot à qui l'on demande « parle-moi de Tesla », c'est **la méthode et la preuve**. Un chatbot répond de mémoire et peut mêler le fait à la supposition. AuditViewer interroge le web en direct, **source chaque chiffre avec un lien et une date**, signale la fiabilité de chaque source, et refuse d'inventer une donnée qu'il ne trouve pas.

---

## Les sept dimensions

Un vrai dossier d'audit examine un sujet sous plusieurs angles. AuditViewer en couvre toujours sept (un audit « rapide » couvre les quatre premiers) :

| Dimension | La question à laquelle elle répond |
|---|---|
| **Historique** | D'où cela vient-il, et qu'est-ce qui l'a façonné ? |
| **Marché** | Quelle est la taille du secteur, qui s'y trouve, où croît-il ? |
| **Technologie** | Qu'est-ce que c'est réellement, et qu'est-ce qui le distingue ? |
| **Tarification** | Comment cela génère-t-il des revenus, et à quel niveau de prix ? |
| **Concurrence** | Qui d'autre est dans la course, et qui l'emporte ? |
| **Finances** | Est-ce sain — revenus, financement, valorisation ? |
| **Perspectives** | Où cela se dirige-t-il, et qu'est-ce qui pourrait mal tourner ? |

Vous pouvez ajouter des chapitres **SWOT**, **ESG / durabilité** et **RH & culture** à la demande.

---

## Les cinq étapes d'un audit

### 1. Reconnaissance
Avant tout travail approfondi, l'IA lance quelques recherches larges pour *cadrer* le sujet : « Jaguar », est-ce le constructeur automobile ou l'animal ? « Notion », est-ce le logiciel ou autre chose ? Elle identifie le type de sujet, les acteurs clés et le vocabulaire à employer dans les recherches suivantes.

### 2. Confirmation (vous gardez la main)
Elle vous montre ensuite ce qu'elle a compris et **vous demande votre accord avant d'engager un vrai effort** : *lancer la recherche, ajuster le focus, ou annuler ?* Ce point de contrôle garantit que vous ne perdez jamais une longue exécution sur un sujet mal interprété.

### 3. Recherche, dimension par dimension
Pour chaque dimension, l'IA lance des recherches ciblées, lit les meilleures sources et rédige le chapitre correspondant. Ce faisant, elle suit des **règles de qualité strictes** :

- Chaque chiffre porte une **source avec lien et date de publication**.
- Les sources sont étiquetées **[Officielle]**, **[Analyste]** ou **[Presse]** pour que vous jugiez leur fiabilité d'un coup d'œil.
- Tout ce qui date de plus d'un an est signalé par ⚠️.
- Elle n'invente rien : si un chiffre n'est pas public, elle le dit.

Selon votre assistant, ces chapitres sont traités **en parallèle** (plusieurs « sous-analystes » à la fois, plus rapide) ou **l'un après l'autre** (davantage de recoupements). Vous n'avez pas à choisir — l'outil retient un réglage par défaut raisonnable.

### 4. Vérification des faits
Une passe dédiée reprend les 5 à 10 chiffres les plus importants (revenus, valorisation, part de marché…) et revérifie chacun auprès d'**au moins deux sources indépendantes**. Les contradictions sont mises en évidence explicitement, plutôt que discrètement « lissées ».

### 5. Assemblage
Enfin, elle rédige le **résumé exécutif** d'une page, fusionne tous les chapitres en un **rapport complet** prêt à partager, et dédoublonne la liste des sources pour que chaque référence n'apparaisse qu'une fois.

---

## Pourquoi vous pouvez faire confiance aux chiffres

La confiance vient du processus, et ce processus est délibérément strict :

- **Sourcé ou rien.** Chaque affirmation chiffrée renvoie à son origine.
- **La fiabilité est visible.** Les tags Officielle / Analyste / Presse vous laissent peser vous-même une affirmation.
- **La fraîcheur est visible.** Les données périmées sont signalées, pas dissimulées.
- **Les estimations sont identifiées.** Une supposition ne se déguise jamais en fait.
- **Les chiffres clés sont recoupés.** Les données qui comptent le plus reçoivent un deuxième, voire un troisième avis.

C'est la même rigueur qu'applique une équipe de conseil — traduite en règles que l'IA doit respecter à chaque exécution.

---

## Les visualiseurs, un langage commun

Vous pouvez lire un audit sous forme de simples fichiers. Mais le **visualiseur web** et l'**application macOS** ajoutent la progression en direct, une lecture confortable et une carte des liens entre vos audits. En déplacement, le **lecteur iOS / iPadOS** ouvre les mêmes audits directement depuis l'app Fichiers.

Toutes comprennent la même chose parce que le skill écrit sa sortie comme un **contrat machine** — un petit ensemble de fichiers stables à la structure fixe :

- un **flux d'événements** en direct pour qu'un visualiseur affiche la progression en temps réel ;
- un **canal de contrôle** pour qu'un visualiseur puisse mettre en pause, reprendre, annuler ou relancer un chapitre ;
- un échange **question/réponse** pour que l'IA puisse vous solliciter en pleine exécution, via l'interface ;
- et des **résumés structurés** (le manifeste, les chiffres clés, l'index des sources) que n'importe quel outil peut lire.

Parce que ce contrat est documenté et versionné, n'importe qui peut bâtir son propre visualiseur ou sa propre automatisation par-dessus. La spécification complète se trouve dans **[ARCHITECTURE.md](../../ARCHITECTURE.md)** — celle-ci s'adresse aux développeurs.

---

## Fonctionne avec Claude et Gemini

Le moteur s'adapte à votre assistant :

- **Claude Code** peut lancer plusieurs sous-agents de recherche à la fois — des audits rapides et parallèles.
- **Gemini** (et assimilés) exécute tout dans un seul grand contexte — le skill le détecte automatiquement et bascule en mode « solo », afin que vous obteniez le même rapport dans tous les cas.

---

Et ensuite : découvrez son application à des situations réelles → **[Cas d'usage](cas-usage.md)**.
