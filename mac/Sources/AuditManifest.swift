import Foundation

// MARK: - Artefacts JSON du contrat machine v1
//
// Modèles Codable (snake_case) des fichiers structurés produits par le skill
// `audit-report` : `_manifest.json`, `_sources.json`, `_data.json` (kpis).
// Tous tolèrent l'absence : les audits legacy de ~/Documents/Research n'ont
// pas ces fichiers et l'app retombe sur ses scans historiques (cf. AuditStore).

// MARK: - _manifest.json

struct AuditManifest: Codable, Sendable {
    var v: Int?
    var subject: String?
    var subjectType: String?
    var slug: String?
    var outputDir: String?
    var auditDate: String?
    var depth: String?              // "quick" | "full"
    var mode: String?               // "parallel" | "sequential" | "solo"
    var options: [String]?
    var status: String?             // "complete" | "partial" | "canceled"
    var dimensions: [Dimension]?
    var files: [FileEntry]?
    var sourcesCount: Int?
    var dataFile: String?
    var sourcesFile: String?
    var reportFile: String?

    struct Dimension: Codable, Sendable {
        var key: String
        var file: String?
        var status: String?
        var sourcesCount: Int?

        enum CodingKeys: String, CodingKey {
            case key, file, status
            case sourcesCount = "sources_count"
        }
    }

    struct FileEntry: Codable, Sendable {
        var name: String
        var kind: String?
    }

    enum CodingKeys: String, CodingKey {
        case v, subject, slug, depth, mode, options, status, dimensions, files
        case subjectType  = "subject_type"
        case outputDir    = "output_dir"
        case auditDate    = "audit_date"
        case sourcesCount = "sources_count"
        case dataFile     = "data_file"
        case sourcesFile  = "sources_file"
        case reportFile   = "report_file"
    }
}

// MARK: - _sources.json

struct SourcesFile: Codable, Sendable {
    var v: Int?
    var sources: [AuditSource]
}

struct AuditSource: Codable, Sendable, Identifiable {
    var id: Int
    var url: String
    var title: String?
    var tag: String?                // "Officielle" | "Analyste" | "Presse"
    var date: String?
    var dimensions: [String]?
    var stale: Bool?
}

// MARK: - _data.json (KPI v1)

struct AuditKpi: Codable, Sendable {
    var key: String?
    var label: String?
    // `value` peut être un nombre OU une chaîne OU null → décodage tolérant.
    var value: String?
    var unit: String?
    var period: String?
    var sourceId: Int?
    var estimated: Bool?

    enum CodingKeys: String, CodingKey {
        case key, label, value, unit, period, estimated
        case sourceId = "source_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        period = try c.decodeIfPresent(String.self, forKey: .period)
        sourceId = try c.decodeIfPresent(Int.self, forKey: .sourceId)
        estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated)
        // value : nombre, chaîne ou null → toujours stocké en String pour l'affichage.
        if let s = try? c.decode(String.self, forKey: .value) {
            value = s
        } else if let d = try? c.decode(Double.self, forKey: .value) {
            // Entier sans décimale affiché sans `.0`
            value = d == d.rounded() && abs(d) < 1e15
                ? NumberFormatter.localizedString(from: NSNumber(value: d), number: .decimal)
                : "\(d)"
        } else {
            value = nil
        }
    }
}

// Schéma v1 minimal de `_data.json` : on ne décode que les `kpis[]` ; le reste
// (financials, market…) reste rendu par le repli générique `renderJSON`.
struct AuditDataKpis: Codable, Sendable {
    var kpis: [AuditKpi]?
}
