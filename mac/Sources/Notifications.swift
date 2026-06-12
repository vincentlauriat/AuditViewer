import AppKit
import Foundation

extension Notification.Name {
    static let toggleFindBar   = Notification.Name("AuditViewer.toggleFindBar")
    static let findRequest     = Notification.Name("AuditViewer.findRequest")
    static let findNext        = Notification.Name("AuditViewer.findNext")
    static let findPrevious    = Notification.Name("AuditViewer.findPrevious")
    static let zoomIn          = Notification.Name("AuditViewer.zoomIn")
    static let zoomOut         = Notification.Name("AuditViewer.zoomOut")
    static let zoomReset       = Notification.Name("AuditViewer.zoomReset")
    static let graphFocusNode  = Notification.Name("AuditViewer.graphFocusNode")
    static let themeChanged    = Notification.Name("AuditViewer.themeChanged")
}

/// Mode de thème choisi par l'utilisateur (persisté via `@AppStorage("themeMode")`).
enum ThemeMode: String, CaseIterable, Sendable {
    case auto, light, dark

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Clair"
        case .dark:  return "Sombre"
        }
    }

    /// Résout le thème effectif (sombre ?) en tenant compte de l'apparence système.
    @MainActor
    var isDark: Bool {
        switch self {
        case .light: return false
        case .dark:  return true
        case .auto:  return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    /// Lit le mode courant depuis les réglages (clé partagée `@AppStorage`).
    @MainActor
    static var current: ThemeMode {
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: "themeMode") ?? "auto") ?? .auto
    }
}
