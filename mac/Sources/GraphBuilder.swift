import Foundation

// MARK: - Modèles du graphe

struct GraphNode: Codable, Sendable {
    let id: String
    let label: String
    let type: String          // subject | section | source | entity | audit
    var sectionId: Int? = nil
    var auditPath: String? = nil
    var weight: Int = 1        // degré → rayon du nœud
}

struct GraphEdge: Codable, Sendable {
    let source: String
    let target: String
    var kind: String = "ref"   // section | source | entity
}

struct GraphData: Codable, Sendable {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []
}

// MARK: - Panneau d'infos (double-clic sur un nœud de la carte)

/// Une URL d'un domaine, éventuellement enrichie par `_sources.json` (tag/date).
struct GraphSourceItem: Identifiable, Sendable {
    let id: String          // = url
    let url: String
    let title: String?      // libellé du lien ou titre _sources.json
    let tag: String?        // "Officielle" | "Analyste" | "Presse"
    let date: String?
    let stale: Bool
}

/// Une section qui mentionne un acteur (entity).
struct GraphSectionRef: Identifiable, Sendable {
    let id: Int             // = sectionId
    let title: String
}

/// Contenu du panneau flottant affiché sur la carte.
enum GraphInfo: Identifiable, Sendable {
    case source(domain: String, nodeId: String, items: [GraphSourceItem])
    case entity(name: String, nodeId: String, sections: [GraphSectionRef])

    var id: String {
        switch self {
        case let .source(_, nodeId, _): return "src-\(nodeId)"
        case let .entity(_, nodeId, _): return "ent-\(nodeId)"
        }
    }
}

// MARK: - Construction des graphes

enum GraphBuilder {

    struct SourceRef: Sendable {
        let url: String
        let domain: String
        let label: String
        let file: String       // nom du fichier .md citant la source
    }

    // Regex : [label](http(s)://…)
    private static let linkRegex = try? NSRegularExpression(
        pattern: #"\[([^\]]*)\]\((https?://[^)\s]+)\)"#
    )

