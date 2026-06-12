import AppKit
import SwiftUI

// NSHostingController (pas NSHostingView) garantit que l'observation @Observable
// est correctement intégrée au cycle de mise à jour AppKit/SwiftUI.

@MainActor
final class LogsPanelController {
    static let shared = LogsPanelController()

    private var panel: NSPanel?
    private var hostingController: NSViewController?

    private init() {}

    func open(store: AuditStore) {
        // Réutilise le panneau existant (isReleasedWhenClosed = false)
        if let p = panel {
            p.makeKeyAndOrderFront(nil)
            return
        }
        let hc = NSHostingController(rootView: LogsView().environment(store))

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        p.title = "Claude Console"
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 480, height: 300)
        p.contentViewController = hc
        p.center()
        p.makeKeyAndOrderFront(nil)

        hostingController = hc
        panel = p
    }
}
