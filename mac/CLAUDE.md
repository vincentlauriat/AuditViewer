# CLAUDE.md — Audit Viewer

Consignes pour les agents IA travaillant sur ce dépôt. Lire aussi [ARCHITECTURE.md](ARCHITECTURE.md).

## Contexte

App macOS SwiftUI (SwiftPM) qui affiche les dossiers d'audit produits par le skill `audit-report`.
Le contenu dépend **directement du schéma de sortie de ce skill** (noms de fichiers, structure JSON).

## Langue
Communiquer et documenter en **français**. Les libellés d'UI sont en français.

## Build & vérification
- **Toujours** vérifier la compilation après modification : `swift build`.
- Pour une app *fonctionnelle* (ressources web incluses), utiliser **`./build.sh`** — `swift build` seul
  ne copie pas les bundles `web/` et `webgraph/`.
- Vérifier le lancement : `open build/AuditViewer.app`.

## Pièges spécifiques à ce projet
- **Bundle markdown partagé** : `web/` provient de `../MarkdownViewer/MarkdownViewer/Resources/web`
  et sert AUSSI à l'app MarkdownViewer. **Ne pas y ajouter de code spécifique à AuditViewer.**
  Tout asset propre à AuditViewer va dans `Sources/WebGraph/` (bundle `webgraph/`).
- **`Sources/WebGraph` est exclu de la cible SwiftPM** (`exclude` dans `Package.swift`) car il contient
  du HTML/JS. Si on ajoute un fichier web là, ne pas oublier qu'il n'est PAS compilé, seulement copié par `build.sh`.
- **Sections virtuelles** = id négatifs (-1 à -5), gérées dans `AuditStore.loadSection` et `SidebarView`.
  Les sections réelles statiques sont id 0-11 (`Models.swift`), les dynamiques 100+.
- **Dépendance au skill** : si les noms de fichiers (`00_*.md`, `_factcheck.md`, `_data.json`,
  `_recon.json`) ou leurs structures changent côté skill, réaligner `auditSections` (`Models.swift`),
  la détection dans `loadAuditDir`, `AuditMeta`, et `GraphBuilder`.

## Conventions de code
- Concurrence Swift 6 stricte : `AuditStore` est `@MainActor @Observable` ; respecter `Sendable`
  pour tout ce qui traverse les frontières d'acteur (cf. `LineAccumulator`, `Task.detached` pour les diffs).
- Suivre le style existant : commentaires en français, `// MARK:` pour les sections, libellés FR.
- Communication WKWebView : Swift→JS via `evaluateJavaScript`, JS→Swift via `WKScriptMessageHandler`.
- Ne pas ajouter de dépendances externes pour le rendu : le bundle carte est **vanilla JS sans dépendance**
  (offline). Garder cette contrainte.

## Débogage
- Corriger la cause racine, pas les symptômes. Ne pas masquer une erreur par du logging.
- Le `WKWebView` a `developerExtrasEnabled` : inspecter via l'inspecteur Web pour les soucis de rendu.

## Git
- Ne jamais push sur `main` directement ; créer une feature branch (sauf instruction contraire).
- Demander la stratégie git avant tout push ; confirmer avant tags/releases. Commits conventionnels.
