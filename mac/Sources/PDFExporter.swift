import AppKit
import WebKit

/// Exporte un document HTML en PDF A4 paginé via NSPrintOperation (respecte les sauts de page CSS).
/// WKWebView.pdf() ne pagine pas correctement les longs documents — il crée un PDF basé sur la
/// hauteur du viewport, ce qui produit des "pages géantes". NSPrintOperation utilise le moteur
/// d'impression macOS qui respecte page-break-after, page-break-before et @page.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        // 794px ≈ 210mm (largeur A4 à 96 dpi) — détermine la largeur de mise en page.
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
        // Laisser WebKit finaliser le layout CSS avant l'impression.
        try? await Task.sleep(for: .milliseconds(700))
        try exporter.printAsPDF(to: destination)
    }

    private func printAsPDF(to destination: URL) throws {
        let printInfo = NSPrintInfo()
        // A4 en points (72 dpi) : 595.28 × 841.89 pt
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
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

        guard op.run() else {
            throw CocoaError(.fileWriteUnknown)
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
