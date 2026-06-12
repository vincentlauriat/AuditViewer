import AppKit
import os
import SwiftUI
import WebKit

private let log = Logger(subsystem: "com.vincent.AuditViewer", category: "GraphWebView")

/// Carte canvas façon Obsidian : graphe force-directed rendu dans un WKWebView.
struct GraphWebView: NSViewRepresentable {
    let json: String
    let scope: AuditStore.GraphScope
    let store: AuditStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "graph")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.webView = webView
        context.coordinator.pendingJSON = json
        context.coordinator.observeAppearance()
        context.coordinator.observeFocusRequests()
        loadBundle(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.store = store
        context.coordinator.render(json: json)
    }

    private func loadBundle(into webView: WKWebView) {
        guard let resources = Bundle.main.resourceURL else {
            log.error("Bundle.main.resourceURL is nil")
            return
        }
        let webRoot = resources.appendingPathComponent("webgraph", isDirectory: true)
        let indexURL = webRoot.appendingPathComponent("graph.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            log.error("graph.html not found at \(indexURL.path, privacy: .public)")
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
    }
}

// MARK: - Coordinator

extension GraphWebView {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var store: AuditStore
        var pendingJSON: String = ""
        private var lastRendered: String = ""
        private var bundleReady = false
        private var appearanceObservation: NSKeyValueObservation?
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        init(store: AuditStore) { self.store = store }

        func observeAppearance() {
            appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.applyTheme() }
            }
        }

        /// Observe les demandes de mise en évidence d'un nœud (depuis le panneau
        /// d'infos) et le réglage de thème, et les applique à la carte.
        func observeFocusRequests() {
            observers.append(NotificationCenter.default.addObserver(
                forName: .graphFocusNode, object: nil, queue: .main
            ) { [weak self] note in
                guard let id = note.userInfo?["id"] as? String else { return }
                MainActor.assumeIsolated { [weak self] in self?.focusNode(id) }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .themeChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in self?.applyTheme() }
            })
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        private func applyTheme() {
            guard bundleReady, let webView else { return }
            let isDark = ThemeMode.current.isDark
            webView.evaluateJavaScript("window.setTheme && window.setTheme('\(isDark ? "dark" : "light")')")
        }

        func render(json: String) {
            pendingJSON = json
            guard bundleReady, let webView, json != lastRendered else { return }
            lastRendered = json
            // Le JSON est déjà un littéral d'objet JS valide.
            webView.evaluateJavaScript("window.renderGraph(\(json))")
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            bundleReady = true
            applyTheme()
            lastRendered = pendingJSON
            webView.evaluateJavaScript("window.renderGraph(\(pendingJSON))")
        }

        // Messages JS → Swift (geste sur un nœud : clic simple ou double-clic)
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "graph",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            let gesture = body["gesture"] as? String ?? "single"
            let label = body["label"] as? String
            let nodeId = body["id"] as? String
            let sectionId = body["sectionId"] as? Int
            let auditPath = body["auditPath"] as? String
            store.handleGraphNodeTap(
                gesture: gesture, type: type, label: label,
                nodeId: nodeId, sectionId: sectionId, auditPath: auditPath
            )
        }

        /// Met en évidence un nœud sur la carte (appelé depuis le panneau d'infos).
        func focusNode(_ id: String) {
            guard bundleReady, let webView else { return }
            let payload = encodeForJS(id)
            webView.evaluateJavaScript("window.focusNode && window.focusNode(\(payload))")
        }

        private func encodeForJS(_ str: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: str, options: [.fragmentsAllowed]),
                  let result = String(data: data, encoding: .utf8) else { return "\"\"" }
            return result
        }

        // Liens externes éventuels → navigateur
        func webView(
            _: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
