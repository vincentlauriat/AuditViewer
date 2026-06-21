import SwiftUI

@main
struct AuditViewerApp: App {
    @State private var store = AuditStore()
    @State private var lanServer = LANServer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 740, minHeight: 480)
        }
        Settings {
            SettingsView()
                .environment(lanServer)
        }
        .commands {
            #if canImport(Sparkle)
            // App menu — mises à jour (Sparkle, build release uniquement)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: UpdaterController.shared.controller.updater)
            }
            #endif

            // File
            CommandGroup(after: .newItem) {
                Button("Ouvrir un dossier d'audit…") { store.openAuditFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Nouvel audit…") { store.showNewAudit = true }
                    .keyboardShortcut("n", modifiers: .command)
            }

            // View
            CommandGroup(after: .toolbar) {
                Button("Zoom +") { post(.zoomIn) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom −") { post(.zoomOut) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Taille réelle") { post(.zoomReset) }
                    .keyboardShortcut("0", modifiers: .command)
            }

            // Edit – find
            CommandGroup(replacing: .textEditing) {
                Button("Rechercher…") { post(.toggleFindBar) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Suivant") { post(.findNext) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Précédent") { post(.findPrevious) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
