import Foundation

// MARK: - ResearchVaultReader
//
// Localise et liste les dossiers d'audit `audit-{slug}/` dans le dossier Research
// choisi par l'utilisateur (iCloud Drive natif ou « Sur mon iPhone »).
//
// Piège iCloud : les fichiers/dossiers visibles dans Fichiers ne sont pas forcément
// téléchargés localement (« dataless placeholders »). `startDownloadingUbiquitousItem`
// est ASYNCHRONE : le déclencher sans attendre fait échouer le listing/lecture qui
// suit (le contenu n'est pas encore là → « aucun audit »). On télécharge donc de
// façon BLOQUANTE (polling du statut avec timeout) avant de lister/lire, et on lit
// le répertoire via NSFileCoordinator (requis pour iCloud Drive).

struct ResearchVaultReader: Sendable {

    // MARK: - Chemin racine (repli)

    /// Repli : `Documents/Research/` du bac à sable de l'app, exposé dans Fichiers
    /// via `UIFileSharingEnabled` (« Sur mon iPhone › AuditViewer ») et iCloud.
    /// La racine principale provient du bookmark choisi par l'utilisateur
    /// (cf. `ResearchFolderBookmark`).
    static func fallbackSandboxRoot() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Research", isDirectory: true)
    }

    // MARK: - Discovery

    /// Scanne `root` et retourne les URLs des dossiers `audit-*/` présents.
    /// Force la matérialisation iCloud de la racine puis liste de façon coordonnée ;
    /// résout les placeholders `.audit-x.icloud` et déclenche le téléchargement de
    /// chaque dossier d'audit retenu.
    static func discoverAuditDirs(root: URL) -> [URL] {
        let fm = FileManager.default

        // 1. Forcer la matérialisation de la racine (bloquant, avec timeout) afin
        //    que son index de contenu soit disponible localement.
        downloadAndWait(url: root)

        // 2. Lister le contenu via coordination de fichier. On NE saute PAS les
        //    fichiers cachés : un dossier non téléchargé peut apparaître comme
        //    placeholder `.audit-x.icloud`.
        var entries: [URL] = []
        coordinatedRead(root, options: []) { coordURL in
            entries = (try? fm.contentsOfDirectory(
                at: coordURL,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isUbiquitousItemKey],
                options: []
            )) ?? []
        }

        // 3. Résoudre les placeholders, filtrer les dossiers `audit-*`, dédoublonner.
        var auditDirs: [URL] = []
        var seen = Set<String>()
        for url in entries {
            let realName = resolvedName(url.lastPathComponent)
            guard realName.hasPrefix("audit-"), seen.insert(realName).inserted else { continue }

            // URL au nom logique réel (sans le préfixe `.`/suffixe `.icloud`).
            let wasPlaceholder = url.lastPathComponent != realName
            let realURL = wasPlaceholder
                ? url.deletingLastPathComponent().appendingPathComponent(realName, isDirectory: true)
                : url

            if wasPlaceholder {
                // Dossier entièrement évincé d'iCloud : le matérialiser de façon
                // BLOQUANTE, sinon la lecture interne (`_manifest.json`…) échouera.
                downloadAndWait(url: realURL)
            } else {
                // Déjà présent : pré-chauffer (non bloquant) le téléchargement de
                // son contenu pour les vues détail.
                triggerDownload(url: realURL)
            }
            auditDirs.append(realURL)
        }

        return auditDirs.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Lecture coordonnée

    /// Lit le contenu d'un fichier via NSFileCoordinator (requis pour iCloud Drive).
    /// Télécharge le fichier de façon bloquante s'il n'est pas encore local.
    static func readFile(at url: URL) -> Data? {
        downloadAndWait(url: url)

        var result: Data?
        coordinatedRead(url, options: .withoutChanges) { coordURL in
            result = try? Data(contentsOf: coordURL)
        }
        return result
    }

    /// Exécute une lecture coordonnée NSFileCoordinator sur `url`.
    private static func coordinatedRead(
        _ url: URL,
        options: NSFileCoordinator.ReadingOptions,
        _ body: (URL) -> Void
    ) {
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &error) { coordURL in
            body(coordURL)
        }
        if let error {
            print("[ResearchVaultReader] coordination \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - iCloud download

    /// Demande le téléchargement d'un item iCloud non local **et attend** qu'il soit
    /// matérialisé (polling du statut, avec timeout). Retourne `true` si l'item est
    /// disponible localement à la sortie. Items non-ubiquitaires (stockage local) :
    /// retour immédiat `true`.
    @discardableResult
    static func downloadAndWait(url: URL, timeout: TimeInterval = 20) -> Bool {
        guard isUbiquitous(url) else { return true }   // fichier local pur
        if isDownloaded(url) { return true }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isDownloaded(url) { return true }
            usleep(150_000)   // 150 ms — appelé depuis un Task.detached de fond
        }
        return isDownloaded(url)
    }

    /// Déclenche le téléchargement (fire-and-forget) sans attendre. Utilisé pour
    /// pré-chauffer les dossiers d'audit listés.
    static func triggerDownload(url: URL) {
        guard isUbiquitous(url), !isDownloaded(url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Helpers iCloud

    private static func isUbiquitous(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem ?? false
    }

    private static func isDownloaded(_ url: URL) -> Bool {
        let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus
        return status == .current
    }

    /// `.audit-mlx.icloud` → `audit-mlx` ; sinon renvoie le nom inchangé.
    private static func resolvedName(_ name: String) -> String {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}
