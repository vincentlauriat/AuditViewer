import Foundation
import Network
import Observation

// MARK: - Serveur LAN read-only (Phase 1 du viewer tvOS)
//
// Publie le dossier `researchRoot` sur le réseau local en **lecture seule** via un
// petit serveur HTTP/1.1 (GET uniquement) + Bonjour `_auditviewer._tcp`. L'Apple TV
// (target tvOS, à venir) le découvre en Bonjour et lit les audits par réseau — tvOS
// n'ayant ni Files picker ni accès iCloud Drive (cf. PLAN_TVOS.md).
//
// Contrat REST (aligné sur le backend Express V1) :
//   GET /api/audits                      → [{id, subject, status, …}]
//   GET /api/audit/{id}/manifest|data|sources → JSON brut de l'audit
//   GET /api/audit/{id}/file?name=X.md   → un .md de l'audit
//
// Anti path-traversal : whitelist par énumération réelle. Un `{id}` n'est servi que
// s'il correspond exactement au nom d'un dossier `audit-*/` réellement présent ; un
// `name` n'est servi que s'il figure dans le listing réel du dossier.

// MARK: - État observable exposé à l'UI

struct LANServerState: Sendable {
    var isRunning: Bool = false
    var port: UInt16? = nil
    var requestsServed: Int = 0
    var lastError: String? = nil
}

// MARK: - Réponse HTTP minimale

struct HTTPResponse: Sendable {
    var status: Int
    var statusText: String
    var contentType: String
    var body: Data

    static func json(_ data: Data) -> HTTPResponse {
        .init(status: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: data)
    }
    static func markdown(_ data: Data) -> HTTPResponse {
        .init(status: 200, statusText: "OK", contentType: "text/markdown; charset=utf-8", body: data)
    }
    static func error(_ status: Int, _ text: String) -> HTTPResponse {
        .init(status: status, statusText: text, contentType: "application/json; charset=utf-8",
              body: Data("{\"error\":\"\(text.lowercased().replacingOccurrences(of: " ", with: "_"))\"}".utf8))
    }
    static func notFound() -> HTTPResponse { .error(404, "Not Found") }

    /// Sérialise la réponse complète (en-têtes + corps) prête à émettre sur la socket.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"   // confort de test au navigateur (read-only LAN)
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

// MARK: - Logique métier read-only (sans état réseau, testable isolément)

struct AuditHTTPService: Sendable {
    let root: URL

    /// Résumé d'un audit pour la liste `/api/audits`.
    private struct AuditSummary: Codable, Sendable {
        var id: String
        var subject: String?
        var subjectType: String?
        var status: String?
        var auditDate: String?
        var depth: String?
    }

    /// Dossiers d'audit autorisés, indexés par nom (`audit-notion` → URL). Whitelist.
    private func allowedDirs() -> [String: URL] {
        var map: [String: URL] = [:]
        for url in GraphBuilder.auditDirs(in: root) { map[url.lastPathComponent] = url }
        return map
    }

    func response(method: String, path rawPath: String) -> HTTPResponse {
        guard method == "GET" else { return .error(405, "Method Not Allowed") }

        let split = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(split[0])
        let query = split.count > 1 ? String(split[1]) : ""
        let comps = path.split(separator: "/").map(String.init)

        if comps == ["api", "audits"] { return audits() }

        if comps.count == 4, comps[0] == "api", comps[1] == "audit" {
            let id = comps[2].removingPercentEncoding ?? comps[2]
            let kind = comps[3]
            guard let dir = allowedDirs()[id] else { return .notFound() }
            switch kind {
            case "manifest": return jsonFile(dir.appendingPathComponent("_manifest.json"))
            case "data":     return jsonFile(dir.appendingPathComponent("_data.json"))
            case "sources":  return jsonFile(dir.appendingPathComponent("_sources.json"))
            case "files":    return filesList(in: dir)
            case "file":     return markdownFile(in: dir, query: query)
            default:         return .notFound()
            }
        }
        return .notFound()
    }

    // MARK: Routes

    private func audits() -> HTTPResponse {
        let summaries: [AuditSummary] = allowedDirs()
            .sorted { $0.key < $1.key }
            .map { id, dir in
                let manifest = (try? Data(contentsOf: dir.appendingPathComponent("_manifest.json")))
                    .flatMap { try? JSONDecoder().decode(AuditManifest.self, from: $0) }
                return AuditSummary(
                    id: id,
                    subject: manifest?.subject,
                    subjectType: manifest?.subjectType,
                    status: manifest?.status,
                    auditDate: manifest?.auditDate,
                    depth: manifest?.depth
                )
            }
        guard let data = try? JSONEncoder().encode(summaries) else { return .error(500, "Encode Failed") }
        return .json(data)
    }

    private func jsonFile(_ url: URL) -> HTTPResponse {
        guard let data = try? Data(contentsOf: url) else { return .notFound() }
        return .json(data)
    }

