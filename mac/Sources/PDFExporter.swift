import AppKit
import WebKit

/// Exporte du HTML en PDF A4 vectoriel paginé.
///
/// ## Pourquoi pas WKWebView.pdf()
/// Contrairement à ce qu'on pourrait croire, `.pdf()` ne pagine PAS en fonction de la hauteur
/// du frame : il capture tout le contenu en une seule page géante, puis rasterise les couches
/// CSS (gradients, clip-path) à la résolution Retina 2x → fichiers de plusieurs GB pour les
/// longs rapports. Les directives @page et page-break-* sont ignorées.
///
/// ## Solution : WKWebView.printOperation(with:) + fenêtre hors-écran + runModal
/// - printOperation(with:) utilise le moteur d'impression WebKit : vectoriel, pagine
///   correctement, honore @page/page-break/clip-path/gradients.
/// - La WKWebView DOIT être attachée à une NSWindow réelle (même invisible) pour que le
///   WebContent process out-of-process produise un layout imprimable. Sans fenêtre,
///   op.run() attend indéfiniment → freeze.
/// - runModal(for:delegate:didRun:contextInfo:) est ASYNCHRONE : retourne immédiatement,
///   le callback est invoqué par AppKit via le run loop quand le PDF est écrit.
///   Contrairement à op.run() (synchrone, bloque le main thread), runModal ne gèle pas l'UI.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private let window: NSWindow
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var printDelegate: PrintDelegate?   // référence forte jusqu'au callback AppKit

    private override init() {
        let frame = CGRect(x: 0, y: 0, width: 794, height: 1123) // A4 @96 dpi
        webView = WKWebView(frame: frame)

        // Fenêtre réelle mais invisible hors de tous les écrans.
        // orderBack(nil) est indispensable : sans être dans l'order-list,
        // le WebContent process ne produit pas de layout imprimable.
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0                               // transparente = invisible
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000)) // hors de tout écran
        super.init()
        window.contentView = webView
        window.orderBack(nil)                               // force le rendu WebKit
        webView.navigationDelegate = self
    }

    static func export(html: String, to destination: URL) async throws {
        let exporter = PDFExporter()

        // Étape 1 : charger le HTML et attendre didFinish
        await withCheckedContinuation { continuation in
            exporter.loadContinuation = continuation
            exporter.webView.loadHTMLString(html, baseURL: nil)
        }

        // Étape 2 : laisser WebKit finaliser le layout CSS et les polices
        try? await Task.sleep(for: .milliseconds(400))

        // Étape 3 : impression PDF asynchrone via runModal
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let info = NSPrintInfo()
            info.paperSize = NSSize(width: 595.28, height: 841.89) // A4 en points (72 dpi)
            info.topMargin = 0
            info.bottomMargin = 0
            info.leftMargin = 0
            info.rightMargin = 0
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            info.jobDisposition = .save
            info.dictionary().setValue(
                destination as NSURL,
                forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue
            )

            let op = exporter.webView.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false

            let delegate = PrintDelegate(continuation: continuation)
            exporter.printDelegate = delegate          // empêche la désallocation prématurée

            // runModal est asynchrone : retourne immédiatement, callback via run loop AppKit.
            op.runModal(
                for: exporter.window,
                delegate: delegate,
                didRun: #selector(PrintDelegate.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }

        exporter.window.orderOut(nil)
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

/// Reçoit le callback AppKit de fin d'impression.
///
/// ⚠️ NE PAS isoler au `@MainActor` : `runModal(for:delegate:didRun:contextInfo:)` exécute
/// l'opération d'impression sur un thread d'arrière-plan dédié (NSThread) et invoque ce
/// callback SUR CE THREAD, pas sur le main. Marquer la classe `@MainActor` ferait insérer
/// par Swift 6 une vérification d'isolation d'acteur (`_checkExpectedExecutor`) au début du
/// callback `@objc` → `dispatch_assert_queue` échoue → SIGTRAP.
///
/// `CheckedContinuation` est `Sendable` et peut être résumée depuis n'importe quel thread ;
/// la reprise de l'`await` se fait ensuite sur le `@MainActor` car `export()` y est isolée.
/// `@unchecked Sendable` : `continuation` n'est touchée qu'une seule fois (le callback n'est
/// appelé qu'une fois par AppKit), donc pas de course réelle.
private final class PrintDelegate: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    @objc nonisolated func printOperationDidRun(
        _ op: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let c = continuation
        continuation = nil
        if success {
            c?.resume()
        } else {
            c?.resume(throwing: CocoaError(.fileWriteUnknown))
        }
    }
}
