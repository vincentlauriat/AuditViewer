import Foundation

// MARK: - AuditEntry
//
// Représente un audit découvert dans un dossier racine (mode multi-audits).
// Pendant macOS de `AuditEntry` côté iOS (`ios/Sources/AuditStoreIOS.swift`) :
// les deux cibles ne partagent pas leurs Sources (seul `AuditManifest.swift` l'est),
// d'où cette définition dédiée.

struct AuditEntry: Identifiable, Sendable {
    let id: String          // slug dérivé du nom de dossier (ex : "mlx", "databricks")
    let dir: URL
    var manifest: AuditManifest?
    var title: String       // subject depuis le manifest, ou H1 de 00_RESUME_EXECUTIF.md
    var auditDate: String?
    var status: String?     // "complete" | "partial" | "canceled" | nil (legacy)
    var sourcesCount: Int?
    var depth: String?
    var options: [String]?
}
