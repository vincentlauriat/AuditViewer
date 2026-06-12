import AppKit
import os
import SwiftUI
import WebKit

private let log = Logger(subsystem: "com.vincent.AuditViewer", category: "WebView")

struct WebView: NSViewRepresentable {
    let markdown: String
    var zoom: Double = 1.0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = zoom

        context.coordinator.webView = webView
        context.coordinator.observeAppearance()
        context.coordinator.observeNotifications()
        loadBundle(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.documentMarkdown = markdown
        context.coordinator.flush()
        if abs(webView.pageZoom - zoom) > 0.001 {
            webView.pageZoom = zoom
        }
    }

    private func loadBundle(into webView: WKWebView) {
        guard let resources = Bundle.main.resourceURL else {
            log.error("Bundle.main.resourceURL is nil")
            return
        }
        let webRoot = resources.appendingPathComponent("web", isDirectory: true)
        let indexURL = webRoot.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            log.error("index.html not found at \(indexURL.path, privacy: .public)")
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
    }
}

// MARK: - Coordinator

extension WebView {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var documentMarkdown: String = ""
        private var bundleReady = false
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
        private var appearanceObservation: NSKeyValueObservation?
        private var lastFindQuery: String = ""

        // MARK: Appearance

        func observeAppearance() {
            applyTheme()
            appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.applyTheme() }
            }
        }

        private func applyTheme() {
            guard bundleReady, let webView else { return }
            let isDark = ThemeMode.current.isDark
            webView.evaluateJavaScript(
                "window.setTheme && window.setTheme('\(isDark ? "dark" : "light")')",
                completionHandler: nil
            )
        }

        // MARK: Notifications

        func observeNotifications() {
            // Extraire uniquement des types Sendable (String, Bool) avant de croiser l'acteur
            observers.append(NotificationCenter.default.addObserver(
                forName: .findRequest, object: nil, queue: .main
            ) { [weak self] note in
                guard let info  = note.userInfo,
                      let query = info["query"]   as? String,
                      let fwd   = info["forward"] as? Bool else { return }
                MainActor.assumeIsolated { [weak self] in self?.runFind(query: query, forward: fwd) }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .findNext, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in self?.runFind(query: nil, forward: true) }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .findPrevious, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in self?.runFind(query: nil, forward: false) }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .themeChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in self?.applyTheme() }
            })
        }

        // MARK: Render

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            bundleReady = true
            applyTheme()
            flush()
        }

        func flush() {
            guard bundleReady, let webView else { return }
            let payload = encodeForJS(documentMarkdown)
            webView.evaluateJavaScript("window.renderMarkdown(\(payload))", completionHandler: nil)
        }

        // MARK: Find

        private func runFind(query: String?, forward: Bool) {
            guard let webView, webView.window?.isKeyWindow == true else { return }
            let q = query ?? lastFindQuery
            guard !q.isEmpty else { return }
            lastFindQuery = q
            let config = WKFindConfiguration()
            config.backwards = !forward
            config.caseSensitive = false
            config.wraps = true
            webView.find(q, configuration: config) { result in
                if !result.matchFound {
                    log.debug("find: no match for \(q, privacy: .public)")
                }
            }
        }

        // MARK: External links

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

        // MARK: Helpers

        private func encodeForJS(_ str: String) -> String {
            guard
                let data = try? JSONSerialization.data(withJSONObject: str, options: [.fragmentsAllowed]),
                let result = String(data: data, encoding: .utf8)
            else { return "\"\"" }
            return result
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
