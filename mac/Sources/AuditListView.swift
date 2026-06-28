import SwiftUI

// MARK: - AuditListView (macOS, mode racine)
//
// Liste plein écran de tous les audits découverts dans le dossier racine.
// Affichée par ContentView quand `auditDir == nil` et `browseMode`.
// Clic sur une ligne → `store.loadAuditDir(entry.dir)` (bascule en vue détail).

struct AuditListView: View {
    @Environment(AuditStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audits")
                    .font(.title2.weight(.semibold))
                if let root = store.browseRoot {
                    Text(root.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(root.path)
                }
            }

            Spacer()

            if store.isLoadingAudits {
                ProgressView().controlSize(.small)
            }

            Button {
                store.refreshRoot()
            } label: {
                Label("Recharger", systemImage: "arrow.clockwise")
            }
            .help("Re-scanner le dossier racine")
            .disabled(store.isLoadingAudits)

            Button {
                store.openRootFolder()
            } label: {
                Label("Changer de dossier…", systemImage: "folder")
            }
            .help("Choisir un autre dossier racine")
        }
        .padding(16)
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        if store.isLoadingAudits && store.audits.isEmpty {
            loadingState
        } else if store.audits.isEmpty {
            emptyState
        } else {
            List(store.audits) { entry in
                AuditRowView(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture { store.loadAuditDir(entry.dir) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Recherche des audits…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Aucun audit dans ce dossier")
                .font(.title3.weight(.medium))
            Text("Ce dossier ne contient aucun audit (dossier avec `_manifest.json` ou `00_RESUME_EXECUTIF.md`).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                store.openRootFolder()
            } label: {
                Label("Changer de dossier…", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ligne d'audit

struct AuditRowView: View {
    let entry: AuditEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let status = entry.status {
                        StatusBadge(status: status)
                    }
                }

                HStack(spacing: 12) {
                    if let date = entry.auditDate {
                        Label(date, systemImage: "calendar")
                    }
                    if let count = entry.sourcesCount, count > 0 {
                        Label("\(count) sources", systemImage: "link")
                    }
                    if let depth = entry.depth {
                        Text(depth)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
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
        case "complete": return "Complet"
        case "partial":  return "Partiel"
        case "canceled": return "Annulé"
        default:         return status
        }
    }

    private var color: Color {
        switch status {
        case "complete": return .green
        case "partial":  return .orange
        case "canceled": return .red
        default:         return .secondary
        }
    }
}
