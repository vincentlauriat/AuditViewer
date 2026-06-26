import AppKit
import Darwin
import Foundation
import Observation
import SwiftUI
import WebKit

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
    enum ViewMode: String { case document, graph, kpis }
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

    func runAudit(subject: String, options: AuditOptions, outputDir: URL, model: String = "auto") async {
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
        // Modèle Claude : "auto" laisse le défaut de Claude Code ; sinon `--model`
        // est passé au CLI `claude` lui-même (pas au skill).
        var arguments: [String] = []
        if model != "auto" { arguments += ["--model", model] }
        arguments += [
            "--output-format", "stream-json",
            "--verbose",
            "-p", "/audit-report \(quotedSubject) \(options.cliFlags(appMode: true)) --output \(quotedOutput)"
        ]
        process.arguments = arguments
        process.currentDirectoryURL = outputDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // même pipe pour capturer aussi les erreurs

        // Wrapper @unchecked Sendable pour accumuler les lignes partielles hors MainActor
        final class LineAccumulator: @unchecked Sendable { var buffer = "" }
        let accumulator = LineAccumulator()

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            accumulator.buffer += text
            let lines = accumulator.buffer.components(separatedBy: "\n")
            accumulator.buffer = lines.last ?? ""
            let completed = Array(lines.dropLast().filter { !$0.isEmpty })
            Task { @MainActor in
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

    func rerunAuditWith(options: AuditOptions, model: String = "auto") async {
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

        await runAudit(subject: subject, options: options, outputDir: dir.deletingLastPathComponent(), model: model)

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

    // MARK: - Export

    /// Fichier source, titre du document et titre de la section pour la section affichée.
    private func exportSourceInfo() -> (filename: String, docTitle: String, sectionTitle: String) {
        switch selectedSectionId {
        case -3:
            let t = subject.isEmpty ? "Vérification des faits" : "\(subject) — Vérification des faits"
            return ("_factcheck.md", t, "Vérification des faits")
        case -1, -2, -4, -5:
            return ("RAPPORT_COMPLET.md", subject, "Rapport complet")
        default:
            if let s = sections.first(where: { $0.id == selectedSectionId }), s.exists {
                let t = subject.isEmpty ? s.title : "\(subject) — \(s.title)"
                return (s.filename, t, s.title)
            }
            return ("RAPPORT_COMPLET.md", subject, "Rapport complet")
        }
    }

    func exportCurrentSectionToDocx() {
        guard let dir = auditDir else { return }
        let (filename, _, sectionTitle) = exportSourceInfo()
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
        let capturedSubject = subject.isEmpty ? "Audit" : subject
        let capturedSection = sectionTitle
        let capturedDate = Self.formattedAuditDate(manifest?.auditDate ?? meta?.auditDate)
        let capturedSources = sourceCount

        Task.detached(priority: .userInitiated) {
            guard let sourceContent = try? String(contentsOf: sourceURL, encoding: .utf8) else { return }

            let sourcesLabel = capturedSources > 0
                ? "\(capturedSources) source\(capturedSources > 1 ? "s" : "") analysée\(capturedSources > 1 ? "s" : "")"
                : ""
            let authorLine = sourcesLabel.isEmpty ? "" : "author: \"\(sourcesLabel)\"\n"

            // Prépend un bloc YAML pour la page de titre pandoc (Title / Subtitle / Date / Author)
            let yaml = """
            ---
            title: "\(capturedSubject.replacingOccurrences(of: "\"", with: "\\\""))"
            subtitle: "\(capturedSection.replacingOccurrences(of: "\"", with: "\\\""))"
            date: "\(capturedDate)"
            \(authorLine)---

            """
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".md")
            try? (yaml + sourceContent).write(to: tempURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: pandoc)
            process.arguments = [
                tempURL.path,
                "--from", "markdown",
                "--to", "docx",
                "--output", destURL.path,
                "--toc", "--toc-depth=2"
            ]
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                _ = await MainActor.run { NSWorkspace.shared.open(destURL) }
            }
        }
    }

    func exportCurrentSectionToPDF() {
        guard let dir = auditDir else { return }
        let (filename, _, sectionTitle) = exportSourceInfo()
        let sourceURL = dir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename.replacingOccurrences(of: ".md", with: ".pdf")
        panel.directoryURL = dir
        panel.message = "Exporter en PDF"
        panel.prompt = "Exporter"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let pandoc = Self.findPandoc()
        let capturedSubject = subject.isEmpty ? "Audit" : subject
        let capturedSection = sectionTitle
        let capturedDate = Self.formattedAuditDate(manifest?.auditDate ?? meta?.auditDate)
        let capturedSources = sourceCount

        Task {
            // Conversion markdown → fragment HTML via pandoc (thread détaché)
            let htmlBody = await Task.detached(priority: .userInitiated) { () -> String in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: pandoc)
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()
                process.arguments = [sourceURL.path, "--from", "markdown", "--to", "html5"]
                try? process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0,
                   let html = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    return html
                }
                // Repli : contenu brut préformaté
                let raw = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
                return "<pre>\(raw.replacingOccurrences(of: "<", with: "&lt;"))</pre>"
            }.value

            let fullHTML = Self.buildPDFHTML(
                subject: capturedSubject,
                sectionTitle: capturedSection,
                date: capturedDate,
                sourcesCount: capturedSources,
                bodyHTML: htmlBody
            )

            do {
                try await PDFExporter.export(html: fullHTML, to: destURL)
                NSWorkspace.shared.open(destURL)
            } catch {
                // Échec silencieux — l'utilisateur voit que le fichier n'est pas créé
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

    var canExportPDF: Bool { canExportDocx }

    // MARK: - PDF HTML

    nonisolated static func buildPDFHTML(
        subject: String,
        sectionTitle: String,
        date: String,
        sourcesCount: Int,
        bodyHTML: String
    ) -> String {
        let sourcesLabel = sourcesCount > 0
            ? "\(sourcesCount) source\(sourcesCount > 1 ? "s" : "") analysée\(sourcesCount > 1 ? "s" : "")"
            : ""
        let sourcesRow = sourcesLabel.isEmpty ? "" : """
              <div class="ci">
                <span class="cl">Sources</span>
                <span class="cv">\(escapeHTML(sourcesLabel))</span>
              </div>
        """

        return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="UTF-8">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          @page { size: A4; margin: 0; }
          body {
            font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
            font-size: 10pt;
            color: #1a1a2e;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
          }

          /* ── Page de garde ── */
          .cover {
            width: 210mm; min-height: 297mm;
            background: #0c1a3d;
            display: flex; flex-direction: column;
            position: relative; overflow: hidden;
            page-break-after: always;
          }
          .cover-stripe {
            position: absolute; right: 0; top: 0;
            width: 58mm; height: 100%;
            background: linear-gradient(160deg, #132347 0%, #0e1d3a 100%);
            clip-path: polygon(28% 0, 100% 0, 100% 100%, 0% 100%);
          }
          .cover-line {
            position: absolute; right: 0; top: 0;
            width: 3px; height: 100%;
            background: linear-gradient(180deg, #4d9fff 0%, #2563eb 100%);
          }
          .cover-body {
            position: relative; z-index: 2;
            flex: 1; padding: 50mm 28mm 18mm;
            display: flex; flex-direction: column;
          }
          .eyebrow {
            font-size: 7pt; letter-spacing: 5px;
            text-transform: uppercase; color: #4d9fff;
            font-weight: 500; margin-bottom: 12mm;
          }
          .cover-title {
            font-size: 36pt; font-weight: 800;
            color: #fff; line-height: 1.0;
            letter-spacing: -0.5px;
            max-width: 128mm; margin-bottom: 6mm;
          }
          .cover-sub {
            font-size: 15pt; font-weight: 300;
            color: rgba(255,255,255,0.5);
            letter-spacing: 0.2px; margin-bottom: auto;
          }
          .cover-bar {
            width: 16mm; height: 2px;
            background: #4d9fff; border-radius: 1px;
            margin: 13mm 0 9mm;
          }
          .ci {
            display: flex; align-items: baseline;
            gap: 4mm; margin-bottom: 3.5mm;
          }
          .cl {
            font-size: 6.5pt; letter-spacing: 2.5px;
            text-transform: uppercase; color: rgba(255,255,255,0.28);
            min-width: 22mm;
          }
          .cv {
            font-size: 9pt; color: rgba(255,255,255,0.78);
            font-weight: 500;
          }
          .cover-footer {
            position: relative; z-index: 2;
            padding: 5mm 28mm;
            border-top: 1px solid rgba(255,255,255,0.07);
            display: flex; justify-content: space-between; align-items: center;
          }
          .brand {
            font-size: 7pt; letter-spacing: 3px;
            text-transform: uppercase; color: rgba(255,255,255,0.18);
          }
          .dot {
            width: 4px; height: 4px; border-radius: 50%;
            background: #4d9fff; opacity: 0.35;
          }

          /* ── Contenu ── */
          .content { padding: 18mm 22mm 22mm; }

          h1, h2, h3, h4 {
            font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
          }
          h1 {
            font-size: 20pt; font-weight: 700; color: #0c1a3d;
            margin: 12mm 0 5mm; padding-bottom: 3mm;
            border-bottom: 2.5px solid #4d9fff;
            page-break-before: always; page-break-after: avoid;
          }
          h1:first-child { page-break-before: avoid; margin-top: 0; }
          h2 {
            font-size: 14pt; font-weight: 700; color: #132347;
            margin: 8mm 0 3mm; page-break-after: avoid;
          }
          h3 {
            font-size: 11pt; font-weight: 600; color: #1e3566;
            margin: 6mm 0 2mm; page-break-after: avoid;
          }
          h4 { font-size: 10pt; font-weight: 600; color: #2a4a7c; margin: 4mm 0 1.5mm; }
          p { font-size: 10pt; line-height: 1.7; color: #252540; margin-bottom: 4mm; }
          ul, ol { margin: 0 0 4mm 7mm; padding: 0; }
          li { font-size: 10pt; line-height: 1.6; color: #252540; margin-bottom: 1.5mm; }
          strong { font-weight: 700; color: #0c1a3d; }
          em { font-style: italic; color: #2a2a50; }
          blockquote {
            border-left: 3px solid #4d9fff; background: #f2f5fb;
            padding: 3mm 5mm; margin: 5mm 0; border-radius: 0 3px 3px 0;
          }
          blockquote p { margin: 0; font-style: italic; color: #3a3a60; }
          table {
            width: 100%; border-collapse: collapse;
            margin: 5mm 0; font-size: 9pt; page-break-inside: avoid;
          }
          thead th {
            background: #0c1a3d; color: #fff;
            padding: 3mm 4mm; text-align: left;
            font-weight: 600; font-size: 8.5pt; letter-spacing: 0.3px;
          }
          tbody td {
            padding: 2.5mm 4mm; border-bottom: 1px solid #e5e9f5;
            vertical-align: top; line-height: 1.5;
          }
          tbody tr:nth-child(even) td { background: #f7f9fd; }
          tbody tr:last-child td { border-bottom: 2px solid #0c1a3d; }
          code {
            font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 8.5pt; background: #eef2fb;
            color: #1e3566; padding: 1px 4px; border-radius: 3px;
          }
          pre {
            background: #f0f4fd; border: 1px solid #d8e0f0;
            border-radius: 4px; padding: 4mm; margin: 4mm 0; overflow: hidden;
          }
          pre code { background: none; padding: 0; font-size: 8pt; color: #1e3566; }
          hr { border: none; border-top: 1px solid #dde2f0; margin: 7mm 0; }
          a { color: #1e3566; text-decoration: none; }
          section { display: block; }
          .footnotes {
            margin-top: 10mm; padding-top: 4mm;
            border-top: 1px solid #dde2f0;
            font-size: 8.5pt; color: #5a5a80;
          }
        </style>
        </head>
        <body>

        <div class="cover">
          <div class="cover-stripe"></div>
          <div class="cover-line"></div>
          <div class="cover-body">
            <div class="eyebrow">Dossier d&#8217;audit strat&#233;gique</div>
            <div class="cover-title">\(escapeHTML(subject))</div>
            <div class="cover-sub">\(escapeHTML(sectionTitle))</div>
            <div class="cover-bar"></div>
            <div class="ci">
              <span class="cl">Date</span>
              <span class="cv">\(escapeHTML(date))</span>
            </div>
            \(sourcesRow)
          </div>
          <div class="cover-footer">
            <span class="brand">AuditViewer</span>
            <div class="dot"></div>
            <span class="brand">Confidentiel</span>
          </div>
        </div>

        <div class="content">
        \(bodyHTML)
        </div>

        </body>
        </html>
        """
    }

    nonisolated private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    nonisolated static func formattedAuditDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            let f = DateFormatter()
            f.dateStyle = .long
            f.locale = Locale(identifier: "fr_FR")
            return f.string(from: Date())
        }
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        iso.locale = Locale(identifier: "en_US_POSIX")
        if let d = iso.date(from: String(raw.prefix(10))) {
            let f = DateFormatter()
            f.dateStyle = .long
            f.locale = Locale(identifier: "fr_FR")
            return f.string(from: d)
        }
        return raw
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
