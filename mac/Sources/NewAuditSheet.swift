import AppKit
import SwiftUI

struct NewAuditSheet: View {
    @Environment(AuditStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // ── Formulaire ─────────────────────────────────────────────────────────────
    @State private var subject: String = ""
    @State private var options: AuditOptions = AuditOptions()
    @State private var outputPath: String = ""

    // ── Progression ────────────────────────────────────────────────────────────
    @State private var isRunning: Bool = false
    @State private var launchedSubject: String = ""
    @State private var launchedOptions: AuditOptions = AuditOptions()
    @State private var launchedOutputDir: URL?

    private var outputDir: URL {
        URL(fileURLWithPath: outputPath.isEmpty ? defaultOutputPath : outputPath)
    }

    private var defaultOutputPath: String {
        KeychainStore.researchRoot?.path
            ?? store.auditDir?.deletingLastPathComponent().path
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 16)

            if isRunning, let dir = launchedOutputDir {
                progressPhase(dir: dir)
            } else {
                formPhase
            }
        }
        .padding(24)
        .frame(width: 520)
        .animation(.easeInOut(duration: 0.3), value: isRunning)
        .onAppear { outputPath = defaultOutputPath }
        .sheet(item: Binding(
            get: { store.pendingQuestion },
            set: { _ in }
        )) { question in
            QuestionSheet(question: question).environment(store)
        }
    }

    // MARK: - Header (commun)

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isRunning ? "gearshape.2" : "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.rotate, options: isRunning ? .repeating : .nonRepeating)
            VStack(alignment: .leading, spacing: 1) {
                Text(isRunning ? "Audit en cours" : "Nouveau rapport d'audit")
                    .font(.headline)
                if isRunning {
                    Text(launchedSubject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(isRunning)
        }
    }

    // MARK: - Formulaire

    private var formPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sujet
            VStack(alignment: .leading, spacing: 6) {
                Text("Sujet à auditer").font(.callout.weight(.medium))
                TextField("ex: Apple, Tesla Model Y, marché des LLM", text: $subject)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { launchIfReady() }
            }

            Divider()

            // Profondeur + Mode (côte à côte)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profondeur").font(.callout.weight(.medium))
                    Picker("", selection: $options.depth) {
                        Text("Rapide (~10 sources)").tag("quick")
                        Text("Complet (~30 sources)").tag("full")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Divider().frame(height: 60)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode de recherche").font(.callout.weight(.medium))
                    Picker("", selection: $options.mode) {
                        Text("Parallèle (rapide)").tag("parallel")
                        Text("Séquentiel").tag("sequential")
                        Text("Solo (1 agent)").tag("solo")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }

            // Langue + Verbose
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Langue du rapport").font(.callout.weight(.medium))
                    Picker("", selection: $options.lang) {
                        Text("Français").tag("fr")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                Spacer()
                Toggle("Verbose", isOn: $options.verbose)
                    .toggleStyle(.checkbox)
            }

            // Modules optionnels
            DisclosureGroup("Modules optionnels") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 20) {
                        Toggle("SWOT", isOn: $options.swot).toggleStyle(.checkbox)
                        Toggle("ESG / Durabilité", isOn: $options.esg).toggleStyle(.checkbox)
                        Toggle("RH / Culture", isOn: $options.rh).toggleStyle(.checkbox)
                    }
                    HStack(spacing: 20) {
                        Toggle("Sources à surveiller (--watch)", isOn: $options.watch).toggleStyle(.checkbox)
                        Toggle("Brief uniquement (1 page)", isOn: $options.brief).toggleStyle(.checkbox)
                    }
                    if options.brief {
                        Text("Le mode Brief produit uniquement BRIEF.md et ignore les étapes 3-4.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Focus optionnel
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focus (optionnel)").font(.caption.weight(.medium))
                        TextField("ex: financier, concurrence, technique", text: $options.focus)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }
                }
                .padding(.top, 8)
            }
            .font(.callout.weight(.medium))

            // Dossier de sortie
            VStack(alignment: .leading, spacing: 6) {
                Text("Dossier de sortie").font(.callout.weight(.medium))
                HStack {
                    Text(outputDir.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choisir…") { pickOutputDir() }.controlSize(.small)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("Lancer l'audit") { launchIfReady() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Phase de progression

    private func progressPhase(dir: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Arbre des agents
            AuditProgressView(
                outputDir: dir,
                subject: launchedSubject,
                options: launchedOptions
            )
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            // Feed de logs Claude (collapsible)
            logsSection

            Divider()

            HStack {
                Text("Rapport dans \(dir.lastPathComponent)/")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    LogsPanelController.shared.open(store: store)
                } label: {
                    Label("Console", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .overlay(alignment: .topTrailing) {
                    if store.isRunningAudit {
                        Circle().fill(Color.green).frame(width: 7, height: 7).offset(x: 3, y: -3)
                    }
                }
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    @ViewBuilder
    private var logsSection: some View {
        DisclosureGroup("Logs") {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.processOutput.isEmpty ? "En attente…" : store.processOutput)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("log-bottom")
                }
                .frame(height: 110)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: store.processOutput) { _, _ in
                    proxy.scrollTo("log-bottom")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if !store.eventLog.isEmpty {
            DisclosureGroup("Événements (\(store.eventLog.count))") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.eventLog.suffix(5), id: \.eventId) { event in
                        HStack(spacing: 6) {
                            Image(systemName: eventIcon(for: event.type))
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                            Text(eventDescription(event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func eventIcon(for type: AuditEvent.EventType) -> String {
        switch type {
        case .auditStart:               return "flag.fill"
        case .phaseStart, .stepStart:   return "play.fill"
        case .phaseDone, .stepDone:     return "checkmark"
        case .dimensionStart:           return "play.circle"
        case .dimensionDone:            return "checkmark.circle"
        case .progress:                 return "chart.bar.fill"
        case .search:                   return "magnifyingglass"
        case .source:                   return "link"
        case .fileWritten:              return "doc.badge.plus"
        case .question, .answer:        return "questionmark.circle"
        case .error:                    return "exclamationmark.triangle"
        case .auditComplete:            return "checkmark.seal.fill"
        case .auditCanceled, .auditCancelled: return "xmark.circle"
        default:                        return "circle.fill"
        }
    }

    private func eventDescription(_ e: AuditEvent) -> String {
        switch e.type {
        case .auditStart:    return "🚀 \(e.subject ?? "Audit") démarré"
        case .phaseStart, .stepStart:   return "▶ \(e.label ?? e.phase ?? e.dimension ?? "…")"
        case .phaseDone, .stepDone:     return "✓ \(e.label ?? e.phase ?? e.dimension ?? "…")"
        case .dimensionStart: return "▶ \(e.label ?? e.dimension ?? "…")"
        case .dimensionDone:  return "✓ \(e.label ?? e.dimension ?? "…")"
        case .progress:      return "📊 \(Int(e.pct ?? 0)) %"
        case .search:        return "🔍 \(e.query ?? "…")"
        case .source:        return "📄 \(e.title ?? e.url ?? "…")"
        case .fileWritten:   return "📝 \(e.file ?? "…")"
        case .question:      return "❓ Question en attente"
        case .answer:        return "💬 Réponse : \(e.value ?? "…")"
        case .error:         return "⚠️ \(e.message ?? "Erreur")"
        case .auditComplete: return "✅ Audit terminé"
        case .auditCanceled, .auditCancelled: return "🛑 Annulé (\(e.reason ?? "—"))"
        default:             return e.message ?? e.rawType
        }
    }

    // MARK: - Actions

    private func pickOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choisir le dossier de sortie"
        panel.prompt = "Choisir"
        panel.directoryURL = outputDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputPath = url.path
    }

    private func launchIfReady() {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isRunning else { return }

        let slug = AuditStore.slugify(trimmed)

        launchedSubject = trimmed
        launchedOptions = options
        // AuditProgressView surveille le sous-dossier créé par le skill
        let auditSubDir = outputDir.appendingPathComponent("audit-\(slug)")
        try? FileManager.default.createDirectory(at: auditSubDir, withIntermediateDirectories: true)
        store.startWatchingEvents(in: auditSubDir)
        launchedOutputDir = auditSubDir
        isRunning = true

        Task {
            // runAudit reçoit le dossier parent (crée audit-{slug}/ dedans)
            await store.runAudit(subject: trimmed, options: options, outputDir: outputDir)
        }
    }
}
