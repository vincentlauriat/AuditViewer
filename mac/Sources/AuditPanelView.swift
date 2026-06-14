import AppKit
import SwiftUI

// MARK: - Mode

enum AuditPanelMode: Equatable {
    case new
    case update
}

// MARK: - AuditPanelView

struct AuditPanelView: View {
    @Environment(AuditStore.self) private var store

    let mode: AuditPanelMode

    // Config
    @State private var subject: String = ""
    @State private var options: AuditOptions = AuditOptions()
    @State private var outputPath: String = ""

    // Runtime
    @State private var isRunning = false
    @State private var isDone = false
    @State private var progressDir: URL? = nil
    @State private var launchedOptions: AuditOptions = AuditOptions()
    @State private var launchedSubject: String = ""

    // Logs animation
    @State private var autoScroll = true
    @State private var highlightedId: UUID? = nil
    @State private var pulseActive = false

    private var outputDir: URL {
        URL(fileURLWithPath: outputPath.isEmpty ? defaultOutputPath : outputPath)
    }

    private var defaultOutputPath: String {
        KeychainStore.researchRoot?.path
            ?? store.auditDir?.deletingLastPathComponent().path
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
    }

    var body: some View {
        HSplitView {
            leftColumn
                .frame(minWidth: 220, maxWidth: 360)
            middleColumn
                .frame(minWidth: 240)
            rightColumn
                .frame(minWidth: 240)
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .onAppear {
            setupInitial()
            startPulse()
        }
        .sheet(item: Binding(
            get: { store.pendingQuestion },
            set: { _ in }
        )) { question in
            QuestionSheet(question: question).environment(store)
        }
    }

    // MARK: - Left column: options + launch button

    private var leftColumn: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Subject / folder info
                if mode == .update {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary).font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.auditDir?.lastPathComponent ?? "")
                                .font(.callout.weight(.medium)).lineLimit(1)
                            Text(store.auditDir?.deletingLastPathComponent().path ?? "")
                                .font(.caption).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sujet à auditer").font(.callout.weight(.medium))
                        TextField("ex: Apple, Tesla Model Y, LLM…", text: $subject)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { launch() }
                    }
                }

                Divider()

                // Profondeur
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profondeur").font(.callout.weight(.medium))
                    Picker("", selection: $options.depth) {
                        Text("Rapide (~10 sources)").tag("quick")
                        Text("Complet (~30 sources)").tag("full")
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                }

                // Mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode de recherche").font(.callout.weight(.medium))
                    Picker("", selection: $options.mode) {
                        Text("Parallèle (rapide)").tag("parallel")
                        Text("Séquentiel").tag("sequential")
                        Text("Solo (1 agent)").tag("solo")
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                }

                // Langue
                VStack(alignment: .leading, spacing: 6) {
                    Text("Langue du rapport").font(.callout.weight(.medium))
                    Picker("", selection: $options.lang) {
                        Text("English").tag("en")
                        Text("Français").tag("fr")
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                // Modules
                VStack(alignment: .leading, spacing: 10) {
                    Text("Modules optionnels").font(.callout.weight(.medium))
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle("SWOT", isOn: $options.swot).toggleStyle(.checkbox)
                        Toggle("ESG / Durabilité", isOn: $options.esg).toggleStyle(.checkbox)
                        Toggle("RH / Culture", isOn: $options.rh).toggleStyle(.checkbox)
                        Divider()
                        Toggle("Sources à surveiller", isOn: $options.watch).toggleStyle(.checkbox)
                        Toggle("Brief uniquement (1 page)", isOn: $options.brief).toggleStyle(.checkbox)
                        Toggle("Verbose", isOn: $options.verbose).toggleStyle(.checkbox)
                    }
                }

                // Focus
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus (optionnel)").font(.caption.weight(.medium))
                    TextField("ex: financier, concurrence…", text: $options.focus)
                        .textFieldStyle(.roundedBorder).font(.callout)
                }

                if mode == .new {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dossier de sortie").font(.caption.weight(.medium))
                        HStack(spacing: 6) {
                            Text(outputDir.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Button("…") { pickOutputDir() }.controlSize(.mini)
                        }
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(16)
        } // fin ScrollView

        Divider()

        // Bouton de lancement épinglé en bas de la colonne
        VStack(spacing: 8) {
            if isDone {
                Label("Terminé", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Relancer") { isDone = false; launch() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            if !isRunning {
                Button(mode == .new ? "Lancer l'audit" : "Relancer l'audit") { launch() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(mode == .new && subject.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65)
                    Text("En cours…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)

        } // fin VStack leftColumn
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Middle column: progression

    private var middleColumn: some View {
        VStack(spacing: 0) {
            // Mini header
            HStack(spacing: 6) {
                Image(systemName: isDone ? "checkmark.circle.fill"
                      : isRunning ? "gearshape.2.fill" : "clock")
                    .font(.caption)
                    .foregroundStyle(isDone ? Color.green : isRunning ? Color.accentColor : Color.secondary)
                    .symbolEffect(.rotate, options: isRunning ? .repeating : .nonRepeating)
                Text(isDone ? "Terminé" : isRunning ? "En cours…" : "En attente")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let dir = progressDir {
                LiveProgressView(
                    outputDir: dir,
                    subject: launchedSubject,
                    options: launchedOptions
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text(mode == .new
                         ? "Configurez les options\npuis lancez l'audit"
                         : "Ajustez les options\npuis relancez l'audit")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Right column: logs

    private var rightColumn: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    if store.isRunningAudit {
                        Circle()
                            .fill(OBColor.green.opacity(pulseActive ? 0.3 : 0.0))
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(OBColor.green.opacity(pulseActive ? 0.12 : 0.0))
                            .frame(width: 20, height: 20)
                    }
                    Circle()
                        .fill(store.isRunningAudit ? OBColor.green : OBColor.overlay)
                        .frame(width: 7, height: 7)
                }
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulseActive)

                Text("Console")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(OBColor.subtle)

                Spacer()

                Toggle("Scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OBColor.subtle)

                Text("\(store.logEntries.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OBColor.overlay)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.logEntries.removeAll() }
                } label: {
                    Image(systemName: "trash").font(.caption2).foregroundStyle(OBColor.subtle)
                }
                .buttonStyle(.borderless)
                .disabled(store.logEntries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OBColor.surface)

            logList
        }
        .background(OBColor.base)
    }

    @ViewBuilder
    private var logList: some View {
        if !store.logEntries.isEmpty {
            // Entrées parsées (stream-json) → vue stylisée
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.logEntries) { entry in
                            PanelLogRow(
                                entry: entry,
                                isHighlighted: entry.id == highlightedId,
                                isLast: entry.id == store.logEntries.last?.id,
                                pulse: pulseActive
                            )
                            .id(entry.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(duration: 0.3, bounce: 0.1), value: store.logEntries.count)
                }
                .background(OBColor.base)
                .onChange(of: store.logEntries.count) { _, _ in
                    guard let last = store.logEntries.last else { return }
                    flashHighlight(last.id)
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        } else if !store.processOutput.isEmpty {
            // Fallback : sortie brute Claude si le parsing stream-json n'a rien produit
            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.processOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(OBColor.text.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("raw-end")
                }
                .background(OBColor.base)
                .onChange(of: store.processOutput) { _, _ in
                    if autoScroll { proxy.scrollTo("raw-end") }
                }
            }
        } else {
            // État vide
            VStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 26))
                    .foregroundStyle(OBColor.overlay)
                Text(isRunning ? "Démarrage…" : "Aucun log")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OBColor.subtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OBColor.base)
        }
    }

    // MARK: - Footer

    // MARK: - Actions

    private func setupInitial() {
        if mode == .update {
            if let dir = store.auditDir,
               let saved = AuditStore.loadSavedOptions(from: dir) {
                options = saved
            } else {
                options = store.lastOptions
            }
            if let depth = store.meta?.depth { options.depth = depth }
        } else {
            outputPath = defaultOutputPath
        }
    }

    private func launch() {
        guard !isRunning else { return }
        isDone = false

        if mode == .new {
            let trimmed = subject.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let slug = AuditStore.slugify(trimmed)
            let subDir = outputDir.appendingPathComponent("audit-\(slug)")
            try? FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            store.startWatchingEvents(in: subDir)
            launchedSubject = trimmed
            launchedOptions = options
            progressDir = subDir
            isRunning = true
            Task {
                await store.runAudit(subject: trimmed, options: options, outputDir: outputDir)
                isRunning = false
                isDone = true
            }
        } else {
            guard let dir = store.auditDir else { return }
            store.startWatchingEvents(in: dir)
            launchedSubject = store.subject
            launchedOptions = options
            progressDir = dir
            isRunning = true
            Task {
                await store.rerunAuditWith(options: options)
                isRunning = false
                isDone = true
            }
        }
    }

    private func pickOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = outputDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputPath = url.path
    }

    private func flashHighlight(_ id: UUID) {
        highlightedId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.6)) { highlightedId = nil }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulseActive = true
        }
    }
}

