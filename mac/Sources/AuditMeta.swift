import Foundation

struct AuditMeta: Codable, Sendable {
    var subject: String
    var subjectType: String?
    var keyPlayers: [String]?
    var sector: String?
    var searchKeywords: [String]?
    var languageSources: String?
    var auditDate: String?
    var depth: String?
    var sourcesCount: Int?

    enum CodingKeys: String, CodingKey {
        case subject
        case subjectType     = "subject_type"
        case keyPlayers      = "key_players"
        case sector
        case searchKeywords  = "search_keywords"
        case languageSources = "language_sources"
        case auditDate       = "audit_date"
        case depth
        case sourcesCount    = "sources_count"
    }
}
