import SwiftUI

// MARK: - LiveProgressView
// Vue de progression pilotée à la fois par les événements de log (store.logEntries)
// et par le polling des fichiers sur disque. Les deux sources se complètent :
// - Un .write sur "01_HISTORIQUE.md" → section done instantanément
// - Un .agent mentionnant "historique" → section running
// - Polling 1s → rattrape les fichiers créés hors stream (mode solo, outil externe)

struct LiveProgressView: View {
    @Environment(AuditStore.self) private var store

    let outputDir: URL
    let subject: String
    let options: AuditOptions

    @State private var filesOnDisk: Set<String> = []
    @State private var pollTimer: Timer? = nil

    // Sections à afficher selon les options
    private var sections: [AuditSection] {
        if options.brief {
            return [AuditSection(id: 0, filename: "BRIEF.md", title: "Brief (1 page)")]
        }
        return auditSections.filter { s in
            guard s.isOptional else { return true }
            switch s.filename {
            case "08_ESG.md":  return options.esg
            case "09_SWOT.md": return options.swot
            case "10_RH.md":   return options.rh
            default:           return false
            }
        }
    }

    // Clé de dimension v1 (events `dimension_done`) pour un fichier de section.
    private func dimensionKey(for filename: String) -> String? {
        switch filename {
        case "01_HISTORIQUE.md":   return "historique"
        case "02_MARCHE.md":       return "marche"
        case "03_TECHNIQUE.md":    return "technique"
        case "04_TARIFICATION.md": return "tarification"
        case "05_CONCURRENCE.md":  return "concurrence"
        case "06_FINANCIER.md":    return "financier"
        case "07_FUTUR.md":        return "futur"
        case "08_ESG.md":          return "esg"
        case "10_RH.md":           return "rh"
        default:                   return nil
        }
    }

    // Statut d'une section : done > running > pending
    private func status(for section: AuditSection) -> LiveStatus {
        // 1. Fichier présent sur disque
        if filesOnDisk.contains(section.filename) { return .done }
        // 2. Événement v1 `dimension_done` pour cette dimension
        if let key = dimensionKey(for: section.filename),
           store.completedDimensions.contains(key) { return .done }
        // 3. Événement .write dans les logs (plus rapide que le poll)
        if store.logEntries.contains(where: {
            $0.kind == .write && $0.message.contains(section.filename)
        }) { return .done }
        // 4. Un agent récent correspond à cette section
        if isAgentRunning(for: section) { return .running }
        return .pending
    }

    // Dernière opération attribuable à cette section (pour affichage sous le nom)
    private func recentOp(for section: AuditSection) -> String? {
        let kw = keywords(for: section)
        return store.logEntries.reversed().first { entry in
            [.search, .fetch, .bash].contains(entry.kind) &&
            kw.contains(where: { entry.message.localizedCaseInsensitiveContains($0) })
        }?.message
    }

