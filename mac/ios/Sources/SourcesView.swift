import SwiftUI

// MARK: - SourcesView
//
// Affiche les sources d'un audit depuis `_sources.json`.
// - Tri par tag : Officielle → Analyste → Presse → autres
// - Badge coloré par tag
// - Badge ⚠️ si stale
// - Dimensions citantes en chips

struct SourcesView: View {
    let dir: URL

    @State private var sources: [AuditSource] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if failed || sources.isEmpty {
                ContentUnavailableView(
                    "Sources indisponibles",
                    systemImage: "link.badge.slash",
                    description: Text("Le fichier _sources.json est absent ou vide.")
                )
            } else {
                sourcesList
            }
        }
        .task { await loadSources() }
    }

    // MARK: - Liste triée

    private var sortedSources: [AuditSource] {
        let order = ["Officielle": 0, "Analyste": 1, "Presse": 2]
        return sources.sorted { a, b in
            let oa = order[a.tag ?? ""] ?? 3
            let ob = order[b.tag ?? ""] ?? 3
            return oa == ob ? a.id < b.id : oa < ob
        }
    }

    private var sourcesList: some View {
        List(sortedSources) { source in
            SourceRowView(source: source)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Chargement

    private func loadSources() async {
        isLoading = true
        defer { isLoading = false }

        let url = dir.appendingPathComponent("_sources.json")
        let loaded: [AuditSource]? = await Task.detached(priority: .utility) {
            guard let data = ResearchVaultReader.readFile(at: url),
                  let decoded = try? JSONDecoder().decode(SourcesFile.self, from: data)
            else { return nil }
            return decoded.sources
        }.value

        if let loaded {
            sources = loaded
        } else {
            failed = true
        }
    }
}

// MARK: - Ligne source

struct SourceRowView: View {
    let source: AuditSource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Titre + badges
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title ?? source.url)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    if source.title != nil {
                        Text(source.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let tag = source.tag {
                        TagBadge(tag: tag)
                    }
                    if source.stale == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }

            // Métadonnées
            HStack(spacing: 12) {
                if let date = source.date {
                    Label(date, systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Dimensions citantes
                if let dims = source.dimensions, !dims.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(dims, id: \.self) { dim in
                                Text(dim)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.blue.opacity(0.8))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: source.url) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Badge tag

struct TagBadge: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch tag {
        case "Officielle": return .green
        case "Analyste":   return .orange
        case "Presse":     return .purple
        default:           return .secondary
        }
    }
}
