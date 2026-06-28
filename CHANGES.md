# CHANGES — Release Notes & Changelog

## 2026-06-28

### Added
- **macOS app: mode racine multi-audits** — Second mode d'ouverture (en plus du mode direct `⌘O` qui pointe un dossier d'audit précis). Nouveau « Ouvrir un dossier racine… » (`⇧⌘O`, menu Fichier + bouton de l'écran d'accueil) : on pointe un dossier **racine** contenant plusieurs audits, l'app affiche une **liste plein écran** de tous les audits trouvés (titre, date, sources, profondeur, badge de statut), et un clic ouvre l'audit dans la vue détail habituelle ; un bouton **« ‹ Audits »** dans la toolbar revient à la liste. Détection robuste : tout sous-dossier contenant `_manifest.json` ou `00_RESUME_EXECUTIF.md` (indépendant du préfixe `audit-`). Nouveaux fichiers `Sources/AuditEntry.swift`, `Sources/AuditListView.swift` ; `AuditStore` gagne `audits`/`browseMode`/`browseRoot` + `openRootFolder`/`loadRoot`/`backToList`/`discoverAudits`/`loadEntry`. Racine mémorisée dans le Keychain (`researchRoot`).

### Fixed
- **macOS app: liste racine figée sur dossier iCloud** — Les fichiers d'un `Research/` synchronisé iCloud sont *dataless* (taille logique visible, mais 1re lecture = matérialisation bloquante ~0,8 s/fichier). Le chargement des entrées en série gelait la liste ~30 s sur la « Recherche des audits… ». Corrigé : lecture des entrées **en parallèle** (`withTaskGroup`, ~16 concurrentes) hors MainActor → mur ramené à quelques secondes au 1er accès, instantané ensuite.

### Added
- **iOS app: icône d'app** — La cible iOS reçoit enfin une icône, identique à celle de macOS. Générée depuis `AppIcon.icns` (1024×1024) via le nouveau script `Scripts/make-ios-icon.swift` (compose l'icône sur un dégradé indigo opaque — iOS interdit l'alpha et applique son propre masque arrondi). Asset catalog `ios/Assets.xcassets/AppIcon.appiconset`, déclaré dans `project.yml` (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`).

### Fixed
- **iOS app: audits iCloud manquants dans la liste** — Les dossiers `audit-*` non encore téléchargés (placeholders iCloud, parfois cachés `.audit-x.icloud`) étaient ignorés → certains audits (ADCytherix, Cast Software, Infortive Transition…) n'apparaissaient pas, voire « aucun audit ». `ResearchVaultReader` ne sautait plus `.skipsHiddenFiles` mais surtout le téléchargement iCloud était **fire-and-forget** (`startDownloadingUbiquitousItem` jamais attendu) : le listing/lecture s'exécutait avant la matérialisation. Corrigé : téléchargement **bloquant** avec polling du statut (`downloadAndWait`, timeout 20 s), lecture coordonnée du répertoire racine (`NSFileCoordinator`), résolution des placeholders `.icloud` → nom réel, matérialisation bloquante des dossiers évincés avant lecture interne.

## 2026-06-26

### Added
- **macOS app: Export PDF** — Nouveau bouton « Exporter en PDF » dans la toolbar ; produit un PDF A4 via WKWebView sans dépendance externe (hors pandoc pour la conversion Markdown→HTML)
- **Page de garde professionnelle (PDF)** — Fond marine, bande géométrique, titre en grand, sous-titre, date et nombre de sources ; typographie système et CSS @page A4
- **Page de garde DOCX améliorée** — Injection d'un bloc YAML front matter (title / subtitle / date / author) avant pandoc pour que le titre, le sous-titre, la date et le nombre de sources apparaissent sur la page de titre Word

### Changed
- **Écran « Chiffres clés » : cartes encadrées** — Chaque KPI est désormais dans un cadre élégant : coins arrondis (14), bordure fine adaptée au thème, ombre douce, barre d'accent latérale (bleu / orange si estimé), valeur en gras `title3`, badge « estimé » en capsule. Le fond uniforme de la grille (identique aux cartes, donc invisible) a été retiré pour que les cartes se détachent.

### Fixed
- **Rapport complet exporté en markdown brut (cadre gris)** — `RAPPORT_COMPLET.md` contient des blocs `---` … `---` (séparateurs horizontaux entourant des notes de section) que pandoc interprétait comme des métadonnées YAML → erreur de parsing (`Unknown alias`, exit 64) → l'export PDF retombait sur le fallback `<pre>` (markdown brut). Corrigé en désactivant l'extension via `--from markdown-yaml_metadata_block` (PDF **et** DOCX). Les `--metadata` CLI restent appliqués.
- **PDF crash (SIGTRAP)** — `runModal(for:delegate:didRun:)` rappelle son delegate sur un thread d'arrière-plan ; le `PrintDelegate` marqué `@MainActor` déclenchait une assertion d'isolation Swift 6. Rendu `nonisolated` / `@unchecked Sendable` ; la `CheckedContinuation` se résout depuis n'importe quel thread.
- **PDF multi-GB** — `WKWebView.pdf()` capturait le contenu en une seule page géante rastérisée à 2x Retina → fichiers de plusieurs GB, app bloquée. Remplacé par `WKWebView.printOperation(with:)` + fenêtre NSWindow réelle hors-écran (`alphaValue=0`, origine -30000,-30000, `orderBack`) + `runModal(for:delegate:didRun:contextInfo:)` asynchrone : PDFs A4 vectoriels paginés, l'UI ne freeze plus.
- **App freeze après export** — `NSPrintOperation.run()` était synchrone et bloquait le main thread ; `runModal` retourne immédiatement et rappelle via le run loop AppKit.

### Technical
- `PDFExporter.swift` réécrit : `NSWindow` hors-écran + `WKWebView.printOperation(with:)` + `PrintDelegate` (`NSObject @MainActor`) qui résout la continuation Swift dans `printOperationDidRun(_:success:contextInfo:)`
- `AuditStore` : refactoring `exportSourceInfo()` partagé entre les deux exports ; `exportCurrentSectionToPDF()` ; `canExportPDF` ; `buildPDFHTML()` + `escapeHTML()` + `formattedAuditDate()` (tous `nonisolated static`)
- `ContentView` : bouton PDF ajouté à côté du bouton Word dans la toolbar primaire

## 2026-06-24

### Added
- **macOS app: KPIs fullscreen viewer** — New "Chiffres clés" tab in the main toolbar (alongside Document & Carte views) for dedicated exploration of key performance indicators with a 4-column responsive grid layout

### Changed
- **macOS app: KPI display** — Removed right-side panel approach; KPIs now accessible exclusively via dedicated fullscreen tab for cleaner UI and focused analysis

### Technical
- `AuditStore.ViewMode` extended: added `.kpis` case for KPI-dedicated view mode
- `ContentView` refactored: consolidated display logic; KPI sidebar removed; fullscreen KPI view integrated into view mode picker
- Animation fixes: wrapped conditional views in `Group` to properly apply SwiftUI animations across view mode transitions

## Future
- [ ] Commit & PR: KPI fullscreen mode feature
- [ ] Vérif visuelle sur macOS : ouvrir un audit réel (OneStream) et tester l'onglet "Chiffres clés"
- [ ] Consider panel-based sidebar approach if right-side KPI display returns as feature request

---

## Earlier versions
See `PLAN.md` for macro-scale architecture decisions and multi-platform roadmap (tvOS, iOS, web viewer).

