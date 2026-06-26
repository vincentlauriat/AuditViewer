# CHANGES — Release Notes & Changelog

## 2026-06-26

### Added
- **macOS app: Export PDF** — Nouveau bouton « Exporter en PDF » dans la toolbar ; produit un PDF A4 via WKWebView sans dépendance externe (hors pandoc pour la conversion Markdown→HTML)
- **Page de garde professionnelle (PDF)** — Fond marine, bande géométrique, titre en grand, sous-titre, date et nombre de sources ; typographie système et CSS @page A4
- **Page de garde DOCX améliorée** — Injection d'un bloc YAML front matter (title / subtitle / date / author) avant pandoc pour que le titre, le sous-titre, la date et le nombre de sources apparaissent sur la page de titre Word

### Fixed
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

