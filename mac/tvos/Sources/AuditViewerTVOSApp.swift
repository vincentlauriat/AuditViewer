import SwiftUI

// MARK: - Point d'entrée tvOS (Apple TV)

@main
struct AuditViewerTVOSApp: App {
    @State private var store = AuditStoreTVOS()

    var body: some Scene {
        WindowGroup {
            ContentViewTVOS()
                .environment(store)
        }
    }
}
