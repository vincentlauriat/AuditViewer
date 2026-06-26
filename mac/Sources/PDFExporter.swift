import AppKit
import WebKit

/// Exporte un document HTML vers PDF via une WKWebView hors-écran.
/// L'instance est gardée en vie localement dans `export(html:to:)` pendant toute l'opération.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        // Largeur A4 à 96 dpi (794 px) pour la mise en page ; le CSS @page gère le format final.
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        super.init()
        webView.navigationDelegate = self
    }

    static func export(html: String, to destination: URL) async throws {
        let exporter = PDFExporter()
        await withCheckedContinuation { continuation in
            exporter.loadContinuation = continuation
            exporter.webView.loadHTMLString(html, baseURL: nil)
        }
        // Délai pour que le CSS @page et les polices système soient appliqués.
        try? await Task.sleep(for: .milliseconds(450))
        let data = try await exporter.webView.pdf()
        try data.write(to: destination)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}
