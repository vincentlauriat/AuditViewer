import SwiftUI
import WebKit

// MARK: - DimensionView
//
// Affiche un fichier Markdown d'une dimension d'audit.
// - Strip du frontmatter YAML (---\n...\n---) avant rendu
// - Rendu via WKWebView pour supporter les tableaux complexes
// - Chargement lazy (déclenché à l'apparition de la vue)

struct DimensionView: View {
    let dir: URL
    let filename: String
    var title: String? = nil

    @State private var markdown: String? = nil
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView(
                    "Fichier indisponible",
                    systemImage: "doc.text.slash",
                    description: Text(filename)
                )
            } else if let md = markdown {
                MarkdownWebView(markdown: md)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(title ?? dimensionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMarkdown() }
    }

    // MARK: - Helpers

    private var dimensionTitle: String {
        String(filename
            .replacingOccurrences(of: ".md", with: "")
            .drop(while: { $0.isNumber || $0 == "_" })
        ).capitalized
    }

    private func loadMarkdown() async {
        isLoading = true
        defer { isLoading = false }

        let url = dir.appendingPathComponent(filename)
        let raw: String? = await Task.detached(priority: .utility) {
            guard let data = ResearchVaultReader.readFile(at: url),
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            return AuditStoreIOS.stripYAMLFrontmatter(text)
        }.value

        if let raw {
            markdown = raw
        } else {
            failed = true
        }
    }
}

// MARK: - MarkdownWebView (WKWebView wrapper)

struct MarkdownWebView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link]
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        wv.loadHTMLString(buildHTML(from: markdown), baseURL: nil)
    }

    // MARK: - HTML minimal avec rendu Markdown via marked.js intégré

    private func buildHTML(from md: String) -> String {
        // Rendu côté CSS uniquement pour les cas simples.
        // Pour P0 : rendu naïf (titres, paragraphes, code).
        // L'intégration du bundle web/ peut remplacer ceci en P1.
        let escaped = md
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let bg = isDark ? "#1C1C1E" : "#FFFFFF"
        let fg = isDark ? "#F2F2F7" : "#1C1C1E"
        let link = isDark ? "#0A84FF" : "#007AFF"
        let codeBg = isDark ? "#2C2C2E" : "#F2F2F7"

        return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script>
        // Micro-renderer Markdown → HTML (inline, sans dépendance)
        function render(md) {
          let h = md
            // Titres
            .replace(/^#{6} (.+)$/gm, '<h6>$1</h6>')
            .replace(/^#{5} (.+)$/gm, '<h5>$1</h5>')
            .replace(/^#{4} (.+)$/gm, '<h4>$1</h4>')
            .replace(/^### (.+)$/gm, '<h3>$1</h3>')
            .replace(/^## (.+)$/gm, '<h2>$1</h2>')
            .replace(/^# (.+)$/gm, '<h1>$1</h1>')
            // Gras / italique
            .replace(/\\*\\*(.+?)\\*\\*/g, '<strong>$1</strong>')
            .replace(/\\*(.+?)\\*/g, '<em>$1</em>')
            // Code inline
            .replace(/`([^`]+)`/g, '<code>$1</code>')
            // Liens
            .replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g, '<a href="$2">$1</a>')
            // Séparateurs
            .replace(/^---$/gm, '<hr>')
            // Listes non ordonnées
            .replace(/^[*\\-] (.+)$/gm, '<li>$1</li>')
            // Tableaux simples (ligne |...|)
            .replace(/^\\|(.+)\\|$/gm, function(m, row) {
              const cells = row.split('|').map(c => c.trim());
              return '<tr>' + cells.map(c => '<td>' + c + '</td>').join('') + '</tr>';
            });
          // Entourer les blocs <li> dans <ul>
          h = h.replace(/(<li>.*<\\/li>\\n?)+/g, m => '<ul>' + m + '</ul>');
          // Entourer les blocs <tr> dans <table>
          h = h.replace(/(<tr>.*<\\/tr>\\n?)+/g, m => '<table>' + m + '</table>');
          // Paragraphes (lignes non balisées)
          h = h.split('\\n\\n').map(block => {
            if (/^<[h1-6ul|table|hr]/.test(block.trim())) return block;
            return '<p>' + block.replace(/\\n/g, ' ').trim() + '</p>';
          }).join('\\n');
          return h;
        }
        </script>
        <style>
          :root {
            color-scheme: light dark;
            --bg: \(bg);
            --fg: \(fg);
            --link: \(link);
            --code-bg: \(codeBg);
          }
          body {
            background: var(--bg);
            color: var(--fg);
            font-family: -apple-system, 'SF Pro Text', sans-serif;
            font-size: 16px;
            line-height: 1.65;
            padding: 16px 20px 60px;
            margin: 0;
          }
          h1 { font-size: 1.5em; margin: 1.2em 0 0.5em; }
          h2 { font-size: 1.25em; margin: 1.1em 0 0.4em; border-bottom: 1px solid rgba(128,128,128,0.2); padding-bottom: 0.2em; }
          h3 { font-size: 1.05em; margin: 1em 0 0.3em; }
          h4, h5, h6 { font-size: 0.95em; margin: 0.9em 0 0.3em; }
          p { margin: 0.6em 0; }
          code { background: var(--code-bg); padding: 0.15em 0.4em; border-radius: 4px; font-size: 0.88em; font-family: 'SF Mono', monospace; }
          a { color: var(--link); text-decoration: none; }
          ul { padding-left: 1.4em; margin: 0.5em 0; }
          li { margin: 0.25em 0; }
          table { border-collapse: collapse; width: 100%; margin: 0.8em 0; font-size: 0.9em; }
          td, th { border: 1px solid rgba(128,128,128,0.3); padding: 6px 10px; text-align: left; }
          tr:nth-child(even) { background: rgba(128,128,128,0.05); }
          hr { border: none; border-top: 1px solid rgba(128,128,128,0.25); margin: 1.2em 0; }
          blockquote { border-left: 3px solid rgba(128,128,128,0.4); margin: 0.8em 0; padding: 0.2em 0 0.2em 1em; color: rgba(128,128,128,0.9); }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        const raw = \(jsonEncode(md));
        document.getElementById('content').innerHTML = render(raw);
        </script>
        </body>
        </html>
        """
    }

    private func jsonEncode(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
