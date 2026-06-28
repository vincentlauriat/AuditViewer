import SwiftUI

// MARK: - KPIGridView (macOS)
//
// Grille 3-4 colonnes affichant les KPIs extraits de `_data.json`.
// Adaptation macOS du design iOS : cartes avec label, valeur+unité, période, badge "estimé".

struct KPIGridView: View {
    let dir: URL

    @State private var kpis: [AuditKpi] = []
    @State private var isLoading = true
    @State private var failed = false

    private let columns = [
        GridItem(.flexible(minimum: 140), spacing: 12),
        GridItem(.flexible(minimum: 140), spacing: 12),
        GridItem(.flexible(minimum: 140), spacing: 12),
        GridItem(.flexible(minimum: 140), spacing: 12),
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if kpis.isEmpty {
                Text("Aucun KPI disponible")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(kpis.enumerated()), id: \.offset) { _, kpi in
                        KPICellView(kpi: kpi)
                    }
                }
                .padding(4)
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
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(AuditDataKpis.self, from: data)
            else { return nil }
            return decoded.kpis
        }.value

        kpis = loaded ?? []
        if loaded == nil { failed = true }
    }
}

// MARK: - Cellule KPI (macOS)

struct KPICellView: View {
    let kpi: AuditKpi

    @Environment(\.colorScheme) private var scheme

    /// Teinte d'accent de la carte : orange pour un KPI estimé, bleu sinon.
    private var accent: Color { kpi.estimated == true ? .orange : .accentColor }

    private var cornerRadius: CGFloat { 14 }

    var body: some View {
        HStack(spacing: 0) {
            // Barre d'accent latérale
            Rectangle()
                .fill(accent.opacity(0.9))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 7) {
                // Label
                Text(kpi.label ?? kpi.key ?? "—")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Valeur + unité
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(kpi.value ?? "—")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = kpi.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                // Période + badge estimé
                HStack(spacing: 6) {
                    if let period = kpi.period, !period.isEmpty {
                        Text(period)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if kpi.estimated == true {
                        Text("estimé")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.08), radius: 5, x: 0, y: 2)
    }
}
