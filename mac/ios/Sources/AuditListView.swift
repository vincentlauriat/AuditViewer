import SwiftUI
import UniformTypeIdentifiers

// MARK: - AuditListView
//
// Liste tous les audits du dossier Research/.
// - iPad (horizontalSizeClass == .regular) : NavigationSplitView deux colonnes
// - iPhone : NavigationStack simple

struct AuditListView: View {
    @Environment(AuditStoreIOS.self) private var store
    @State private var selectedId: String? = nil
    @State private var showingFolderPicker = false

    var body: some View {
        Group {
            NavigationSplitView {
                listContent
                    .navigationTitle("Audits")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                showingFolderPicker = true
                            } label: {
                                Label("Dossier Research", systemImage: "folder")
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if store.isLoading {
                                ProgressView()
                            } else {
                                Button {
                                    Task { await store.refresh() }
                                } label: {
                                    Label("Recharger", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                    }
            } detail: {
                if let id = selectedId,
                   let entry = store.audits.first(where: { $0.id == id }) {
                    AuditDetailView(entry: entry)
                } else {
                    ContentUnavailableView(
                        "Sélectionner un audit",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handlePicked(result)
        }
        .task { await store.refresh() }
    }

    // MARK: - Sélection du dossier

    private func handlePicked(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        Task { await store.setResearchFolder(url) }
    }

    // MARK: - Contenu de la liste

    @ViewBuilder
    private var listContent: some View {
        if store.isLoading && store.audits.isEmpty {
            loadingState
        } else if store.audits.isEmpty {
            emptyState
        } else {
            List(store.audits, selection: $selectedId) { entry in
                AuditRowView(entry: entry)
                    .tag(entry.id)
            }
            .refreshable { await store.refresh() }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - État de chargement

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Recherche des audits…")
                .font(.headline)
            Text("Premier accès : téléchargement depuis iCloud.\nCela peut prendre un moment.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - État vide

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun audit", systemImage: "folder.badge.questionmark")
        } description: {
            Text(store.hasFolder
                 ? "Le dossier choisi ne contient aucun `audit-*/`.\nVérifiez le dossier ou ajoutez vos audits."
                 : "Choisissez votre dossier Research dans Fichiers\n(iCloud Drive ou « Sur mon iPhone »).")
                .font(.callout)
                .foregroundStyle(.secondary)
        } actions: {
            Button {
                showingFolderPicker = true
            } label: {
                Label(store.hasFolder ? "Changer de dossier…" : "Choisir le dossier Research…",
                      systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Ligne d'audit

struct AuditRowView: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let status = entry.status {
                    StatusBadge(status: status)
                }
            }

            HStack(spacing: 12) {
                if let date = entry.auditDate {
                    Label(date, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let count = entry.sourcesCount, count > 0 {
                    Label("\(count) sources", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let depth = entry.depth {
                    Text(depth)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Badge de statut

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    private var label: String {
        switch status {
        case "complete":  return "Complet"
        case "partial":   return "Partiel"
        case "canceled":  return "Annulé"
        default:          return status
        }
    }

    private var color: Color {
        switch status {
        case "complete":  return .green
        case "partial":   return .orange
        case "canceled":  return .red
        default:          return .secondary
        }
    }
}
