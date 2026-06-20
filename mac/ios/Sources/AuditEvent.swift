import Foundation

// MARK: - AuditEvent (contrat machine v1)
//
// Un événement = une ligne JSON de `_events.jsonl`. Champs communs v1 :
//   - `v`    : version du contrat (= 1)
//   - `ts`   : horodatage ISO8601 UTC (les audits legacy utilisent `t` → repli)
//   - `type` : type d'événement (chaîne libre, mappée sur `EventType` tolérant)
//
// Robustesse : un `type` inconnu NE DOIT PAS faire échouer le décodage de la ligne.
// On décode `type` en `String` brut puis on calcule un cas `.unknown` au besoin
// (cf. `eventType`). Tous les champs de payload sont optionnels.

struct AuditEvent: Codable, Sendable {
    var v: Int?
    var ts: String?
    var rawType: String

    // Payloads (tous optionnels — présents selon le type)
    var phase: String?
    var dimension: String?
    var label: String?
    var status: String?
    var sourcesCount: Int?
    var summary: String?
    var done: Int?
    var total: Int?
    var pct: Double?
    var value: String?
    var subject: String?
    var depth: String?
    var mode: String?
    var options: [String]?
    var outputDir: String?
    var reason: String?
    var query: String?
    var url: String?
    var title: String?
    var tag: String?
    var file: String?
    var filesCount: Int?
    var id: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case v
        case ts
        case t                                  // legacy : horodatage avant v1
        case rawType = "type"
        case phase
        case dimension
        case label
        case status
        case sourcesCount = "sources_count"
        case summary
        case done
        case total
        case pct
        case value
        case subject
        case depth
        case mode
        case options
        case outputDir = "output_dir"
        case reason
        case query
        case url
        case title
        case tag
        case file
        case filesCount = "files_count"
        case id
        case message
        case step                               // legacy : équivalent dimension/phase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v)
        // `ts` (v1) avec repli sur `t` (legacy)
        ts = try c.decodeIfPresent(String.self, forKey: .ts)
            ?? c.decodeIfPresent(String.self, forKey: .t)
        rawType = (try? c.decode(String.self, forKey: .rawType)) ?? "unknown"

        phase = try c.decodeIfPresent(String.self, forKey: .phase)
        // `step` (legacy) sert à la fois de phase et de dimension selon le contexte
        let step = try c.decodeIfPresent(String.self, forKey: .step)
        dimension = try c.decodeIfPresent(String.self, forKey: .dimension) ?? step
        if phase == nil { phase = step }
        label = try c.decodeIfPresent(String.self, forKey: .label)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        sourcesCount = try c.decodeIfPresent(Int.self, forKey: .sourcesCount)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        done = try c.decodeIfPresent(Int.self, forKey: .done)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        pct = try c.decodeIfPresent(Double.self, forKey: .pct)
        value = try c.decodeIfPresent(String.self, forKey: .value)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        depth = try c.decodeIfPresent(String.self, forKey: .depth)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        options = try c.decodeIfPresent([String].self, forKey: .options)
        outputDir = try c.decodeIfPresent(String.self, forKey: .outputDir)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        query = try c.decodeIfPresent(String.self, forKey: .query)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        filesCount = try c.decodeIfPresent(Int.self, forKey: .filesCount)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(v, forKey: .v)
        try c.encodeIfPresent(ts, forKey: .ts)
        try c.encode(rawType, forKey: .rawType)
        try c.encodeIfPresent(phase, forKey: .phase)
        try c.encodeIfPresent(dimension, forKey: .dimension)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(sourcesCount, forKey: .sourcesCount)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(done, forKey: .done)
        try c.encodeIfPresent(total, forKey: .total)
        try c.encodeIfPresent(pct, forKey: .pct)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(subject, forKey: .subject)
        try c.encodeIfPresent(depth, forKey: .depth)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(options, forKey: .options)
        try c.encodeIfPresent(outputDir, forKey: .outputDir)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(query, forKey: .query)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encodeIfPresent(filesCount, forKey: .filesCount)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(message, forKey: .message)
    }

    /// Type d'événement résolu (tolérant : inconnu → `.unknown`).
    var type: EventType { EventType(rawValue: rawType) ?? .unknown }

    // Identifiant stable pour les `ForEach` SwiftUI (ts + type, ou fallback).
    var eventId: String { "\(ts ?? "?")|\(rawType)|\(file ?? dimension ?? phase ?? "")" }

    enum EventType: String, Sendable {
        // v1
        case auditStart      = "audit_start"
        case phaseStart      = "phase_start"
        case phaseDone       = "phase_done"
        case dimensionStart  = "dimension_start"
        case dimensionDone   = "dimension_done"
        case progress        = "progress"
        case search          = "search"
        case source          = "source"
        case fileWritten     = "file_written"
        case question        = "question"
        case answer          = "answer"
        case error           = "error"
        case auditComplete   = "audit_complete"
        case auditCanceled   = "audit_canceled"
        // legacy (compat ascendante)
        case stepStart       = "step_start"
        case stepDone        = "step_done"
        case auditCancelled  = "audit_cancelled"   // ancienne orthographe
        case log             = "log"
        // repli
        case unknown
    }
}

struct AuditQuestion: Codable, Sendable, Identifiable {
    struct Option: Codable, Sendable {
        var value: String
        var label: String
    }
    var id: String
    var text: String
    var options: [Option]
}

struct AuditAnswer: Codable, Sendable {
    var v: Int = 1
    var id: String
    var value: String
}
