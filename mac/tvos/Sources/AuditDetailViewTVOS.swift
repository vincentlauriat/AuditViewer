import SwiftUI

// MARK: - Vue détail d'un audit (tvOS, 10-foot)
//
// Charge le contenu via HTTP (AuditAPIClient). 4 onglets :
// Synthèse (header + KPIs + dimensions), Dimensions (drill-down markdown),
// Sources, Rapport complet.

struct AuditDetailViewTVOS: View {
    let client: AuditAPIClient
    let audit: AuditAPIClient.AuditSummary

    @State private var manifest: AuditManifest?
    @State private var kpis: [AuditKpi] = []
    @State private var files: [String] = []
    @State private var loading = true

    private var subject: String {
        manifest?.subject ?? audit.subject ?? Self.prettify(audit.id)
    }

    /// "audit-iphone" → "Iphone" (titre de repli pour les audits sans manifest).
    private static func prettify(_ id: String) -> String {
        let s = id.hasPrefix("audit-") ? String(id.dropFirst(6)) : id
        return s.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// "01_HISTORIQUE.md" → "Historique".
    private static func sectionTitle(_ filename: String) -> String {
        let base = filename.replacingOccurrences(of: ".md", with: "")
        let stripped = String(base.drop(while: { $0.isNumber || $0 == "_" }))
        return stripped.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Fichier du rapport : manifest s'il existe, sinon repli sur les fichiers réels
    /// (RAPPORT_COMPLET puis résumé exécutif puis première section).
    private var reportFilename: String {
        if let rf = manifest?.reportFile, files.isEmpty || files.contains(rf) { return rf }
        if files.contains("RAPPORT_COMPLET.md") { return "RAPPORT_COMPLET.md" }
        if files.contains("00_RESUME_EXECUTIF.md") { return "00_RESUME_EXECUTIF.md" }
        return files.first(where: { !$0.hasPrefix("_") }) ?? "RAPPORT_COMPLET.md"
    }

    /// Sections à lister dans l'onglet Dimensions quand il n'y a pas de manifest :
    /// les `.md` de section (hors fichiers techniques `_*` et hors rapport complet).
    private var fallbackSections: [String] {
        files.filter { !$0.hasPrefix("_") && $0 != "RAPPORT_COMPLET.md" }
    }

    var body: some View {
        TabView {
            syntheseTab
                .tabItem { Label("Synthèse", systemImage: "doc.text") }

            dimensionsTab
                .tabItem { Label("Dimensions", systemImage: "list.bullet.rectangle") }

            NavigationStack {
                SourcesTVOSView(client: client, id: audit.id)
                    .navigationTitle("Sources")
            }
            .tabItem { Label("Sources", systemImage: "link") }

            NavigationStack {
                DimensionTVOSView(client: client, id: audit.id,
                                  filename: reportFilename,
                                  title: "Rapport")
            }
            .tabItem { Label("Rapport", systemImage: "doc.richtext") }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let m = try? client.manifest(audit.id)
        async let d = try? client.data(audit.id)
        async let f = try? client.files(audit.id)
        manifest = await m
        kpis = (await d)?.kpis ?? []
        files = (await f) ?? []
    }

    // MARK: Synthèse

    private var syntheseTab: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                if !kpis.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Indicateurs clés").font(.title2).fontWeight(.semibold)
                        kpiGrid
                    }
                }
                if let dims = manifest?.dimensions, !dims.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Dimensions").font(.title2).fontWeight(.semibold)
                        dimensionChips(dims)
                    }
                }
            }
            .padding(90)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(subject).font(.largeTitle).fontWeight(.bold)
            HStack(spacing: 14) {
                if let date = manifest?.auditDate ?? audit.auditDate {
                    Label(date, systemImage: "calendar").foregroundStyle(.secondary)
                }
                if let status = manifest?.status ?? audit.status { StatusBadgeTVOS(status: status) }
            }
            .font(.title3)

            HStack(spacing: 12) {
                if let depth = manifest?.depth ?? audit.depth { metaBadge(depth, .blue) }
                if let opts = manifest?.options { ForEach(opts, id: \.self) { metaBadge($0, .purple) } }
                if let n = manifest?.sourcesCount, n > 0 { metaBadge("\(n) sources", .green) }
            }
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, kpi in
                VStack(alignment: .leading, spacing: 8) {
                    Text(kpi.label ?? kpi.key ?? "—")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(kpi.value ?? "—").font(.title2).fontWeight(.semibold)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let u = kpi.unit, !u.isEmpty { Text(u).font(.callout).foregroundStyle(.secondary) }
                    }
                    if let p = kpi.period, !p.isEmpty {
                        Text(p).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .focusable()   // permet le défilement de l'onglet à la télécommande
            }
        }
    }

    private func dimensionChips(_ dims: [AuditManifest.Dimension]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            ForEach(dims, id: \.key) { dim in
                HStack(spacing: 8) {
                    Circle().fill(dim.status == "done" ? .green : .orange).frame(width: 10, height: 10)
                    Text(dim.key.capitalized).font(.callout).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .focusable()
            }
        }
    }

    private func metaBadge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.callout).fontWeight(.medium).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Dimensions

    private var dimensionsTab: some View {
        NavigationStack {
            List {
                if let dims = manifest?.dimensions, !dims.isEmpty {
                    ForEach(dims, id: \.key) { dim in
                        NavigationLink {
                            DimensionTVOSView(client: client, id: audit.id,
                                              filename: dim.file ?? "\(dim.key).md",
                                              title: dim.key.capitalized)
                        } label: {
                            HStack {
                                Text(dim.key.capitalized)
                                Spacer()
                                if let n = dim.sourcesCount { Text("\(n) sources").foregroundStyle(.secondary) }
                                if let s = dim.status {
                                    Circle().fill(s == "done" ? .green : .orange).frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                } else if !fallbackSections.isEmpty {
                    // Audit sans manifest : sections déduites des fichiers présents.
                    ForEach(fallbackSections, id: \.self) { name in
                        NavigationLink {
                            DimensionTVOSView(client: client, id: audit.id,
                                              filename: name, title: Self.sectionTitle(name))
                        } label: {
                            Text(Self.sectionTitle(name))
                        }
                    }
                } else {
                    Text("Aucune section disponible.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dimensions")
        }
    }
}

// MARK: - Détail d'une dimension / rapport (markdown via HTTP)

struct DimensionTVOSView: View {
    let client: AuditAPIClient
    let id: String
    let filename: String
    var title: String? = nil

    @State private var markdown: String?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView("Fichier indisponible", systemImage: "doc.text.slash", description: Text(filename))
            } else if let md = markdown {
                MarkdownTVOSView(markdown: md)
            }
        }
        .navigationTitle(title ?? filename)
        .task(id: filename) { await load() }   // recharge si le nom se résout après coup
    }

    private func load() async {
        loading = true
        failed = false
        defer { loading = false }
        do {
            markdown = stripYAMLFrontmatter(try await client.file(id, name: filename))
        } catch {
            failed = true
        }
    }
}

// MARK: - Sources (via HTTP)

struct SourcesTVOSView: View {
    let client: AuditAPIClient
    let id: String

    @State private var sources: [AuditSource] = []
    @State private var loading = true
    @State private var failed = false

    private var sorted: [AuditSource] {
        let order = ["Officielle": 0, "Analyste": 1, "Presse": 2]
        return sources.sorted { a, b in
            let oa = order[a.tag ?? ""] ?? 3, ob = order[b.tag ?? ""] ?? 3
            return oa == ob ? a.id < b.id : oa < ob
        }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed || sources.isEmpty {
                ContentUnavailableView("Sources indisponibles", systemImage: "link.badge.slash",
                                       description: Text("Aucune source partagée pour cet audit."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Lignes focusables : sur tvOS la liste ne défile (et n'est
                        // atteignable depuis la barre d'onglets) que via des cibles de focus.
                        ForEach(sorted) { source in
                            FocusableBlock {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        Text(source.title ?? source.url).fontWeight(.medium).lineLimit(2)
                                        Spacer()
                                        if let tag = source.tag { TagBadgeTVOS(tag: tag) }
                                        if source.stale == true {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        }
                                    }
                                    Text(source.url).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                    if let date = source.date {
                                        Label(date, systemImage: "calendar").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 90)
                    .padding(.vertical, 60)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            sources = try await client.sources(id).sources
        } catch {
            failed = true
        }
    }
}

// MARK: - Badges

struct StatusBadgeTVOS: View {
    let status: String
    var body: some View {
        Text(label).font(.callout).fontWeight(.semibold).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
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

struct TagBadgeTVOS: View {
    let tag: String
    var body: some View {
        Text(tag).font(.caption).fontWeight(.semibold).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
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
