import SwiftUI

// MARK: - KPIGridView
//
// Grille 2 colonnes affichant les KPIs extraits de `_data.json`.
// Chaque cellule : label, valeur+unité, période, badge "estimé".

struct KPIGridView: View {
    let dir: URL

    @State private var kpis: [AuditKpi] = []
    @State private var isLoading = true
    @State private var failed = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if kpis.isEmpty {
                EmptyView()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(kpis.enumerated()), id: \.offset) { _, kpi in
                        KPICellView(kpi: kpi)
                    }
                }
            }
        }
        .task { await loadKPIs() }
    }

    // MARK: - Chargement

    private func loadKPIs() async {
        isLoading = true
        defer { isLoading = false }

        let url = dir.appendingPathComponent("_data.json")
        let loaded: [AuditKpi]? = await Task.detached(priority: .utility) {
            guard let data = ResearchVaultReader.readFile(at: url),
                  let decoded = try? JSONDecoder().decode(AuditDataKpis.self, from: data)
            else { return nil }
            return decoded.kpis
        }.value

        kpis = loaded ?? []
        if loaded == nil { failed = true }
    }
}

// MARK: - Cellule KPI

struct KPICellView: View {
    let kpi: AuditKpi

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label
            Text(kpi.label ?? kpi.key ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Valeur + unité
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kpi.value ?? "—")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = kpi.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Période + badge estimé
            HStack(spacing: 6) {
                if let period = kpi.period, !period.isEmpty {
                    Text(period)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if kpi.estimated == true {
                    Text("estimé")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
