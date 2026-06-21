import SwiftUI

// MARK: - Rendu Markdown natif SwiftUI (10-foot)
//
// tvOS ne permet pas de faire défiler un WKWebView à la télécommande de façon
// fiable : on rend donc le Markdown en vues SwiftUI natives dans une ScrollView
// focusable. Couvre titres, paragraphes (inline gras/italique/code/lien via
// AttributedString), listes, tableaux, citations, blocs de code et séparateurs.

/// Supprime le frontmatter YAML `---\n…\n---` en tête de fichier.
func stripYAMLFrontmatter(_ text: String) -> String {
    guard text.hasPrefix("---") else { return text }
    let lines = text.components(separatedBy: "\n")
    var i = 1
    while i < lines.count {
        if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            return lines.dropFirst(i + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
        }
        i += 1
    }
    return text
}

struct MarkdownTVOSView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                    block.view
                }
            }
            .padding(.horizontal, 90)   // marges TV-safe
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Modèle de bloc

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullets([String])
    case table(header: [String], rows: [[String]])
    case code(String)
    case quote(String)
    case rule

    @ViewBuilder var view: some View {
        switch self {
        case let .heading(level, text):
            inline(text)
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .padding(.top, level <= 2 ? 12 : 4)

        case let .paragraph(text):
            inline(text)
                .font(.body)
                .lineSpacing(6)

        case let .bullets(items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("•").font(.body).foregroundStyle(.secondary)
                        inline(item).font(.body)
                    }
                }
            }

        case let .table(header, rows):
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(.callout).fontWeight(.bold)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

        case let .code(text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

        case let .quote(text):
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 4)
                inline(text).font(.body).italic().foregroundStyle(.secondary)
            }

        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .largeTitle
        case 2:  return .title
        case 3:  return .title2
        default: return .title3
        }
    }

    /// Texte inline : gras/italique/code/lien via AttributedString Markdown.
    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }

    // MARK: - Parsing ligne par ligne

    static func parse(_ md: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = md.components(separatedBy: "\n")
        var i = 0
        var para: [String] = []

        func flushPara() {
            if !para.isEmpty {
                blocks.append(.paragraph(para.joined(separator: " ")))
                para.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Bloc de code ```…```
            if trimmed.hasPrefix("```") {
                flushPara()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }

            // Tableau (lignes |…|)
            if trimmed.hasPrefix("|") {
                flushPara()
                var tableLines: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1
                }
                if let table = parseTable(tableLines) { blocks.append(table) }
                continue
            }

            // Ligne vide → fin de paragraphe
            if trimmed.isEmpty {
                flushPara()
                i += 1
                continue
            }

            // Titre
            if let h = parseHeading(trimmed) {
                flushPara()
                blocks.append(h)
                i += 1
                continue
            }

            // Séparateur horizontal
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushPara()
                blocks.append(.rule)
                i += 1
                continue
            }

            // Citation
            if trimmed.hasPrefix("> ") {
                flushPara()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).drop(while: { $0 == ">" || $0 == " " })))
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: " ")))
                continue
            }

            // Liste à puces
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushPara()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("- ") || t.hasPrefix("* ") else { break }
                    items.append(String(t.dropFirst(2)))
                    i += 1
                }
                blocks.append(.bullets(items))
                continue
            }

            // Paragraphe
            para.append(trimmed)
            i += 1
        }
        flushPara()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for c in line { if c == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6, line.dropFirst(level).first == " " else { return nil }
        return .heading(level, String(line.dropFirst(level + 1)))
    }

    private static func parseTable(_ lines: [String]) -> MarkdownBlock? {
        func cells(_ l: String) -> [String] {
            var s = l
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard let first = lines.first else { return nil }
        let header = cells(first)
        // 2e ligne = séparateur (---) si présente
        var dataStart = 1
        if lines.count > 1, lines[1].contains("-") {
            dataStart = 2
        }
        let rows = lines.dropFirst(dataStart).map(cells)
        return .table(header: header, rows: Array(rows))
    }
}
