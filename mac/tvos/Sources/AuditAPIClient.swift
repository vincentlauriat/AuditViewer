import Foundation

// MARK: - Client REST du serveur LAN AuditViewer (lecture seule)
//
// Consomme le contrat servi par LANServer (côté macOS). `base` = http://host:port
// résolu depuis Bonjour (cf. EndpointResolver). Réutilise les modèles partagés
// (`AuditManifest`, `SourcesFile`, `AuditDataKpis`) référencés depuis Sources/.

struct AuditAPIClient: Sendable {
    let base: URL

    /// Résumé d'un audit, tel qu'émis par `GET /api/audits`.
    struct AuditSummary: Codable, Sendable, Identifiable, Hashable {
        var id: String
        var subject: String?
        var subjectType: String?
        var status: String?
        var auditDate: String?
        var depth: String?
    }

    func audits() async throws -> [AuditSummary] {
        try await getJSON("api/audits")
    }
    func manifest(_ id: String) async throws -> AuditManifest {
        try await getJSON("api/audit/\(id)/manifest")
    }
    func sources(_ id: String) async throws -> SourcesFile {
        try await getJSON("api/audit/\(id)/sources")
    }
    func data(_ id: String) async throws -> AuditDataKpis {
        try await getJSON("api/audit/\(id)/data")
    }

    /// Liste des fichiers `.md` présents (pour les audits sans manifest).
    func files(_ id: String) async throws -> [String] {
        try await getJSON("api/audit/\(id)/files")
    }

    /// Contenu markdown d'un fichier de l'audit (`?name=00_RESUME.md`).
    func file(_ id: String, name: String) async throws -> String {
        var comps = URLComponents(url: base.appendingPathComponent("api/audit/\(id)/file"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        try Self.ensureOK(resp)   // sinon un 404 renvoie un corps JSON d'erreur affiché comme markdown
        return String(decoding: data, as: UTF8.self)
    }

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent(path))
        try Self.ensureOK(resp)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Rejette les réponses non-2xx (le serveur renvoie 404 avec un corps JSON d'erreur).
    private static func ensureOK(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