    static func domain(of url: String) -> String {
        guard let host = URLComponents(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func extractSources(from text: String, file: String) -> [SourceRef] {
        guard let regex = linkRegex else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        var refs: [SourceRef] = []
        regex.enumerateMatches(in: text, range: ns) { match, _, _ in
            guard let m = match,
                  let lr = Range(m.range(at: 1), in: text),
                  let ur = Range(m.range(at: 2), in: text) else { return }
            let url = String(text[ur])
            refs.append(SourceRef(
                url: url,
                domain: domain(of: url),
                label: String(text[lr]),
                file: file
            ))
        }
        return refs
    }

    /// Scanne tous les .md non préfixés "_" d'un dossier et renvoie les sources citées.
    static func scanSources(in dir: URL) -> [SourceRef] {
        let fm = FileManager.default
        let mdFiles = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var refs: [SourceRef] = []
        for file in mdFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            refs.append(contentsOf: extractSources(from: text, file: file.lastPathComponent))
        }
        return refs
    }

    /// Libellé court d'un acteur clé : texte avant la première parenthèse.
    static func entityLabel(_ raw: String) -> String {
        if let idx = raw.firstIndex(of: "(") {
            return raw[..<idx].trimmingCharacters(in: .whitespaces)
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Graphe local (un audit)

    static func buildLocalGraph(
        dir: URL,
        subject: String,
        sections: [AuditSection],
        meta: AuditMeta?
    ) -> GraphData {
        var data = GraphData()

        let subjectId = "subject"
        data.nodes.append(GraphNode(
            id: subjectId,
            label: subject.isEmpty ? "Audit" : subject,
            type: "subject",
            weight: 6
        ))

        // Sections réelles présentes sur disque
        let realSections = sections.filter { $0.exists && $0.id >= 0 }

        // Pré-chargement du texte de chaque section (réutilisé pour sources + entités)
        var texts: [String: String] = [:]
        var fileToNode: [String: String] = [:]
        for s in realSections {
            let nid = "sec-\(s.id)"
            fileToNode[s.filename] = nid
            data.nodes.append(GraphNode(id: nid, label: s.title, type: "section", sectionId: s.id, weight: 3))
            data.edges.append(GraphEdge(source: subjectId, target: nid, kind: "section"))
            if let t = try? String(contentsOf: dir.appendingPathComponent(s.filename), encoding: .utf8) {
                texts[s.filename] = t
            }
        }

        // Sources : un nœud par domaine, arête section→domaine (dédupliquée)
        var domainNode: [String: String] = [:]
        var domainWeight: [String: Int] = [:]
        var pairs = Set<String>()
        for (file, text) in texts {
            guard let secNode = fileToNode[file] else { continue }
            for ref in extractSources(from: text, file: file) {
                let dn: String
                if let existing = domainNode[ref.domain] {
                    dn = existing
                } else {
                    dn = "src-\(domainNode.count)"
                    domainNode[ref.domain] = dn
                }
                domainWeight[ref.domain, default: 0] += 1
                let key = "\(secNode)|\(dn)"
                if pairs.insert(key).inserted {
                    data.edges.append(GraphEdge(source: secNode, target: dn, kind: "source"))
                }
            }
        }
        for (domain, nid) in domainNode {
            data.nodes.append(GraphNode(id: nid, label: domain, type: "source",
                                        weight: max(1, domainWeight[domain] ?? 1)))
        }

        // Acteurs clés : nœud par key_player, arête vers les sections qui le mentionnent
        if let players = meta?.keyPlayers {
            for (i, raw) in players.enumerated() {
                let label = entityLabel(raw)
                guard !label.isEmpty else { continue }
                let nid = "ent-\(i)"
                var degree = 0
                for s in realSections {
                    guard let t = texts[s.filename], let secNode = fileToNode[s.filename] else { continue }
                    if t.localizedCaseInsensitiveContains(label) {
                        data.edges.append(GraphEdge(source: secNode, target: nid, kind: "entity"))
                        degree += 1
                    }
                }
                if degree == 0 {
                    // Rattaché au sujet pour rester visible
                    data.edges.append(GraphEdge(source: subjectId, target: nid, kind: "entity"))
                }
                data.nodes.append(GraphNode(id: nid, label: label, type: "entity", weight: max(2, degree)))
            }
        }

        return data
    }

    // MARK: Graphe global (tous les audits)

    private static func subjectTitle(from dir: URL) -> String {
        var slug = dir.lastPathComponent
        for prefix in ["audit-", "audit_"] where slug.hasPrefix(prefix) {
            slug = String(slug.dropFirst(prefix.count)); break
        }
        return slug.replacingOccurrences(of: "-", with: " ")
                   .replacingOccurrences(of: "_", with: " ")
                   .capitalized
    }

    /// Graphe reliant les audits entre eux par sources et acteurs partagés (degré ≥ 2).
    static func buildGlobalGraph(root: URL) -> GraphData {
        let fm = FileManager.default
        let auditDirs = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: $0.path, isDirectory: &isDir)
                let name = $0.lastPathComponent
                return exists && isDir.boolValue && (name.hasPrefix("audit-") || name.hasPrefix("audit_"))
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var data = GraphData()
        guard !auditDirs.isEmpty else { return data }

        // auditId -> ensemble de domaines et d'entités
        var auditId: [URL: String] = [:]
        var domainToAudits: [String: Set<String>] = [:]
        var entityToAudits: [String: Set<String>] = [:]

        for (i, dir) in auditDirs.enumerated() {
            let aid = "audit-\(i)"
            auditId[dir] = aid
            data.nodes.append(GraphNode(
                id: aid,
                label: subjectTitle(from: dir),
                type: "audit",
                auditPath: dir.path,
                weight: 4
            ))

            // Domaines cités
            for ref in scanSources(in: dir) {
                domainToAudits[ref.domain, default: []].insert(aid)
            }
            // Acteurs clés (depuis _recon.json)
            if let metaData = try? Data(contentsOf: dir.appendingPathComponent("_recon.json")),
               let meta = try? JSONDecoder().decode(AuditMeta.self, from: metaData),
               let players = meta.keyPlayers {
                for raw in players {
                    let label = entityLabel(raw)
                    if !label.isEmpty { entityToAudits[label, default: []].insert(aid) }
                }
            }
        }

        // Ne garder que les nœuds partagés par ≥ 2 audits (= vrais liens inter-audits)
        var srcIdx = 0
        for (domain, audits) in domainToAudits where audits.count >= 2 {
            let nid = "gsrc-\(srcIdx)"; srcIdx += 1
            data.nodes.append(GraphNode(id: nid, label: domain, type: "source", weight: audits.count))
            for aid in audits { data.edges.append(GraphEdge(source: aid, target: nid, kind: "source")) }
        }
        var entIdx = 0
        for (label, audits) in entityToAudits where audits.count >= 2 {
            let nid = "gent-\(entIdx)"; entIdx += 1
            data.nodes.append(GraphNode(id: nid, label: label, type: "entity", weight: audits.count + 1))
            for aid in audits { data.edges.append(GraphEdge(source: aid, target: nid, kind: "entity")) }
        }

        return data
    }
}
