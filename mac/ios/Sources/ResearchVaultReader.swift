import Foundation

// MARK: - ResearchVaultReader
//
// Localise et liste les dossiers d'audit `audit-{slug}/` dans
// `~/Documents/Research/` (iCloud Drive natif).
// Utilise NSFileCoordinator pour déclencher le téléchargement des
// fichiers iCloud non encore disponibles localement.

struct ResearchVaultReader: Sendable {

    // MARK: - Chemin racine

    /// Retourne l'URL de `~/Documents/Research/` ou nil si introuvable.
    static func researchRootURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Research", isDirectory: true)
    }

    // MARK: - Discovery

    /// Scanne `root` et retourne les URLs des dossiers `audit-*/` présents.
    /// Déclenche le téléchargement iCloud si les entrées sont des placeholders.
    static func discoverAuditDirs(root: URL) -> [URL] {
        let fm = FileManager.default

        // S'assurer que le dossier Research est local (télécharger si besoin)
        triggerDownloadIfNeeded(url: root)

        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { url in
                guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      vals.isDirectory == true else { return false }
                return url.lastPathComponent.hasPrefix("audit-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Lecture coordonnée

    /// Lit le contenu d'un fichier via NSFileCoordinator (requis pour iCloud Drive).
    /// Déclenche le téléchargement si le fichier est un placeholder.
    static func readFile(at url: URL) -> Data? {
        triggerDownloadIfNeeded(url: url)

        var result: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { coordURL in
            result = try? Data(contentsOf: coordURL)
        }

        if let error { print("[ResearchVaultReader] Erreur lecture \(url.lastPathComponent): \(error)") }
        return result
    }

    // MARK: - iCloud download

    /// Demande le téléchargement d'un fichier iCloud non local (silencieux si déjà local).
    static func triggerDownloadIfNeeded(url: URL) {
        let fm = FileManager.default
        guard let vals = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              vals.ubiquitousItemDownloadingStatus != .current
        else { return }

        try? fm.startDownloadingUbiquitousItem(at: url)
    }
}
