import Foundation

// MARK: - Sections d'un audit (iOS)
//
// Version iOS de Models.swift : contient uniquement AuditSection et auditSections[].
// LogEntry est volontairement absent — ses propriétés `icon` et `color` (String) 
// dépendent d'AppKit sur macOS. Sur iOS, les événements ne sont pas affichés (P4).

struct AuditSection: Identifiable, Sendable {
    let id: Int
    let filename: String
    let title: String
    var isOptional: Bool = false
    var exists: Bool = false
}

let auditSections: [AuditSection] = [
    AuditSection(id: 0,  filename: "00_RESUME_EXECUTIF.md", title: "Résumé exécutif"),
    AuditSection(id: 1,  filename: "01_HISTORIQUE.md",      title: "Historique"),
    AuditSection(id: 2,  filename: "02_MARCHE.md",          title: "Marché"),
    AuditSection(id: 3,  filename: "03_TECHNIQUE.md",       title: "Technique"),
    AuditSection(id: 4,  filename: "04_TARIFICATION.md",    title: "Tarification"),
    AuditSection(id: 5,  filename: "05_CONCURRENCE.md",     title: "Concurrence"),
    AuditSection(id: 6,  filename: "06_FINANCIER.md",       title: "Financier"),
    AuditSection(id: 7,  filename: "07_FUTUR.md",           title: "Futur"),
    AuditSection(id: 8,  filename: "08_ESG.md",             title: "ESG",          isOptional: true),
    AuditSection(id: 9,  filename: "09_SWOT.md",            title: "SWOT",         isOptional: true),
    AuditSection(id: 10, filename: "10_RH.md",              title: "RH / Culture", isOptional: true),
    AuditSection(id: 11, filename: "RAPPORT_COMPLET.md",    title: "Rapport complet"),
]

// Identifiant de base pour les sections découvertes dynamiquement
let dynamicSectionBaseId = 100
