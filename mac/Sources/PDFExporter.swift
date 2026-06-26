import AppKit
import WebKit

/// Exporte un document HTML en PDF via WKWebView.pdf() (macOS 12+).
///
/// WKWebView.pdf() est pleinement async, ne bloque pas le main thread, et pagine
/// le contenu correctement en fonction de la hauteur du frame (794 × 1123 px ≈ A4 à 96 dpi).
/// NSPrintOperation.run() a été écarté car il bloque le main thread et ne peut pas
/// être appelé de façon non-bloquante depuis Swift concurrency sur macOS.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        // 794 × 1123 px ≈ A4 à 96 dpi (210 × 297 mm).
        // La largeur détermine la mise en page ; la hauteur est la hauteur de chaque page PDF.
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        super.init()
        webView.navigationDelegate = self
    }

    static func export(html: String, to destination: URL) async throws {
        let exporter = PDFExporter()

        // Charger le HTML et attendre que WebKit signale didFinish.
        await withCheckedContinuation { continuation in
            exporter.loadContinuation = continuation
            exporter.webView.loadHTMLString(html, baseURL: nil)
        }

        // Laisser WebKit finaliser le layout CSS avant l'export.
        try? await Task.sleep(for: .milliseconds(500))

        // Générer le PDF de manière asynchrone — ne bloque pas le main thread.
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
