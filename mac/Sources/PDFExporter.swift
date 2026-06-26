import AppKit
import WebKit

/// Exporte un document HTML en PDF A4 paginé via NSPrintOperation.
///
/// Pourquoi NSPrintOperation :
///   - WKWebView.pdf() ne pagine pas — il crée un PDF dont la hauteur de page = hauteur du
///     viewport, ce qui produit des "pages géantes" sur les longs documents.
///   - NSPrintOperation utilise le moteur d'impression macOS qui respecte page-break-* CSS.
///
/// Pourquoi run(withCompletion:) et non run() :
///   - run() est synchrone et pompe sa propre run loop via [NSApp nextEventMatchingMask:].
///     Appelé depuis une task Swift concurrency sur @MainActor, il deadlocke (le scheduler
///     Swift ne cède pas la run loop AppKit → NSPrintOperation attend des events qui ne viennent
///     jamais → freeze de l'application).
///   - run(withCompletion:) retourne immédiatement ; AppKit appelle le callback quand le PDF
///     est écrit, sans bloquer le main actor.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        // 794px ≈ 210mm à 96 dpi = largeur A4, détermine la largeur de mise en page.
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        super.init()
        webView.navigationDelegate = self
    }

    static func export(html: String, to destination: URL) async throws {
        let exporter = PDFExporter()

        // Étape 1 : charger le HTML et attendre didFinish
        await withCheckedContinuation { continuation in
            exporter.loadContinuation = continuation
            exporter.webView.loadHTMLString(html, baseURL: nil)
        }

        // Étape 2 : laisser WebKit finaliser le layout CSS
        try? await Task.sleep(for: .milliseconds(700))

        // Étape 3 : imprimer en PDF (non bloquant)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.runPrintOperation(to: destination, continuation: continuation)
        }
    }

    private func runPrintOperation(
        to destination: URL,
        continuation: CheckedContinuation<Void, Error>
    ) {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89) // A4 @ 72 dpi
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary().setValue(
            destination as NSURL,
            forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue
        )

        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false

        // Dispatcher via DispatchQueue.main plutôt qu'appeler op.run() directement :
        // op.run() est synchrone et pompe la run loop via [NSApp nextEventMatchingMask:].
        // Depuis un @MainActor Swift task, le scheduler Swift ne cède pas la run loop AppKit
        // → op.run() deadlocke. Depuis un bloc DispatchQueue.main.async, la run loop est
        // disponible → op.run() peut traiter ses events internes sans bloquer.
        // Le withCheckedThrowingContinuation suspend le task Swift (libère le main actor)
        // avant que ce bloc s'exécute, donc pas de deadlock avec la queue principale.
        DispatchQueue.main.async {
            let success = op.run()
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: CocoaError(.fileWriteUnknown))
            }
        }
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
