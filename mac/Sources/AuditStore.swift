import AppKit
import Darwin
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AuditStore {

    var auditDir: URL?
    var sections: [AuditSection] = []
    var selectedSectionId: Int = 0
    var currentMarkdown: String = ""
    var subject: String = ""
    var meta: AuditMeta? = nil
    var manifest: AuditManifest? = nil   // _manifest.json (contrat v1), nil si legacy
    var diffs: [Int: DiffEngine.Result] = [:]

    var showNewAudit: Bool = false
    var showUpdateSheet: Bool = false
    var isRunningAudit: Bool = false
    var processOutput: String = ""
    var lastOptions: AuditOptions = AuditOptions()

    var pendingQuestion: AuditQuestion? = nil
    var eventLog: [AuditEvent] = []
    var logEntries: [LogEntry] = []
    var showLogs: Bool = false
    private(set) var activeWatchDir: URL? = nil

    // Progression chiffrée issue des events v1 (`progress.pct`), 0…100, nil si inconnue
    var progressPct: Double? = nil
    // Dimensions terminées (clé v1 : historique, marche, …) pour l'affichage live
    var completedDimensions: Set<String> = []
    // Phase courante (recon, research, factcheck, swot, summary, assembly, finalize)
    var currentPhase: String? = nil

    // Output additionnel produit par le skill
    var factcheckExists: Bool = false
    var dataExists: Bool = false
    var sourceCount: Int = 0

    // Mode d'affichage du pane détail
    enum ViewMode: String { case document, graph }
    enum GraphScope: String { case local, global }
    var viewMode: ViewMode = .document
    var graphScope: GraphScope = .local
    private var localGraphCache: String? = nil
    private var globalGraphCache: String? = nil

    // Panneau d'infos flottant déclenché par un double-clic sur la carte
    // (source → URLs du domaine ; entity → sections citant l'acteur).
    var graphInfo: GraphInfo? = nil

    private var eventsSource: DispatchSourceFileSystemObject?
    private var eventsFD: Int32 = -1
    private var questionPollTimer: Timer?
    private var lastEventLine: Int = 0
    private var runningProcess: Process?   // process claude en cours (pour l'annulation)

    // MARK: - Computed

    var researchRoot: URL? { KeychainStore.researchRoot }

    var hasChanges: Bool { diffs.values.contains { $0.hasDiff } }

    var changedSectionsCount: Int { diffs.values.filter { $0.hasDiff }.count }

    // MARK: - Open

    func openAuditFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Sélectionner un dossier d'audit"
        panel.prompt = "Ouvrir"
        panel.directoryURL = auditDir?.deletingLastPathComponent()
            ?? KeychainStore.researchRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadAuditDir(url)
    }

    func loadAuditDir(_ url: URL) {
        auditDir = url
        subject = Self.subjectFromDir(url)
        diffs = [:]
        let fm = FileManager.default

        // Sections connues
        var built: [AuditSection] = auditSections.map { s in
            var copy = s
            copy.exists = fm.fileExists(atPath: url.appendingPathComponent(s.filename).path)
            return copy
        }

        // Découverte dynamique : .md non préfixés par "_" absents des sections connues
        let known = Set(auditSections.map { $0.filename })
        let extras = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_") }
            .map { $0.lastPathComponent }
            .filter { !known.contains($0) }
            .sorted()
        for (i, filename) in extras.enumerated() {
            let title = filename
                .replacingOccurrences(of: ".md", with: "")
                .replacingOccurrences(of: "_", with: " ")
            built.append(AuditSection(
                id: dynamicSectionBaseId + i,
                filename: filename,
                title: title,
                isOptional: true,
                exists: true
            ))
        }

        sections = built
        meta = Self.loadMeta(from: url)
        manifest = Self.loadManifest(from: url)

        // _manifest.json (v1) : faire foi pour les sujet/sections produites.
        // Une dimension dont le statut n'est pas "pending" et qui pointe un
        // fichier est considérée présente même si le scan ne l'a pas vue.
        if let manifest, let dims = manifest.dimensions {
            for dim in dims {
                guard let file = dim.file,
                      let i = sections.firstIndex(where: { $0.filename == file }) else { continue }
                let produced = (dim.status ?? "").lowercased() != "pending"
                    && fm.fileExists(atPath: url.appendingPathComponent(file).path)
                if produced { sections[i].exists = true }
            }
            // Sujet officiel du manifest (plus fiable que la dérivation du dossier)
            if let s = manifest.subject, !s.isEmpty { subject = s }
        }

        // Output additionnel
        factcheckExists = fm.fileExists(atPath: url.appendingPathComponent("_factcheck.md").path)
        dataExists = fm.fileExists(atPath: url.appendingPathComponent("_data.json").path)
        sourceCount = Self.countSources(in: url)

        // Invalider les caches de graphe (le global reste valable entre audits)
        localGraphCache = nil
        graphInfo = nil
        viewMode = .document

        // Options : _options.json (app) prioritaire, sinon déduites du manifest v1.
        if let saved = Self.loadSavedOptions(from: url) {
            lastOptions = saved
        } else if let manifest {
            lastOptions = Self.optionsFromManifest(manifest)
        }
        selectedSectionId = 0
        loadSection(0)
        saveOptions(lastOptions, in: url)
        startWatchingEvents(in: url)
    }

    // MARK: - Event watching (--app-mode)

    func startWatchingEvents(in dir: URL) {
        stopWatchingEvents()
        activeWatchDir = dir
        lastEventLine = 0
        eventLog = []
        pendingQuestion = nil
        progressPct = nil
        completedDimensions = []
        currentPhase = nil

        let eventsURL = dir.appendingPathComponent("_events.jsonl")
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }

        let fd = open(eventsURL.path, O_RDONLY)
        guard fd >= 0 else { return }
        eventsFD = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { [weak self] in
                self?.readNewEvents(from: eventsURL)
            }
        }
        src.setCancelHandler { [weak self] in
            let fd = self?.eventsFD ?? -1
            if fd >= 0 { close(fd) }
            self?.eventsFD = -1
        }
        src.resume()
        eventsSource = src

        questionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkForQuestion(in: dir) }
        }
    }

    func stopWatchingEvents() {
        eventsSource?.cancel()
        eventsSource = nil
        questionPollTimer?.invalidate()
        questionPollTimer = nil
    }

    private func readNewEvents(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > lastEventLine else { return }
        let newLines = Array(lines[lastEventLine...])
        lastEventLine = lines.count
        let decoder = JSONDecoder()
        for line in newLines {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(AuditEvent.self, from: data) else { continue }
            withAnimation(.easeInOut(duration: 0.2)) { eventLog.append(event) }
            applyEvent(event)
        }
    }

    private func applyEvent(_ event: AuditEvent) {
        switch event.type {
        case .fileWritten:
            if let dir = auditDir ?? activeWatchDir, let file = event.file,
               let i = sections.firstIndex(where: { $0.filename == file }) {
                sections[i].exists = FileManager.default.fileExists(
                    atPath: dir.appendingPathComponent(file).path
                )
            }

        case .progress:
            // Progression chiffrée 0…100 ; si seul `done`/`total` est fourni, on calcule.
            if let pct = event.pct {
                progressPct = max(0, min(100, pct))
            } else if let done = event.done, let total = event.total, total > 0 {
                progressPct = max(0, min(100, Double(done) / Double(total) * 100))
            }

        case .phaseStart:
            currentPhase = event.phase

        case .phaseDone:
            // Rien de spécifique : la progression chiffrée fait foi.
            break

        case .dimensionStart:
            // La dimension passe en cours — l'affichage live l'infère.
            break

        case .dimensionDone:
            // Marquer la dimension terminée (clé v1) pour l'affichage live.
            if let dim = event.dimension { completedDimensions.insert(dim) }

        case .question:
            // Une question attend dans `_question.json` — la lire sans attendre le poll.
            if let dir = auditDir ?? activeWatchDir { checkForQuestion(in: dir) }

        case .auditCanceled, .auditCancelled:
            // Arrêt comme une complétion : on recharge le dossier pour l'état final.
            stopWatchingEvents()
            if let dir = auditDir { loadAuditDir(dir) }

        case .error:
            appendLog(.error, event.message ?? "Erreur durant l'audit")

        case .auditComplete:
            progressPct = 100
            stopWatchingEvents()
            if let dir = auditDir { loadAuditDir(dir) }

        default:
            break
        }
    }

    private func checkForQuestion(in dir: URL) {
        let url = dir.appendingPathComponent("_question.json")
        guard pendingQuestion == nil,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let q = try? JSONDecoder().decode(AuditQuestion.self, from: data)
        else { return }
        pendingQuestion = q
    }

    func answerQuestion(value: String) {
        guard let question = pendingQuestion, let dir = auditDir ?? activeWatchDir else { return }
        pendingQuestion = nil
        let answer = AuditAnswer(id: question.id, value: value)
        if let data = try? JSONEncoder().encode(answer) {
            try? data.write(to: dir.appendingPathComponent("_answer.json"), options: .atomic)
        }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("_question.json"))
    }

    func loadSection(_ id: Int) {
        selectedSectionId = id
        switch id {
        case -1:
            currentMarkdown = generateDiffMarkdown()
        case -2:
            currentMarkdown = generateMetaMarkdown()
        case -3:
            if let dir = auditDir,
               let text = try? String(contentsOf: dir.appendingPathComponent("_factcheck.md"), encoding: .utf8) {
                currentMarkdown = text
            } else {
                currentMarkdown = "# Vérification des faits\n\n_`_factcheck.md` introuvable._"
            }
        case -4:
            currentMarkdown = generateDataMarkdown()
        case -5:
            currentMarkdown = generateSourcesMarkdown()
        default:
            guard let section = sections.first(where: { $0.id == id }) else { return }
            if let dir = auditDir,
               let text = try? String(contentsOf: dir.appendingPathComponent(section.filename), encoding: .utf8) {
                currentMarkdown = text
            } else {
                currentMarkdown = placeholderMarkdown(for: section)
            }
        }
    }

    // MARK: - Run audit

    func runAudit(subject: String, options: AuditOptions, outputDir: URL) async {
        lastOptions = options
        isRunningAudit = true
        processOutput = ""
        logEntries = []
        appendLog(.info, "Démarrage de l'audit : \(subject)")

        // Dossier de sortie déterministe aligné v1 : <outputDir>/audit-<slug>.
        // On le passe explicitement au skill via `--output` (plus de dépendance
        // au cwd ni à `findNewAuditDir`).
        let slug = Self.slugify(subject)
        let auditDir = outputDir.appendingPathComponent("audit-\(slug)")
        try? FileManager.default.createDirectory(at: auditDir, withIntermediateDirectories: true)

        // Dossier de l'audit en cours, mémorisé pour l'annulation (_control.json).
        activeWatchDir = activeWatchDir ?? auditDir

        let claudePath = Self.findClaude()
        let process = Process()
        runningProcess = process
        process.executableURL = URL(fileURLWithPath: claudePath)
        // Sujet quoté (guillemets internes échappés) → évite l'injection d'args
        // et gère espaces/accents. `--output` pointe sur le dossier déterministe.
        let quotedSubject = Self.shellQuote(subject)
        let quotedOutput = Self.shellQuote(auditDir.path)
        process.arguments = [
            "--output-format", "stream-json",
            "--verbose",
            "-p", "/audit-report \(quotedSubject) \(options.cliFlags(appMode: true)) --output \(quotedOutput)"
        ]
        process.currentDirectoryURL = outputDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // même pipe pour capturer aussi les erreurs

        // Wrapper @unchecked Sendable pour accumuler les lignes partielles hors MainActor
        final class LineAccumulator: @unchecked Sendable { var buffer = "" }
        let accumulator = LineAccumulator()

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            accumulator.buffer += text
            let lines = accumulator.buffer.components(separatedBy: "\n")
            accumulator.buffer = lines.last ?? ""
            let completed = Array(lines.dropLast().filter { !$0.isEmpty })
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processOutput += text
                for line in completed { self.parseStreamLine(line) }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                handle.readabilityHandler = nil
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in
                    self?.processOutput = "Erreur : \(error.localizedDescription)"
                }
                continuation.resume()
            }
        }

        isRunningAudit = false
        runningProcess = nil

        // Charger le dossier déterministe ; repli sur la détection si absent
        // (sécurité pour un skill qui n'aurait pas honoré `--output`).
        if FileManager.default.fileExists(atPath: auditDir.path) {
            loadAuditDir(auditDir)
        } else if let newDir = Self.findNewAuditDir(in: outputDir, for: subject) {
            loadAuditDir(newDir)
        }
    }

    // MARK: - Annulation

    /// Annule un audit en cours : écrit `_control.json {v:1, action:"cancel"}`
    /// dans le dossier surveillé (le skill s'arrête proprement) puis termine
    /// le process `claude` a minima.
    func cancelAudit() {
        if let dir = activeWatchDir ?? auditDir {
            let control: [String: Any] = ["v": 1, "action": "cancel"]
            if let data = try? JSONSerialization.data(withJSONObject: control) {
                try? data.write(to: dir.appendingPathComponent("_control.json"), options: .atomic)
            }
            appendLog(.info, "Annulation demandée")
        }
        runningProcess?.terminate()
        runningProcess = nil
    }

    // MARK: - Re-run (mise à jour)

    func rerunAudit() async {
        var options = Self.loadSavedOptions(from: auditDir) ?? lastOptions
        options.depth = meta?.depth ?? options.depth
        await rerunAuditWith(options: options)
    }

    func rerunAuditWith(options: AuditOptions) async {
        guard let dir = auditDir else { return }

        // Snapshot du contenu actuel avant écrasement
        let snapshot: [Int: String] = sections.reduce(into: [:]) { acc, s in
            if let text = try? String(contentsOf: dir.appendingPathComponent(s.filename), encoding: .utf8) {
                acc[s.id] = text
            }
        }

        // Réinitialiser les diffs précédents
        diffs = [:]
        for i in sections.indices { sections[i].diffResult = nil }

        await runAudit(subject: subject, options: options, outputDir: dir.deletingLastPathComponent())

        // Calculer les diffs en arrière-plan (CPU intensif)
        await computeDiffs(snapshot: snapshot)
    }

    // MARK: - Persistance des options

    func saveOptions(_ options: AuditOptions, in dir: URL) {
        if let data = try? JSONEncoder().encode(options) {
            try? data.write(to: dir.appendingPathComponent("_options.json"), options: .atomic)
        }
    }

    static func loadSavedOptions(from dir: URL?) -> AuditOptions? {
        guard let dir = dir,
              let data = try? Data(contentsOf: dir.appendingPathComponent("_options.json")),
              let opts = try? JSONDecoder().decode(AuditOptions.self, from: data) else { return nil }
        return opts
    }

    private func computeDiffs(snapshot: [Int: String]) async {
        guard let dir = auditDir else { return }
        let capturedSections = sections

        let computed = await Task.detached(priority: .userInitiated) {
            capturedSections.compactMap { section -> (Int, DiffEngine.Result)? in
                guard let oldText = snapshot[section.id],
                      let newText = try? String(contentsOf: dir.appendingPathComponent(section.filename), encoding: .utf8)
                else { return nil }
                let result = DiffEngine.diff(old: oldText, new: newText)
                return (section.id, result)
            }
        }.value

        for (id, result) in computed {
            diffs[id] = result
            if let i = sections.firstIndex(where: { $0.id == id }), result.hasDiff {
                sections[i].diffResult = result
            }
        }

        if hasChanges {
            selectedSectionId = -1
            currentMarkdown = generateDiffMarkdown()
        }
    }

    // MARK: - Markdown synthétique

    func generateMetaMarkdown() -> String {
        guard let meta = meta else {
            return "# Sources\n\n_Aucune métadonnée disponible (`_recon.json` introuvable)._\n\nLancez un audit pour générer ce fichier."
        }

        var md = "# Sources & Reconnaissance\n\n"

        if let date = meta.auditDate { md += "**Date de l'audit** : \(date)  \n" }
        if let depth = meta.depth {
            md += "**Profondeur** : \(depth == "quick" ? "Rapide" : "Complète")  \n"
        }
        if let count = meta.sourcesCount { md += "**Sources consultées** : ~\(count)  \n" }
        if let lang = meta.languageSources { md += "**Langue des sources** : \(lang)  \n" }

        md += "\n"

        if let sector = meta.sector, !sector.isEmpty {
            md += "## Secteur\n\n\(sector)\n\n"
        }

        if let players = meta.keyPlayers, !players.isEmpty {
            md += "## Acteurs clés identifiés\n\n"
            for p in players { md += "- \(p)\n" }
            md += "\n"
        }

        if let keywords = meta.searchKeywords, !keywords.isEmpty {
            md += "## Mots-clés de recherche utilisés\n\n"
            for k in keywords { md += "- `\(k)`\n" }
            md += "\n"
        }

        if let type_ = meta.subjectType, !type_.isEmpty {
            md += "## Type de sujet\n\n`\(type_)`\n\n"
        }

        return md
    }

    func generateDiffMarkdown() -> String {
        let changed: [(AuditSection, DiffEngine.Result)] = sections.compactMap { s in
            guard let d = diffs[s.id], d.hasDiff else { return nil }
            return (s, d)
        }

        guard !changed.isEmpty else {
            return "# Modifications\n\n_Aucune modification détectée entre les deux versions._"
        }

        var md = "# Modifications\n\n"
        md += "> Comparaison entre la version précédente et la version actuelle de l'audit.\n\n"

        md += "## Résumé\n\n"
        md += "| Section | Ajouts | Suppressions |\n"
        md += "|---------|--------|--------------|\n"
        for (section, diff) in changed {
            md += "| **\(section.title)** | +\(diff.added) | -\(diff.removed) |\n"
        }
        md += "\n"

        md += "## Détail des modifications\n\n"
        for (section, diff) in changed {
            md += "### \(section.title)\n\n"
            md += diff.markdownBlock
            md += "\n\n"
        }

        return md
    }

    // MARK: - Chiffres-clés (_data.json)

    func generateDataMarkdown() -> String {
        guard let dir = auditDir,
              let raw = try? Data(contentsOf: dir.appendingPathComponent("_data.json")) else {
            return "# Chiffres-clés\n\n_Aucune donnée structurée disponible (`_data.json` introuvable)._"
        }

        // v1 : présence de `kpis[]` → tableau KPI dédié.
        if let data = try? JSONDecoder().decode(AuditDataKpis.self, from: raw),
           let kpis = data.kpis, !kpis.isEmpty {
            return Self.renderKpiTable(kpis)
        }

        // Repli legacy : rendu récursif générique du JSON.
        guard let obj = try? JSONSerialization.jsonObject(with: raw) else {
            return "# Chiffres-clés\n\n_`_data.json` illisible._"
        }
        var md = "# Chiffres-clés\n\n"
        md += "> Données structurées extraites de l'audit (`_data.json`).\n\n"
        md += Self.renderJSON(obj, depth: 0)
        return md
    }

    /// Rendu v1 des KPI : tableau Libellé | Valeur+unité | Période | officiel/estimé.
    private static func renderKpiTable(_ kpis: [AuditKpi]) -> String {
        var md = "# Chiffres-clés\n\n"
        md += "> Indicateurs structurés extraits de l'audit (`_data.json`).\n\n"
        md += "| Libellé | Valeur | Période | Statut |\n"
        md += "|---------|--------|---------|--------|\n"
        for k in kpis {
            let label = (k.label ?? k.key ?? "—").replacingOccurrences(of: "|", with: "\\|")
            var valeur = k.value ?? "—"
            if let unit = k.unit, !unit.isEmpty, valeur != "—" { valeur += " \(unit)" }
            valeur = valeur.replacingOccurrences(of: "|", with: "\\|")
            let periode = k.period ?? "—"
            let statut = (k.estimated == true) ? "estimé" : "officiel"
            md += "| \(label) | \(valeur) | \(periode) | \(statut) |\n"
        }
        md += "\n"
        return md
    }

    /// Rendu markdown récursif d'une valeur JSON arbitraire.
    private static func renderJSON(_ value: Any, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        switch value {
        case let dict as [String: Any]:
            var out = ""
            for key in dict.keys.sorted() {
                let pretty = key.replacingOccurrences(of: "_", with: " ").capitalized
                let v = dict[key]!
                if v is [String: Any] || v is [Any] {
                    if depth == 0 {
                        out += "## \(pretty)\n\n\(renderJSON(v, depth: 0))\n"
                    } else {
                        out += "\(indent)- **\(pretty)** :\n\(renderJSON(v, depth: depth + 1))"
                    }
                } else {
                    out += "\(indent)- **\(pretty)** : \(scalar(v))\n"
                }
            }
            return out
        case let arr as [Any]:
            var out = ""
            for v in arr {
                if v is [String: Any] || v is [Any] {
                    out += "\(indent)-\n\(renderJSON(v, depth: depth + 1))"
                } else {
                    out += "\(indent)- \(scalar(v))\n"
                }
            }
            return out
        default:
            return "\(indent)- \(scalar(value))\n"
        }
    }

    private static func scalar(_ v: Any) -> String {
        switch v {
        case let n as NSNumber:
            // Booléen encodé en NSNumber
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "oui" : "non" }
            if n.doubleValue == n.doubleValue.rounded() && abs(n.doubleValue) < 1e15 {
                return NumberFormatter.localizedString(from: n, number: .decimal)
            }
            return "\(n)"
        case let s as String:
            return s
        case is NSNull:
            return "—"
        default:
            return "\(v)"
        }
    }

    // MARK: - Index des sources

    func generateSourcesMarkdown() -> String {
        guard let dir = auditDir else { return "# Sources\n\n_Aucun audit ouvert._" }

        // v1 : `_sources.json` présent → tableau structuré (tag, date, ⚠ si stale, dimensions).
        if let sources = Self.loadSources(from: dir), !sources.isEmpty {
            return Self.renderSourcesTable(sources)
        }

        // Repli legacy : scan regex des liens dans les `.md`.
        let refs = GraphBuilder.scanSources(in: dir)
        guard !refs.isEmpty else {
            return "# Sources\n\n_Aucune source externe citée dans les sections._"
        }

        // domaine -> (sections citant, échantillon d'URLs avec libellés)
        struct Agg { var files = Set<String>(); var links: [(String, String)] = [] }
        var byDomain: [String: Agg] = [:]
        for r in refs {
            var a = byDomain[r.domain] ?? Agg()
            a.files.insert(r.file)
            if !a.links.contains(where: { $0.1 == r.url }) {
                a.links.append((r.label.isEmpty ? r.url : r.label, r.url))
            }
            byDomain[r.domain] = a
        }

        let titleFor: (String) -> String = { file in
            self.sections.first(where: { $0.filename == file })?.title ?? file
        }

        var md = "# Sources\n\n"
        md += "**\(refs.count)** citations · **\(byDomain.count)** domaines distincts\n\n"

        // Tri : domaines les plus partagés d'abord
        let ordered = byDomain.sorted {
            $0.value.files.count != $1.value.files.count
                ? $0.value.files.count > $1.value.files.count
                : $0.key < $1.key
        }
        for (domain, agg) in ordered {
            let secList = agg.files.map(titleFor).sorted().joined(separator: ", ")
            md += "## \(domain)\n\n"
            md += "_Cité dans : \(secList)_\n\n"
            for (label, url) in agg.links.prefix(8) {
                md += "- [\(label)](\(url))\n"
            }
            md += "\n"
        }
        return md
    }

    /// Rendu v1 des sources (`_sources.json`) : tableau trié par tag puis id.
    private static func renderSourcesTable(_ sources: [AuditSource]) -> String {
        let staleCount = sources.filter { $0.stale == true }.count
        var md = "# Sources\n\n"
        md += "**\(sources.count)** sources référencées"
        if staleCount > 0 { md += " · ⚠️ \(staleCount) à rafraîchir" }
        md += "\n\n"
        md += "| # | Source | Type | Date | Dimensions |\n"
        md += "|---|--------|------|------|------------|\n"

        // Tri : Officielle > Analyste > Presse > autre, puis par id.
        func tagRank(_ tag: String?) -> Int {
            switch tag {
            case "Officielle": return 0
            case "Analyste":   return 1
            case "Presse":     return 2
            default:           return 3
            }
        }
        let ordered = sources.sorted {
            tagRank($0.tag) != tagRank($1.tag) ? tagRank($0.tag) < tagRank($1.tag) : $0.id < $1.id
        }

        for s in ordered {
            let warn = (s.stale == true) ? " ⚠️" : ""
            let title = (s.title?.isEmpty == false ? s.title! : s.url)
                .replacingOccurrences(of: "|", with: "\\|")
            let link = "[\(title)](\(s.url))"
            let tag = s.tag.map { "[\($0)]" } ?? "—"
            let date = s.date ?? "—"
            let dims = (s.dimensions ?? []).joined(separator: ", ")
            md += "| \(s.id) | \(link)\(warn) | \(tag) | \(date) | \(dims.isEmpty ? "—" : dims) |\n"
        }
        md += "\n"
        return md
    }

    // MARK: - Carte / Graphe

    func graphJSON(for scope: GraphScope) -> String {
        switch scope {
        case .local:
            if let cached = localGraphCache { return cached }
            guard let dir = auditDir else { return "{\"nodes\":[],\"edges\":[]}" }
            let data = GraphBuilder.buildLocalGraph(dir: dir, subject: subject, sections: sections, meta: meta)
            let json = Self.encodeGraph(data)
            localGraphCache = json
            return json
        case .global:
            if let cached = globalGraphCache { return cached }
            let root = researchRoot ?? auditDir?.deletingLastPathComponent()
            guard let root else { return "{\"nodes\":[],\"edges\":[]}" }
            let data = GraphBuilder.buildGlobalGraph(root: root)
            let json = Self.encodeGraph(data)
            globalGraphCache = json
            return json
        }
    }

    private static func encodeGraph(_ data: GraphData) -> String {
        guard let d = try? JSONEncoder().encode(data),
              let s = String(data: d, encoding: .utf8) else { return "{\"nodes\":[],\"edges\":[]}" }
        return s
    }

    /// Geste sur un nœud du graphe (transmis depuis le JS).
    /// `gesture` vaut "single" (clic simple) ou "double" (double-clic).
    /// `nodeId` est l'identifiant JS du nœud (ex. "src-3", "ent-1"), utilisé
    /// pour la mise en évidence côté carte (`window.focusNode`).
    func handleGraphNodeTap(
        gesture: String,
        type: String,
        label: String?,
        nodeId: String?,
        sectionId: Int?,
        auditPath: String?
    ) {
        if gesture == "double" {
            handleGraphNodeDoubleTap(type: type, label: label, nodeId: nodeId)
            return
        }

        // Clic simple : comportement de navigation existant.
        switch type {
        case "section":
            if let id = sectionId {
                viewMode = .document
                selectedSectionId = id
                loadSection(id)
            }
        case "audit":
            if let path = auditPath {
                loadAuditDir(URL(fileURLWithPath: path))
                graphScope = .local
                viewMode = .graph
            }
        default:
            break
        }
    }

    /// Double-clic : ouverture du rapport complet (subject) ou panneau d'infos
    /// flottant (source/entity). Les sections gardent le comportement de clic simple.
    private func handleGraphNodeDoubleTap(type: String, label: String?, nodeId: String?) {
        switch type {
        case "subject":
            // Ouvrir le rapport complet (section id 11) si présent.
            if sections.contains(where: { $0.id == 11 && $0.exists }) {
                loadSection(11)
                viewMode = .document
            }
        case "source":
            guard let domain = label, let nodeId else { return }
            graphInfo = .source(domain: domain, nodeId: nodeId, items: sourceItems(forDomain: domain))
        case "entity":
            guard let name = label, let nodeId else { return }
            graphInfo = .entity(name: name, nodeId: nodeId, sections: sectionsMentioning(name))
        default:
            break
        }
    }

    /// Ouvre la section d'un panneau « acteur » et ferme le panneau.
    func openSectionFromGraphInfo(_ id: Int) {
        graphInfo = nil
        viewMode = .document
        selectedSectionId = id
        loadSection(id)
    }

    func dismissGraphInfo() { graphInfo = nil }

    // MARK: Données du panneau d'infos

    /// URLs d'un domaine pour le dossier courant : scan des `.md` (domaine→URLs),
    /// enrichi par `_sources.json` (tag/date/stale) lorsqu'une URL y figure.
    private func sourceItems(forDomain domain: String) -> [GraphSourceItem] {
        // En périmètre global, le nœud « Source » agrège un domaine partagé par
        // plusieurs audits : scanner tous les dossiers, pas seulement l'audit courant.
        let dirs: [URL]
        switch graphScope {
        case .local:
            guard let dir = auditDir else { return [] }
            dirs = [dir]
        case .global:
            guard let root = researchRoot ?? auditDir?.deletingLastPathComponent() else { return [] }
            dirs = GraphBuilder.auditDirs(in: root)
        }

        var seen = Set<String>()
        var items: [GraphSourceItem] = []
        for dir in dirs {
            // Index _sources.json par URL (si présent) pour l'enrichissement.
            var meta: [String: AuditSource] = [:]
            if let sources = Self.loadSources(from: dir) {
                for s in sources { meta[s.url] = s }
            }

            // URLs du domaine via le scan (couvre aussi les audits legacy).
            for ref in GraphBuilder.scanSources(in: dir) where ref.domain == domain {
                guard seen.insert(ref.url).inserted else { continue }
                let s = meta[ref.url]
                items.append(GraphSourceItem(
                    id: ref.url,
                    url: ref.url,
                    title: s?.title ?? (ref.label.isEmpty ? nil : ref.label),
                    tag: s?.tag,
                    date: s?.date,
                    stale: s?.stale ?? false
                ))
            }

            // Ajouter les URLs de _sources.json du même domaine non vues au scan.
            for (url, s) in meta where GraphBuilder.domain(of: url) == domain && !seen.contains(url) {
                seen.insert(url)
                items.append(GraphSourceItem(
                    id: url, url: url, title: s.title, tag: s.tag, date: s.date, stale: s.stale ?? false
                ))
            }
        }

        // Tri : Officielle > Analyste > Presse > autre, puis par URL.
        func rank(_ tag: String?) -> Int {
            switch tag {
            case "Officielle": return 0
            case "Analyste":   return 1
            case "Presse":     return 2
            default:           return 3
            }
        }
        return items.sorted {
            rank($0.tag) != rank($1.tag) ? rank($0.tag) < rank($1.tag) : $0.url < $1.url
        }
    }

    /// Sections existantes dont le `.md` mentionne l'acteur (insensible à la casse).
    private func sectionsMentioning(_ name: String) -> [GraphSectionRef] {
        guard let dir = auditDir, !name.isEmpty else { return [] }
        var refs: [GraphSectionRef] = []
        for s in sections where s.exists && s.id >= 0 {
            guard let text = try? String(
                contentsOf: dir.appendingPathComponent(s.filename), encoding: .utf8
            ) else { continue }
            if text.localizedCaseInsensitiveContains(name) {
                refs.append(GraphSectionRef(id: s.id, title: s.title))
            }
        }
        return refs
    }

    // MARK: - Log parsing (stream-json)

    private func appendLog(_ kind: LogEntry.Kind, _ message: String) {
        logEntries.append(LogEntry(id: UUID(), timestamp: Date(), kind: kind, message: message))
    }

    private func parseStreamLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Ligne non-JSON (texte brut, sortie verbeux, hooks) → loggée telle quelle
            if trimmed.count > 3 {
                appendLog(.text, String(trimmed.prefix(300)))
            }
            return
        }

        switch json["type"] as? String {
        case "system":
            // Ignorer les hooks OMC (hook_started, hook_response) — trop verbeux
            // Afficher uniquement l'init pour confirmation de démarrage
            if (json["subtype"] as? String) == "init" {
                let model = json["model"] as? String ?? "Claude"
                appendLog(.info, "Session démarrée — modèle : \(model)")
            }
        case "assistant":
            guard let msg = json["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return }
            for block in content {
                switch block["type"] as? String {
                case "tool_use":
                    let name  = block["name"]  as? String ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    let entry = makeToolEntry(name: name, input: input)
                    logEntries.append(entry)
                case "text":
                    if let text = block["text"] as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            appendLog(.text, String(trimmed.prefix(300)))
                        }
                    }
                default: break
                }
            }
        case "tool":
            // Résultats des outils — ignorer le contenu (trop verbeux), juste noter la fin
            break
        case "result":
            if (json["subtype"] as? String) == "error", let err = json["error"] as? String {
                appendLog(.error, err)
            } else {
                appendLog(.done, "Audit terminé")
            }
        default: break
        }
    }

    private func makeToolEntry(name: String, input: [String: Any]) -> LogEntry {
        let kind: LogEntry.Kind
        let message: String
        switch name {
        case "WebSearch":
            kind = .search
            message = "Recherche : \(input["query"] as? String ?? "")"
        case "WebFetch":
            kind = .fetch
            let url = input["url"] as? String ?? ""
            message = "Fetch : \(url)"
        case "Write":
            kind = .write
            let path = input["file_path"] as? String ?? ""
            message = "Écriture : \(URL(fileURLWithPath: path).lastPathComponent)"
        case "Edit":
            kind = .write
            let path = input["file_path"] as? String ?? ""
            message = "Édition : \(URL(fileURLWithPath: path).lastPathComponent)"
        case "Bash":
            kind = .bash
            let cmd = (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            message = "$ \(String(cmd.prefix(120)))"
        case "Agent":
            kind = .agent
            message = "Agent : \(input["description"] as? String ?? "")"
        case "Read":
            kind = .read
            let path = input["file_path"] as? String ?? ""
            message = "Lecture : \(URL(fileURLWithPath: path).lastPathComponent)"
        default:
            kind = .info
            message = name
        }
        return LogEntry(id: UUID(), timestamp: Date(), kind: kind, message: message)
    }

    // MARK: - Export DOCX

    func exportCurrentSectionToDocx() {
        guard let dir = auditDir else { return }

        // Fichier source : section courante ou RAPPORT_COMPLET par défaut
        let filename: String
        let docTitle: String
        switch selectedSectionId {
        case -3:
            filename = "_factcheck.md"
            docTitle = subject.isEmpty ? "Vérification des faits" : "\(subject) — Vérification des faits"
        case -1, -2, -4, -5:
            filename = "RAPPORT_COMPLET.md"
            docTitle = subject
        default:
            if let section = sections.first(where: { $0.id == selectedSectionId }), section.exists {
                filename = section.filename
                docTitle = subject.isEmpty ? section.title : "\(subject) — \(section.title)"
            } else {
                filename = "RAPPORT_COMPLET.md"
                docTitle = subject
            }
        }

        let sourceURL = dir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "docx") ?? .data]
        panel.nameFieldStringValue = filename.replacingOccurrences(of: ".md", with: ".docx")
        panel.directoryURL = dir
        panel.message = "Exporter en document Word"
        panel.prompt = "Exporter"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let pandoc = Self.findPandoc()
        let capturedTitle = docTitle
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pandoc)
            process.arguments = [
                sourceURL.path,
                "--from", "markdown",
                "--to", "docx",
                "--output", destURL.path,
                "--metadata", "title=\(capturedTitle)",
                "--toc", "--toc-depth=2"
            ]
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                _ = await MainActor.run { NSWorkspace.shared.open(destURL) }
            }
        }
    }

    var canExportDocx: Bool {
        guard auditDir != nil else { return false }
        switch selectedSectionId {
        case -3:
            return factcheckExists
        case -1, -2, -4, -5:
            return auditDir.flatMap {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent("RAPPORT_COMPLET.md").path)
            } ?? false
        default:
            return sections.first(where: { $0.id == selectedSectionId })?.exists ?? false
        }
    }

    // MARK: - Helpers

    private static func loadManifest(from dir: URL) -> AuditManifest? {
        let url = dir.appendingPathComponent("_manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(AuditManifest.self, from: data) else { return nil }
        return manifest
    }

    /// Déduit les options de l'app depuis le manifest v1 (`depth`, `mode`, `options[]`).
    private static func optionsFromManifest(_ m: AuditManifest) -> AuditOptions {
        var opts = AuditOptions()
        if let depth = m.depth { opts.depth = depth }
        if let mode = m.mode { opts.mode = mode }
        let flags = Set((m.options ?? []).map { $0.lowercased() })
        opts.swot  = flags.contains("swot")
        opts.esg   = flags.contains("esg")
        opts.rh    = flags.contains("rh")
        opts.brief = flags.contains("brief")
        return opts
    }

    /// Nombre de sources : `_sources.json` (v1) prioritaire, sinon scan regex des `.md`.
    private static func countSources(in dir: URL) -> Int {
        if let sources = Self.loadSources(from: dir) { return sources.count }
        return GraphBuilder.scanSources(in: dir).count
    }

    /// Lit `_sources.json` (contrat v1) si présent, sinon nil (→ repli scan).
    static func loadSources(from dir: URL) -> [AuditSource]? {
        let url = dir.appendingPathComponent("_sources.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SourcesFile.self, from: data) else { return nil }
        return file.sources
    }

    private static func loadMeta(from dir: URL) -> AuditMeta? {
        // Le skill produit _recon.json (gardé désormais en fin d'audit)
        for name in ["_recon.json", "_meta.json"] {
            let url = dir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let meta = try? JSONDecoder().decode(AuditMeta.self, from: data) {
                return meta
            }
        }
        return nil
    }

    /// Slug déterministe aligné v1 (réplique de la règle du skill) :
    /// NFKD → ASCII (diacritiques retirés) → non-alphanumérique → `-` →
    /// compression/trim des tirets → minuscules → défaut `sujet`.
    static func slugify(_ subject: String) -> String {
        // NFKD + retrait des diacritiques (Mn) → ASCII
        let decomposed = subject.decomposedStringWithCanonicalMapping
        let ascii = String(decomposed.unicodeScalars.filter { scalar in
            scalar.isASCII && !CharacterSet.nonBaseCharacters.contains(scalar)
        })
        // Tout caractère non alphanumérique → `-`
        var out = ""
        var lastWasDash = false
        for ch in ascii.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        // Trim des tirets en bordure
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "sujet" : out
    }

    /// Quote un argument pour une ligne de commande POSIX (guillemets doubles,
    /// échappement des `"`, `\`, `$`, `` ` ``).
    static func shellQuote(_ s: String) -> String {
        var escaped = ""
        for ch in s {
            if ch == "\"" || ch == "\\" || ch == "$" || ch == "`" {
                escaped.append("\\")
            }
            escaped.append(ch)
        }
        return "\"\(escaped)\""
    }

    private static func subjectFromDir(_ url: URL) -> String {
        var slug = url.lastPathComponent
        for prefix in ["audit-", "audit_"] where slug.hasPrefix(prefix) {
            slug = String(slug.dropFirst(prefix.count))
            break
        }
        return slug.replacingOccurrences(of: "-", with: " ")
                   .replacingOccurrences(of: "_", with: " ")
                   .capitalized
    }

    private func placeholderMarkdown(for section: AuditSection) -> String {
        let hint = subject.isEmpty ? "…" : subject
        return """
        # \(section.title)

        > **Fichier `\(section.filename)` non disponible.**

        Lancez `/audit-report \(hint)` dans Claude Code,
        ou appuyez sur **⌘N** pour démarrer un nouvel audit depuis cette application.
        """
    }

    private static func findClaude() -> String {
        let candidates = [
            "/Users/\(NSUserName())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "claude"
    }

    private static func findPandoc() -> String {
        let candidates = [
            "/opt/homebrew/bin/pandoc",
            "/usr/local/bin/pandoc",
            "/usr/bin/pandoc",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "pandoc"
    }

    private static func findNewAuditDir(in parent: URL, for subject: String) -> URL? {
        let slug = slugify(subject)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        for name in ["audit-\(slug)", "audit_\(slug)"] {
            let url = parent.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        let items = (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return items
            .filter { $0.lastPathComponent.hasPrefix("audit-") || $0.lastPathComponent.hasPrefix("audit_") }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return da < db
            }
    }
}