    // Activité globale courante (dernière entrée significative)
    private var currentActivity: LogEntry? {
        store.logEntries.last(where: { [.search, .fetch, .agent, .write, .bash, .done].contains($0.kind) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Progression chiffrée (events v1 `progress.pct`)
                if let pct = store.progressPct {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: pct, total: 100)
                            .progressViewStyle(.linear)
                        Text("\(Int(pct.rounded())) %")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 12)
                }

                // Bandeau d'activité courante
                if store.isRunningAudit, let entry = currentActivity {
                    activityBanner(entry)
                        .padding(.bottom, 12)
                }

                // Nœuds de sections
                ForEach(sections) { section in
                    LiveSectionRow(
                        section: section,
                        status: status(for: section),
                        recentOp: recentOp(for: section),
                        isRunning: store.isRunningAudit
                    )
                }

                // Synthèse finale
                if !options.brief {
                    liveSeparator
                    LiveSectionRow(
                        section: AuditSection(
                            id: 99,
                            filename: "RAPPORT_COMPLET.md",
                            title: "Rapport complet"
                        ),
                        status: status(for: AuditSection(
                            id: 99, filename: "RAPPORT_COMPLET.md", title: "Rapport complet"
                        )),
                        recentOp: nil,
                        isRunning: store.isRunningAudit
                    )
                }

                // Stats en bas
                if !store.isRunningAudit && !filesOnDisk.isEmpty {
                    Divider().padding(.vertical, 8)
                    let done = sections.filter { status(for: $0) == .done }.count
                    Text("\(done) / \(sections.count) sections")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .onAppear { startPolling() }
        .onDisappear { pollTimer?.invalidate(); pollTimer = nil }
    }

    // MARK: - Bandeau activité

    @ViewBuilder
    private func activityBanner(_ entry: LogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.icon)
                .font(.system(size: 11))
                .foregroundStyle(entryColor(entry.kind))
                .frame(width: 14)
            Text(entry.message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(entryColor(entry.kind).opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(entryColor(entry.kind).opacity(0.25), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.3), value: entry.id)
    }

    private var liveSeparator: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
            Image(systemName: "arrow.down")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func isAgentRunning(for section: AuditSection) -> Bool {
        guard store.isRunningAudit else { return false }
        let kw = keywords(for: section)
        return store.logEntries.suffix(30).contains { entry in
            entry.kind == .agent &&
            kw.contains(where: { entry.message.localizedCaseInsensitiveContains($0) })
        }
    }

    private func keywords(for section: AuditSection) -> [String] {
        switch section.filename {
        case "00_RESUME_EXECUTIF.md": return ["résumé", "resume", "executif", "executive", "synthèse"]
        case "01_HISTORIQUE.md":      return ["historique", "history", "historical", "timeline"]
        case "02_MARCHE.md":          return ["marché", "marche", "market", "tam", "sam"]
        case "03_TECHNIQUE.md":       return ["technique", "technical", "technology", "stack"]
        case "04_TARIFICATION.md":    return ["tarification", "pricing", "tarif", "price"]
        case "05_CONCURRENCE.md":     return ["concurrence", "competition", "concurrent", "rival"]
        case "06_FINANCIER.md":       return ["financier", "financial", "finance", "revenue"]
        case "07_FUTUR.md":           return ["futur", "future", "roadmap", "prospective"]
        case "08_ESG.md":             return ["esg", "durabilité", "sustainability", "carbone"]
        case "09_SWOT.md":            return ["swot"]
        case "10_RH.md":              return ["rh", "ressources humaines", "human resources", "culture", "glassdoor"]
        case "RAPPORT_COMPLET.md":    return ["rapport", "report", "complet", "synthèse finale"]
        case "BRIEF.md":              return ["brief", "résumé", "synthèse"]
        default:                      return [section.title.lowercased()]
        }
    }

    private func entryColor(_ kind: LogEntry.Kind) -> Color {
        switch kind {
        case .search: return .blue
        case .fetch:  return .cyan
        case .write:  return .green
        case .agent:  return .purple
        case .bash:   return .orange
        case .done:   return .green
        default:      return .secondary
        }
    }

    private func startPolling() {
        let dir = outputDir
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            var found: Set<String> = []
            for s in auditSections {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent(s.filename).path) {
                    found.insert(s.filename)
                }
            }
            Task { @MainActor in filesOnDisk = found }
        }
    }
}

// MARK: - LiveStatus

enum LiveStatus: Equatable {
    case pending, running, done
}

// MARK: - LiveSectionRow

private struct LiveSectionRow: View {
    let section: AuditSection
    let status: LiveStatus
    let recentOp: String?
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                statusIcon
                Text(section.title)
                    .font(.system(.callout, weight: status == .running ? .semibold : .regular))
                    .foregroundStyle(labelColor)
                Spacer(minLength: 0)
                if status == .done {
                    Text("✓").font(.caption2).foregroundStyle(.green)
                }
            }

            // Opération récente sous le nom de la section
            if status == .running, let op = recentOp {
                Text(op)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 25)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.4), value: status)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
                .frame(width: 16)
                .transition(.scale.combined(with: .opacity))
        case .running:
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.rotate, options: .repeating)
                .frame(width: 16)
                .transition(.opacity)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
        }
    }

    private var labelColor: Color {
        switch status {
        case .done:    return .primary
        case .running: return .accentColor
        case .pending: return .secondary
        }
    }
}