    /// Liste les `.md` réellement présents dans l'audit (pour les audits sans
    /// `_manifest.json` : on découvre ainsi les sections et le rapport disponibles).
    private func filesList(in dir: URL) -> HTTPResponse {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let mds = entries.filter { $0.hasSuffix(".md") }.sorted()
        guard let data = try? JSONEncoder().encode(mds) else { return .error(500, "Encode Failed") }
        return .json(data)
    }

    /// Sert un `.md` du dossier. Le nom est validé par appartenance au listing réel
    /// du dossier (pas de concaténation de chemin à partir de l'entrée client).
    private func markdownFile(in dir: URL, query: String) -> HTTPResponse {
        guard let name = Self.queryValue("name", in: query)?
                .removingPercentEncoding else { return .error(400, "Bad Request") }

        guard name.hasSuffix(".md"), !name.contains("/"), !name.contains("..") else {
            return .notFound()
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        guard entries.contains(name) else { return .notFound() }

        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return .notFound() }
        return .markdown(data)
    }

    /// Extrait la valeur d'un paramètre d'une query string `a=1&b=2`.
    private static func queryValue(_ key: String, in query: String) -> String? {
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.first.map(String.init) == key {
                return kv.count > 1 ? String(kv[1]) : ""
            }
        }
        return nil
    }
}

// MARK: - Moteur réseau (NWListener + Bonjour)
//
// `@unchecked Sendable` : tout l'état mutable est confiné à `queue`. Les handlers de
// NWListener/NWConnection sont exécutés sur cette même queue (via `start(queue:)`),
// donc les mutations directes y sont sûres.

final class LANServerEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vincent.AuditViewer.LANServer")
    private let service: AuditHTTPService
    private let onState: @Sendable (LANServerState) -> Void

    private var listener: NWListener?
    private var state = LANServerState()

    init(root: URL, onState: @escaping @Sendable (LANServerState) -> Void) {
        self.service = AuditHTTPService(root: root)
        self.onState = onState
    }

    func start() { queue.async { self.startLocked() } }
    func stop()  { queue.async { self.stopLocked() } }

    // MARK: Listener

    private func startLocked() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.service = NWListener.Service(name: nil, type: "_auditviewer._tcp")
            l.stateUpdateHandler = { [weak self] st in self?.handleListenerState(st) }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.start(queue: queue)
            listener = l
        } catch {
            state.lastError = error.localizedDescription
            state.isRunning = false
            onState(state)
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        state.isRunning = false
        state.port = nil
        onState(state)
    }

    private func handleListenerState(_ st: NWListener.State) {
        switch st {
        case .ready:
            state.isRunning = true
            state.port = listener?.port?.rawValue
            state.lastError = nil
            onState(state)
        case .failed(let error):
            state.lastError = error.localizedDescription
            stopLocked()
        case .cancelled:
            state.isRunning = false
            onState(state)
        default:
            break
        }
    }

    // MARK: Connexions

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    /// Lit jusqu'à la fin des en-têtes (`\r\n\r\n`). GET sans corps → suffisant.
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let header = buf.subdata(in: buf.startIndex..<range.lowerBound)
                self.handleRequest(conn, header: header)
                return
            }
            if isComplete || error != nil || buf.count > 64 * 1024 {
                self.send(conn, response: .error(400, "Bad Request"))
                return
            }
            self.receive(conn, buffer: buf)
        }
    }

    private func handleRequest(_ conn: NWConnection, header: Data) {
        let firstLine = String(decoding: header, as: UTF8.self)
            .split(separator: "\r\n").first.map(String.init) ?? ""
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else { send(conn, response: .error(400, "Bad Request")); return }

        let response = service.response(method: String(tokens[0]), path: String(tokens[1]))
        state.requestsServed += 1
        onState(state)
        send(conn, response: response)
    }

    private func send(_ conn: NWConnection, response: HTTPResponse) {
        conn.send(content: response.serialized(), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}

// MARK: - Façade UI observable

@MainActor @Observable
final class LANServer {
    private(set) var isRunning = false
    private(set) var port: UInt16?
    private(set) var requestsServed = 0
    private(set) var lastError: String?

    private var engine: LANServerEngine?

    /// Dossier réellement servi : `researchRoot` choisi, sinon repli `~/Documents/Research`.
    private static func serveRoot(_ root: URL?) -> URL {
        root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Research", isDirectory: true)
    }

    func toggle(root: URL?) { isRunning ? stop() : start(root: root) }

    func start(root: URL?) {
        guard engine == nil else { return }
        let e = LANServerEngine(root: Self.serveRoot(root)) { [weak self] st in
            Task { @MainActor in self?.apply(st) }
        }
        engine = e
        e.start()
    }

    func stop() {
        engine?.stop()
        engine = nil
        isRunning = false
        port = nil
    }

    private func apply(_ st: LANServerState) {
        isRunning = st.isRunning
        port = st.port
        requestsServed = st.requestsServed
        lastError = st.lastError
    }
}
