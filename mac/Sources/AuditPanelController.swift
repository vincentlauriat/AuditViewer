import AppKit
import SwiftUI

@MainActor
final class AuditPanelController {
    static let shared = AuditPanelController()

    private var panel: NSPanel?
    private var currentMode: AuditPanelMode?

    private init() {}

    func open(store: AuditStore, mode: AuditPanelMode) {
        // Réutilise la fenêtre si même mode, sinon recrée
        if let p = panel, currentMode == mode {
            p.makeKeyAndOrderFront(nil)
            return
        }
        panel?.close()

        let hc = NSHostingController(
            rootView: AuditPanelView(mode: mode).environment(store)
        )
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        p.title = mode == .new ? "Nouvel audit" : "Mettre à jour — \(store.subject)"
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 900, height: 500)
        p.contentViewController = hc
        p.center()
        p.makeKeyAndOrderFront(nil)

        currentMode = mode
        panel = p
    }
}
