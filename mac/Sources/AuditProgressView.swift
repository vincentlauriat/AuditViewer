import SwiftUI

// MARK: - Model

enum NodeStatus { case pending, running, done }

struct ProgressNode: Identifiable {
    let id: String
    let label: String
    let depth: Int
    let watchFile: String?   // nil = status inféré
    var isGroup: Bool = false
    var status: NodeStatus = .pending
}

// MARK: - View

struct AuditProgressView: View {
    @Environment(AuditStore.self) private var store

    let outputDir: URL
    let subject: String
    let options: AuditOptions

    @State private var nodes: [ProgressNode] = []
    @State private var timer: Timer?
    @State private var spinAngle: Double = 0

    // Propriétés dérivées des options pour la clarté
    private var depth: String { options.depth }
    private var isBrief: Bool { options.brief }

    var isDone: Bool {
        nodes.last?.status == .done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titre
            HStack(spacing: 8) {
                Image(systemName: isDone ? "checkmark.seal.fill" : "gearshape.2")
                    .foregroundStyle(isDone ? .green : Color.accentColor)
                    .symbolEffect(.rotate, options: isDone ? .nonRepeating : .repeating)
                Text(isDone ? "Audit terminé" : "Audit en cours…")
                    .font(.headline)
                Spacer()
                Text(subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 12)

            // Barre de progression chiffrée (events v1 `progress.pct`)
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

            // Arbre
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    NodeRow(
                        node: node,
                        isLast: isLastAtDepth(index: index, depth: node.depth)
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: nodes.map(\.status.rawValue))
        }
        .onAppear { buildNodes(); startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Node row

    struct NodeRow: View {
        let node: ProgressNode
        let isLast: Bool
        @State private var pulse = false

        var body: some View {
            HStack(spacing: 0) {
                // Indentation avec connecteurs ASCII-art
                if node.depth > 0 {
                    Text("   ")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.clear)
                    ForEach(0..<(node.depth - 1), id: \.self) { _ in
                        Text("│  ")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    Text(isLast ? "└─ " : "├─ ")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }

                // Icône de statut
                statusIcon
                    .frame(width: 18)

                // Label
                Text(node.label)
                    .font(node.isGroup ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(labelColor)
                    .padding(.leading, 6)

                Spacer()

                // Badge durée (si done)
                if node.status == .done, !node.isGroup {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.trailing, 4)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .background(
                node.status == .running
                    ? Color.accentColor.opacity(pulse ? 0.08 : 0.02)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .onAppear {
                if node.status == .running {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
            .onChange(of: node.status) { _, new in
                pulse = (new == .running)
            }
        }

        @ViewBuilder
        var statusIcon: some View {
            switch node.status {
            case .pending:
                Image(systemName: node.isGroup ? "circle.grid.3x3" : "circle")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            case .running:
                if node.isGroup {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.breathe, options: .repeating)
                } else {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.rotate, options: .repeating)
                }
            case .done:
                Image(systemName: node.isGroup ? "checkmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }

        var labelColor: Color {
            switch node.status {
            case .pending: return Color(nsColor: .tertiaryLabelColor)
            case .running: return Color(nsColor: .labelColor)
            case .done:    return Color(nsColor: .secondaryLabelColor)
            }
        }
    }

    // MARK: - Build

    private func buildNodes() {
        // Sections standard (quick = 4 prioritaires, full = 7)
        var sectionNodes: [ProgressNode] = [
            ProgressNode(id: "historique",   label: "Historique",    depth: 1, watchFile: "01_HISTORIQUE.md"),
            ProgressNode(id: "marche",       label: "Marché",        depth: 1, watchFile: "02_MARCHE.md"),
            ProgressNode(id: "technique",    label: "Technique",     depth: 1, watchFile: "03_TECHNIQUE.md"),
            ProgressNode(id: "tarification", label: "Tarification",  depth: 1, watchFile: "04_TARIFICATION.md"),
            ProgressNode(id: "concurrence",  label: "Concurrence",   depth: 1, watchFile: "05_CONCURRENCE.md"),
            ProgressNode(id: "financier",    label: "Financier",     depth: 1, watchFile: "06_FINANCIER.md"),
            ProgressNode(id: "futur",        label: "Futur",         depth: 1, watchFile: "07_FUTUR.md"),
        ]
        if depth == "quick" { sectionNodes = Array(sectionNodes.prefix(4)) }

        // Sections optionnelles
        var optionalNodes: [ProgressNode] = []
        if options.esg  { optionalNodes.append(ProgressNode(id: "esg",  label: "ESG / Durabilité", depth: 0, watchFile: "08_ESG.md")) }
        if options.swot { optionalNodes.append(ProgressNode(id: "swot", label: "SWOT",             depth: 0, watchFile: "09_SWOT.md")) }
        if options.rh   { optionalNodes.append(ProgressNode(id: "rh",   label: "RH / Culture",     depth: 0, watchFile: "10_RH.md")) }

        // Nœuds finaux selon le mode
        let finalNodes: [ProgressNode]
        if isBrief {
            finalNodes = [ProgressNode(id: "brief", label: "Génération du brief", depth: 0, watchFile: "BRIEF.md")]
        } else {
            var tail: [ProgressNode] = [
                ProgressNode(id: "resume",  label: "Résumé exécutif",               depth: 0, watchFile: "00_RESUME_EXECUTIF.md"),
            ]
            tail += optionalNodes
            tail.append(ProgressNode(id: "complet", label: "Assemblage du rapport complet", depth: 0, watchFile: "RAPPORT_COMPLET.md"))
            finalNodes = tail
        }

        nodes = [
            ProgressNode(id: "recon",    label: "Reconnaissance initiale", depth: 0, watchFile: nil),
            ProgressNode(id: "parallel", label: "Recherche parallèle",     depth: 0, watchFile: nil, isGroup: true),
        ] + sectionNodes + finalNodes
    }

    // MARK: - Polling

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            Task { @MainActor in poll() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func poll() {
        let fm = FileManager.default

        // Le skill crée le dossier dès l'étape 0 — tant qu'il n'existe pas, on attend
        guard fm.fileExists(atPath: outputDir.path) else { return }

        func fileExists(_ name: String) -> Bool {
            fm.fileExists(atPath: outputDir.appendingPathComponent(name).path)
        }

        // ── Sections standard ───────────────────────────────────────────────
        let sectionIds = ["historique","marche","technique","tarification","concurrence","financier","futur"]
        var doneSections = 0
        for i in nodes.indices where sectionIds.contains(nodes[i].id) {
            // Terminée si le fichier existe OU si un event `dimension_done` l'a signalée.
            let doneByFile  = nodes[i].watchFile.map(fileExists) ?? false
            let doneByEvent = store.completedDimensions.contains(nodes[i].id)
            if doneByFile || doneByEvent {
                if nodes[i].status != .done { withAnimation { nodes[i].status = .done } }
                doneSections += 1
            }
        }
        let expectedSections = depth == "quick" ? 4 : 7
        let anySection  = doneSections > 0
        let allSections = doneSections >= expectedSections

        // ── Mode brief ──────────────────────────────────────────────────────
        if isBrief {
            let briefDone = fileExists("BRIEF.md")
            setStatus("recon",   to: anySection ? .done : .running)
            setStatus("parallel", to: allSections ? .done : anySection ? .running : .pending)
            for i in nodes.indices where sectionIds.contains(nodes[i].id) {
                if nodes[i].status == .pending { withAnimation { nodes[i].status = .running } }
            }
            if briefDone {
                setStatus("brief", to: .done)
                stopPolling()
            } else if anySection {
                setStatus("brief", to: .running)
            }
            return
        }

        // ── Mode normal ─────────────────────────────────────────────────────
        let resumeDone = fileExists("00_RESUME_EXECUTIF.md")
        let esgDone    = fileExists("08_ESG.md")
        let swotDone   = fileExists("09_SWOT.md")
        let rhDone     = fileExists("10_RH.md")
        let complet    = fileExists("RAPPORT_COMPLET.md")

        // Recon
        setStatus("recon", to: anySection ? .done : .running)

        // Groupe parallèle
        setStatus("parallel", to: complet ? .done : allSections ? .done : anySection ? .running : .pending)

        // Sections individuelles → running dès que recon est actif
        if anySection || nodes[nodeIndex("recon")!].status != .pending {
            for i in nodes.indices where sectionIds.contains(nodes[i].id) {
                if nodes[i].status == .pending { withAnimation { nodes[i].status = .running } }
            }
        }

        // Résumé
        if resumeDone       { setStatus("resume", to: .done) }
        else if allSections { setStatus("resume", to: .running) }

        // Sections optionnelles (démarrent après résumé exécutif)
        if options.esg {
            if esgDone            { setStatus("esg", to: .done) }
            else if resumeDone    { setStatus("esg", to: .running) }
        }
        if options.swot {
            if swotDone           { setStatus("swot", to: .done) }
            else if resumeDone    { setStatus("swot", to: .running) }
        }
        if options.rh {
            if rhDone             { setStatus("rh", to: .done) }
            else if resumeDone    { setStatus("rh", to: .running) }
        }

        // Rapport complet : attend toutes les optionnelles activées
        let optsDone = (!options.esg || esgDone) && (!options.swot || swotDone) && (!options.rh || rhDone)
        if complet              { setStatus("complet", to: .done) }
        else if resumeDone && optsDone { setStatus("complet", to: .running) }

        if complet { stopPolling() }
    }

    private func setStatus(_ id: String, to status: NodeStatus) {
        guard let i = nodeIndex(id), nodes[i].status != status else { return }
        withAnimation(.easeInOut(duration: 0.25)) { nodes[i].status = status }
    }

    private func nodeIndex(_ id: String) -> Int? {
        nodes.firstIndex(where: { $0.id == id })
    }

    private func isLastAtDepth(index: Int, depth: Int) -> Bool {
        for i in (index + 1)..<nodes.count {
            if nodes[i].depth == depth { return false }
            if nodes[i].depth < depth { break }
        }
        return true
    }
}

// MARK: - NodeStatus: Equatable + rawValue

extension NodeStatus: Equatable {
    var rawValue: Int {
        switch self { case .pending: 0; case .running: 1; case .done: 2 }
    }
}
