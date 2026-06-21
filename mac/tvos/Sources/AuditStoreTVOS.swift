import Foundation

// MARK: - Store observable du viewer tvOS
//
// Orchestre la découverte Bonjour, la sélection d'un serveur, sa résolution
// host:port et le chargement de la liste d'audits. La couche UI riche (rendu
// markdown, KPIs, sources) arrive en Phase 3 ; ici on expose l'état brut.

@MainActor @Observable
final class AuditStoreTVOS {
    private(set) var servers: [DiscoveredServer] = []
    private(set) var selected: DiscoveredServer?
    private(set) var audits: [AuditAPIClient.AuditSummary] = []
    private(set) var status: String = "Recherche de serveurs sur le réseau local…"
    private(set) var isLoading = false

    private var browser: BonjourBrowser?
    private var client: AuditAPIClient?

    func startDiscovery() {
        guard browser == nil else { return }
        let b = BonjourBrowser { [weak self] found in
            Task { @MainActor in self?.applyServers(found) }
        }
        browser = b
        b.start()
    }

    private func applyServers(_ found: [DiscoveredServer]) {
        servers = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selected == nil {
            status = found.isEmpty
                ? "Aucun serveur trouvé. Activez « Partager sur le réseau local » sur le Mac."
                : "\(found.count) serveur(s) disponible(s)."
        }
    }

    func select(_ server: DiscoveredServer) async {
        selected = server
        audits = []
        isLoading = true
        status = "Connexion à \(server.name)…"
        defer { isLoading = false }

        guard let base = await EndpointResolver.resolve(server.endpoint) else {
            status = "Impossible de résoudre \(server.name)."
            return
        }
        let c = AuditAPIClient(base: base)
        client = c
        do {
            audits = try await c.audits()
            status = audits.isEmpty
                ? "Aucun audit partagé sur \(server.name)."
                : "\(audits.count) audit(s) sur \(server.name)."
        } catch {
            status = "Erreur de chargement : \(error.localizedDescription)"
        }
    }
}
