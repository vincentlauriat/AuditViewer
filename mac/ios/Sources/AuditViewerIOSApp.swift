import SwiftUI

// MARK: - Point d'entrée iOS

@main
struct AuditViewerIOSApp: App {
    @State private var store = AuditStoreIOS()

    var body: some Scene {
        WindowGroup {
            AuditListView()
                .environment(store)
        }
    }
}
