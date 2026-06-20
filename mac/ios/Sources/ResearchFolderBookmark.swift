import Foundation

// MARK: - ResearchFolderBookmark
//
// Persiste l'accès au dossier `Research` choisi par l'utilisateur via le
// sélecteur Fichiers (`.fileImporter`). Sur iOS, l'URL fournie par le sélecteur
// est *security-scoped* : il faut créer un bookmark, le stocker, puis le résoudre
// et appeler `startAccessingSecurityScopedResource()` à chaque session.
//
// La portée d'accès reste active pour toute la durée de vie du process (les vues
// détail lisent les fichiers paresseusement, bien après le scan initial), d'où le
// suivi d'une seule URL active à la fois.

@MainActor
enum ResearchFolderBookmark {

    private static let key = "researchFolderBookmark"

    /// URL actuellement « access-started » + indicateur de balance stop/start.
    private static var active: (url: URL, started: Bool)?

    /// Un bookmark a-t-il déjà été enregistré ?
    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    // MARK: - Enregistrement (depuis le sélecteur)

    /// Crée et stocke un bookmark pour `url` (issue de `.fileImporter`), puis active l'accès.
    @discardableResult
    static func save(_ url: URL) -> Bool {
        let started = url.startAccessingSecurityScopedResource()
        guard let data = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            if started { url.stopAccessingSecurityScopedResource() }
            return false
        }
        UserDefaults.standard.set(data, forKey: key)
        setActive(url: url, started: started)
        return true
    }

    // MARK: - Résolution (au lancement / refresh)

    /// Résout le bookmark stocké et démarre l'accès security-scoped. Retourne nil si absent/illisible.
    @discardableResult
    static func resolveAndActivate() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        let started = url.startAccessingSecurityScopedResource()
        setActive(url: url, started: started)

        // Bookmark périmé (dossier déplacé/renommé) : on le régénère silencieusement.
        if stale,
           let fresh = try? url.bookmarkData(options: .minimalBookmark,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }

        return url
    }

    /// Oublie le dossier choisi et libère l'accès.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        setActive(url: nil, started: false)
    }

    // MARK: - Gestion de la portée active

    private static func setActive(url: URL?, started: Bool) {
        if let prev = active, prev.started {
            prev.url.stopAccessingSecurityScopedResource()
        }
        active = url.map { ($0, started) }
    }
}
