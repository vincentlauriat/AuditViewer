import Foundation
import Network

// MARK: - Découverte Bonjour des serveurs AuditViewer sur le réseau local
//
// Le Mac publie `_auditviewer._tcp` (cf. LANServer côté macOS). Ce browser le
// découvre sur l'Apple TV. La résolution host:port est différée à la sélection
// (cf. EndpointResolver) car URLSession a besoin d'une adresse concrète.

struct DiscoveredServer: Identifiable, Sendable, Hashable {
    let id: String            // nom du service Bonjour (unique sur le réseau)
    let name: String
    let endpoint: NWEndpoint  // conservé pour la résolution à la demande

    static func == (l: DiscoveredServer, r: DiscoveredServer) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// `@unchecked Sendable` : état confiné à `queue` (les handlers NWBrowser y tournent).
final class BonjourBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vincent.AuditViewerTVOS.Bonjour")
    private let onChange: @Sendable ([DiscoveredServer]) -> Void
    private var browser: NWBrowser?

    init(onChange: @escaping @Sendable ([DiscoveredServer]) -> Void) {
        self.onChange = onChange
    }

    func start() { queue.async { self.startLocked() } }
    func stop()  { queue.async { self.browser?.cancel(); self.browser = nil } }

    private func startLocked() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: "_auditviewer._tcp", domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let servers = results.compactMap(Self.server(from:))
            self?.onChange(servers)
        }
        b.start(queue: queue)
        browser = b
    }

    private static func server(from result: NWBrowser.Result) -> DiscoveredServer? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        return DiscoveredServer(id: name, name: name, endpoint: result.endpoint)
    }
}

// MARK: - Résolution endpoint Bonjour → URL http://host:port

/// Ouvre une `NWConnection` éphémère pour obtenir l'adresse concrète d'un service
/// Bonjour, puis l'abandonne. `@unchecked Sendable` : tout est confiné à `queue`.
final class EndpointResolver: @unchecked Sendable {
    static func resolve(_ endpoint: NWEndpoint) async -> URL? {
        await EndpointResolver().run(endpoint)
    }

    private let queue = DispatchQueue(label: "com.vincent.AuditViewerTVOS.Resolve")
    private var conn: NWConnection?
    private var cont: CheckedContinuation<URL?, Never>?
    private var done = false

    private func run(_ endpoint: NWEndpoint) async -> URL? {
        await withCheckedContinuation { c in
            queue.async {
                self.cont = c
                let conn = NWConnection(to: endpoint, using: .tcp)
                self.conn = conn
                conn.stateUpdateHandler = { [weak self] state in self?.handle(state) }
                conn.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.finish(nil) }
            }
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:               finish(Self.url(from: conn?.currentPath?.remoteEndpoint))
        case .failed, .cancelled:  finish(nil)
        default:                   break
        }
    }

    private func finish(_ url: URL?) {
        guard !done else { return }
        done = true
        conn?.cancel(); conn = nil
        cont?.resume(returning: url); cont = nil
    }

    private static func url(from endpoint: NWEndpoint?) -> URL? {
        guard case let .hostPort(host, port) = endpoint else { return nil }
        let h: String
        switch host {
        case .ipv4(let a):     h = "\(a)"
        case .ipv6(let a):     h = "[\(a)]"
        case .name(let n, _):  h = n
        @unknown default:      return nil
        }
        return URL(string: "http://\(h):\(port.rawValue)")
    }
}