// MARK: - PanelLogRow

private struct PanelLogRow: View {
    let entry: LogEntry
    let isHighlighted: Bool
    let isLast: Bool
    let pulse: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OBColor.overlay)
                .frame(width: 54, alignment: .trailing)
                .padding(.trailing, 7)

            RoundedRectangle(cornerRadius: 1)
                .fill(kindColor.opacity(isHighlighted ? 0.9 : 0.3))
                .frame(width: 2, height: 15)
                .padding(.trailing, 7)

            Image(systemName: entry.icon)
                .font(.system(size: 10))
                .foregroundStyle(kindColor)
                .frame(width: 13)
                .scaleEffect(isLast && pulse && needsPulse ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .padding(.trailing, 5)

            Text(entry.message)
                .font(.system(size: 11, design: entry.kind == .bash ? .monospaced : .default))
                .foregroundStyle(isHighlighted ? OBColor.text : labelColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background {
            if isHighlighted {
                kindColor.opacity(0.10)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 3)
            }
        }
        .contentShape(Rectangle())
    }

    private var kindColor: Color {
        switch entry.kind {
        case .search: return OBColor.blue
        case .fetch:  return OBColor.cyan
        case .write:  return OBColor.green
        case .bash:   return OBColor.peach
        case .agent:  return OBColor.purple
        case .read:   return OBColor.subtle
        case .text:   return OBColor.text
        case .info:   return OBColor.subtle
        case .error:  return OBColor.red
        case .done:   return OBColor.green
        }
    }

    private var labelColor: Color {
        switch entry.kind {
        case .error: return OBColor.red
        case .done:  return OBColor.green
        case .info:  return OBColor.subtle
        default:     return OBColor.text.opacity(0.85)
        }
    }

    private var needsPulse: Bool {
        switch entry.kind {
        case .search, .fetch, .agent, .bash: return true
        default: return false
        }
    }
}
