#if canImport(Sparkle)
import SwiftUI
import Sparkle

// Intégration Sparkle (mises à jour automatiques).
//
// Ce fichier n'est compilé que dans le build de *release* généré par xcodegen
// (`project.yml` déclare la dépendance Sparkle). Le build SwiftPM de développement
// (`swift build` / `build.sh`) n'embarque pas Sparkle : `canImport(Sparkle)` y est
// faux et tout ce fichier est ignoré — l'app se lance alors sans auto-update.

/// Détenteur du contrôleur Sparkle, instancié une seule fois au lancement.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    let controller: SPUStandardUpdaterController

    private init() {
        // `startingUpdater: true` démarre la vérification planifiée (intervalle défini
        // par SUScheduledCheckInterval dans Info.plist).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

/// Élément de menu « Rechercher les mises à jour… » (menu de l'application).
struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    var body: some View {
        Button("Rechercher les mises à jour…") {
            updater.checkForUpdates()
        }
    }
}
#endif
