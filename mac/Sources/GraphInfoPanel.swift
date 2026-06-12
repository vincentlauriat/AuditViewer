import AppKit
import SwiftUI

/// Panneau flottant affiché sur la carte au double-clic d'un nœud Source ou Acteur.
/// Source : URLs du domaine (tag/date) + bouton « Ouvrir ».
/// Acteur : sections qui le mentionnent (cliquables) + « Mettre en évidence ».
struct GraphInfoPanel: View {
    let info: GraphInfo
    let store: AuditStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch info {
                    case let .source(_, _, items):
                        if items.isEmpty {
                            empty("Aucune URL trouvée pour ce domaine.")
                        } else {
                            ForEach(items) { sourceRow($0) }
                        }
                    case let .entity(_, nodeId, sections):
                        if sections.isEmpty {
                            empty("Aucune section ne mentionne cet acteur.")
                        } else {
                            ForEach(sections) { sec in
                                Button { store.openSectionFromGraphInfo(sec.id) } label: {
                                    Label(sec.title, systemImage: "doc.text")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Divider()
                        Button {
                            NotificationCenter.default.post(
                                name: .graphFocusNode, object: nil, userInfo: ["id": nodeId]
                            )
                        } label: {
                            Label("Mettre en évidence dans la carte", systemImage: "scope")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(radius: 12, y: 4)
        .padding(12)
    }

    // MARK: - Sous-vues

    private var header: some View {
        HStack {
            Label(title, systemImage: icon).font(.headline).lineLimit(1)
            Spacer()
            Button { store.dismissGraphInfo() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sourceRow(_ item: GraphSourceItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title ?? item.url).font(.callout).lineLimit(2)
            HStack(spacing: 6) {
                if let tag = item.tag { tagBadge(tag) }
                if let date = item.date {
                    Text(date).font(.caption2).foregroundStyle(.secondary)
                }
                if item.stale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .help("Donnée de plus d'un an")
                }
                Spacer()
                Button("Ouvrir") {
                    if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tagColor(tag).opacity(0.2), in: Capsule())
            .foregroundStyle(tagColor(tag))
    }

    // MARK: - Helpers

    private var title: String {
        switch info {
        case let .source(domain, _, _): return domain
        case let .entity(name, _, _):   return name
        }
    }

    private var icon: String {
        switch info {
        case .source: return "globe"
        case .entity: return "person.fill"
        }
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "Officielle": return .blue
        case "Analyste":   return .purple
        case "Presse":     return .teal
        default:           return .secondary
        }
    }
}
