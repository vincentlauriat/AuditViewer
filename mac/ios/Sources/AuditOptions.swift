import Foundation

struct AuditOptions: Codable, Sendable {
    var depth: String   = "full"        // "quick" | "full"
    var lang: String    = "en"          // "en" | "fr"
    var mode: String    = "parallel"    // "parallel" | "sequential" | "solo"
    var focus: String   = ""            // ex: "financier" (optionnel)
    var verbose: Bool   = false
    var swot: Bool      = false
    var brief: Bool     = false
    var esg: Bool       = false
    var rh: Bool        = false
    var watch: Bool     = false

    /// Construit la ligne de flags à passer à claude
    func cliFlags(appMode: Bool = true) -> String {
        var parts: [String] = []
        parts.append("--depth \(depth)")
        parts.append("--lang \(lang)")
        parts.append("--mode \(mode)")
        if !focus.isEmpty { parts.append("--focus \"\(focus)\"") }
        if verbose  { parts.append("--verbose") }
        if swot     { parts.append("--swot") }
        if brief    { parts.append("--brief") }
        if esg      { parts.append("--esg") }
        if rh       { parts.append("--rh") }
        if watch    { parts.append("--watch") }
        if appMode  { parts.append("--app-mode") }
        return parts.joined(separator: " ")
    }
}
