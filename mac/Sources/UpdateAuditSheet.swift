import AppKit
import SwiftUI

struct UpdateAuditSheet: View {
    @Environment(AuditStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var options: AuditOptions = AuditOptions()
    @State private var isRunning: Bool = false
    @State private var isDone: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 16)

            if isRunning || isDone, let dir = store.auditDir {
                progressPhase(dir: dir)
            } else {
                configPhase
            }
        }
        .padding(24)
        .frame(width: 520)
        .animation(.easeInOut(duration: 0.3), value: isRunning)
        .onAppear { loadOptions() }
        .sheet(item: Binding(
            get: { store.pendingQuestion },
            set: { _ in }
        )) { question in
            QuestionSheet(question: question).environment(store)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill"
                             : isRunning ? "arrow.clockwise.circle.fill"
                             : "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(isDone ? .green : Color.accentColor)
                .symbolEffect(.rotate, options: isRunning ? .repeating : .nonRepeating)
            VStack(alignment: .leading, spacing: 1) {
                Text(isDone ? "Mise à jour terminée"
                     : isRunning ? "Mise à jour en cours…"
                     : "Options de mise à jour")
                    .font(.headline)
                Text(store.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(isRunning)
        }
    }

    // MARK: - Phase de configuration

    private var configPhase: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Infos sur l'audit existant
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.auditDir?.lastPathComponent ?? "")
                        .font(.callout.weight(.medium))
                    if let dir = store.auditDir {
                        Text(dir.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Divider()

            // Profondeur + Mode
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
                    Text("Mode").font(.callout.weight(.medium))
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
                    Text("Langue").font(.callout.weight(.medium))
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
                    Divider()
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

            Divider()

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Relancer l'audit") { startUpdate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Phase de progression

    private func progressPhase(dir: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AuditProgressView(
                outputDir: dir,
                subject: store.subject,
                options: options
            )
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

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

            Divider()

            HStack {
                if isDone {
                    Label(
                        "\(store.changedSectionsCount) section\(store.changedSectionsCount > 1 ? "s" : "") modifiée\(store.changedSectionsCount > 1 ? "s" : "")",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Text("Mise à jour de « \(store.subject) »")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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

    // MARK: - Actions

    private func loadOptions() {
        if let dir = store.auditDir,
           let saved = AuditStore.loadSavedOptions(from: dir) {
            options = saved
        } else {
            options = store.lastOptions
        }
        if let depth = store.meta?.depth { options.depth = depth }
    }

    private func startUpdate() {
        guard !isRunning, let dir = store.auditDir else { return }
        isRunning = true
        store.startWatchingEvents(in: dir)
        Task {
            await store.rerunAuditWith(options: options)
            isRunning = false
            isDone = true
        }
    }
}
