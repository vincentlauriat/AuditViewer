import Foundation
import Observation

// MARK: - AuditEntry

struct AuditEntry: Identifiable, Sendable {
    let id: String          // slug (ex : "mlx", "databricks")
    let dir: URL
    var manifest: AuditManifest?
    var title: String       // subject depuis manifest, ou H1 de 00_RESUME_EXECUTIF.md
    var auditDate: String?
    var status: String?     // "complete" | "partial" | "canceled" | nil (legacy)
    var sourcesCount: Int?
    var depth: String?
    var options: [String]?
}

// MARK: - AuditStoreIOS

@MainActor @Observable final class AuditStoreIOS {

    var audits: [AuditEntry] = []
    var isLoading = false
    var errorMessage: String? = nil

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let root = ResearchVaultReader.researchRootURL() else {
            errorMessage = "Dossier Research introuvable."
            return
        }

        let dirs = await Task.detached(priority: .userInitiated) {
            ResearchVaultReader.discoverAuditDirs(root: root)
        }.value

        var entries: [AuditEntry] = []
        for dir in dirs {
            if let entry = await Self.loadEntry(dir: dir) {
                entries.append(entry)
            }
        }

        // Tri par date décroissante, puis par nom
        audits = entries.sorted {
            if let d0 = $0.auditDate, let d1 = $1.auditDate, d0 != d1 {
                return d0 > d1
            }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Chargement d'une entrée

    private static func loadEntry(dir: URL) async -> AuditEntry? {
        let slug = String(dir.lastPathComponent.dropFirst("audit-".count))
        guard !slug.isEmpty else { return nil }

        return await Task.detached(priority: .utility) {
            // 1. Essai manifest v1
            let manifestURL = dir.appendingPathComponent("_manifest.json")
            if let data = ResearchVaultReader.readFile(at: manifestURL),
               let manifest = try? JSONDecoder().decode(AuditManifest.self, from: data) {
                let title = manifest.subject ?? slug
                return AuditEntry(
                    id: slug,
                    dir: dir,
                    manifest: manifest,
                    title: title,
                    auditDate: manifest.auditDate,
                    status: manifest.status,
                    sourcesCount: manifest.sourcesCount,
                    depth: manifest.depth,
                    options: manifest.options
                )
            }

            // 2. Fallback legacy : lire H1 de 00_RESUME_EXECUTIF.md
            let resumeURL = dir.appendingPathComponent("00_RESUME_EXECUTIF.md")
            let title: String
            if let data = ResearchVaultReader.readFile(at: resumeURL),
               let text = String(data: data, encoding: .utf8) {
                title = Self.extractH1(from: text) ?? slug
            } else {
                title = slug
            }

            return AuditEntry(
                id: slug,
                dir: dir,
                manifest: nil,
                title: title,
                auditDate: nil,
                status: nil,
                sourcesCount: nil,
                depth: nil,
                options: nil
            )
        }.value
    }

    // MARK: - Helpers

    /// Extrait le premier titre H1 du Markdown (après le frontmatter YAML éventuel).
    nonisolated private static func extractH1(from text: String) -> String? {
        let stripped = stripYAMLFrontmatter(text)
        for line in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("# ") {
                return String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Supprime le frontmatter YAML `---\n...\n---\n` en début de fichier.
    nonisolated static func stripYAMLFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let lines = text.components(separatedBy: "\n")
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let rest = lines.dropFirst(i + 1).joined(separator: "\n")
                return rest.trimmingCharacters(in: .newlines)
            }
            i += 1
        }
        return text
    }
}
