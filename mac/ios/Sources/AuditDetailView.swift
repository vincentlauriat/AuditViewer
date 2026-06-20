import SwiftUI

// MARK: - AuditDetailView
//
// Vue détail d'un audit avec 4 onglets :
// 1. Synthèse   — header + KPIs
// 2. Dimensions — liste des sections
// 3. Sources    — liste des sources
// 4. Rapport    — RAPPORT_COMPLET.md (lazy)

struct AuditDetailView: View {
    let entry: AuditEntry

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: Onglet 1 — Synthèse
            synthèseTab
                .tabItem { Label("Synthèse", systemImage: "doc.text") }
                .tag(0)

            // MARK: Onglet 2 — Dimensions
            dimensionsTab
                .tabItem { Label("Dimensions", systemImage: "list.bullet.rectangle") }
                .tag(1)

            // MARK: Onglet 3 — Sources
            SourcesView(dir: entry.dir)
                .tabItem { Label("Sources", systemImage: "link") }
                .tag(2)

            // MARK: Onglet 4 — Rapport
            NavigationStack {
                DimensionView(
                    dir: entry.dir,
                    filename: "RAPPORT_COMPLET.md",
                    title: "Rapport complet"
                )
            }
            .tabItem { Label("Rapport", systemImage: "doc.richtext") }
            .tag(3)
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Onglet Synthèse

    private var synthèseTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // En-tête
                headerSection

                // KPIs
                if entry.manifest != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Indicateurs clés")
                            .font(.headline)
                            .padding(.horizontal)
                        KPIGridView(dir: entry.dir)
                            .padding(.horizontal)
                    }
                }

                // Dimensions disponibles (mini aperçu)
                if let dims = entry.manifest?.dimensions, !dims.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dimensions")
                            .font(.headline)
                            .padding(.horizontal)
                        dimensionChips(dims: dims)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - En-tête de la fiche

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    if let date = entry.auditDate {
                        Text(date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let status = entry.status {
                    StatusBadge(status: status)
                }
            }

            // Badges : depth + options
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let depth = entry.depth {
                        metaBadge(depth, color: .blue)
                    }
                    if let opts = entry.options {
                        ForEach(opts, id: \.self) { opt in
                            metaBadge(opt, color: .purple)
                        }
                    }
                    if let count = entry.sourcesCount, count > 0 {
                        metaBadge("\(count) sources", color: .green)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func metaBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Chips dimensions (aperçu dans Synthèse)

    private func dimensionChips(dims: [AuditManifest.Dimension]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(dims, id: \.key) { dim in
                HStack(spacing: 4) {
                    Circle()
                        .fill(dim.status == "done" ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(dim.key)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Onglet Dimensions

    private var dimensionsTab: some View {
        NavigationStack {
            dimensionsList
                .navigationTitle("Dimensions")
        }
    }

    @ViewBuilder
    private var dimensionsList: some View {
        // Depuis le manifest v1
        if let dims = entry.manifest?.dimensions, !dims.isEmpty {
            List(dims, id: \.key) { dim in
                NavigationLink(destination: DimensionView(
                    dir: entry.dir,
                    filename: dim.file ?? "\(dim.key).md",
                    title: dim.key.capitalized
                )) {
                    dimensionRow(dim: dim)
                }
            }
            .listStyle(.insetGrouped)
        } else {
            // Fallback : sections statiques
            List(auditSections.filter { $0.exists || !$0.isOptional }) { section in
                NavigationLink(destination: DimensionView(
                    dir: entry.dir,
                    filename: section.filename,
                    title: section.title
                )) {
                    Text(section.title)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func dimensionRow(dim: AuditManifest.Dimension) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(dim.key.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let count = dim.sourcesCount {
                    Text("\(count) sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let status = dim.status {
                Circle()
                    .fill(status == "done" ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - FlowLayout (disposition en flux pour les chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
