import Foundation

enum DiffEngine {

    struct Result: Sendable {
        let added: Int
        let removed: Int
        let markdownBlock: String
        var hasDiff: Bool { added > 0 || removed > 0 }
        var badge: String { "+\(added) / -\(removed)" }
    }

    static func diff(old: String, new: String, context: Int = 3) -> Result {
        guard old != new else {
            return Result(added: 0, removed: 0, markdownBlock: "_Aucune modification._")
        }
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        if max(oldLines.count, newLines.count) > 800 {
            return largeFileDiff(old: oldLines, new: newLines)
        }
        return buildResult(ops: lcsOps(oldLines, newLines), context: context)
    }

    // MARK: - LCS

    private enum Op: Sendable {
        case equal(String), insert(String), delete(String)
    }

    private static func lcsOps(_ a: [String], _ b: [String]) -> [Op] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1] + 1
                    : max(dp[i-1][j], dp[i][j-1])
            }
        }
        var ops: [Op] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i-1] == b[j-1] {
                ops.append(.equal(a[i-1])); i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                ops.append(.insert(b[j-1])); j -= 1
            } else {
                ops.append(.delete(a[i-1])); i -= 1
            }
        }
        return ops.reversed()
    }

    private static func buildResult(ops: [Op], context: Int) -> Result {
        // Mark positions adjacent to changes
        var near = Array(repeating: false, count: ops.count)
        for i in ops.indices {
            if case .equal = ops[i] { continue }
            let lo = max(0, i - context)
            let hi = min(ops.count - 1, i + context)
            for j in lo...hi { near[j] = true }
        }

        var lines: [String] = []
        var added = 0, removed = 0, skipped = 0

        for (i, op) in ops.enumerated() {
            switch op {
            case .equal(let s):
                if near[i] {
                    if skipped > 0 {
                        lines.append("@@ \(skipped) ligne\(skipped > 1 ? "s" : "") inchangée\(skipped > 1 ? "s" : "") @@")
                        skipped = 0
                    }
                    lines.append("  \(s)")
                } else { skipped += 1 }
            case .insert(let s):
                if skipped > 0 {
                    lines.append("@@ \(skipped) ligne\(skipped > 1 ? "s" : "") inchangée\(skipped > 1 ? "s" : "") @@")
                    skipped = 0
                }
                lines.append("+ \(s)"); added += 1
            case .delete(let s):
                if skipped > 0 {
                    lines.append("@@ \(skipped) ligne\(skipped > 1 ? "s" : "") inchangée\(skipped > 1 ? "s" : "") @@")
                    skipped = 0
                }
                lines.append("- \(s)"); removed += 1
            }
        }
        if skipped > 0 {
            lines.append("@@ \(skipped) ligne\(skipped > 1 ? "s" : "") inchangée\(skipped > 1 ? "s" : "") @@")
        }

        let block = "```diff\n" + lines.joined(separator: "\n") + "\n```"
        return Result(added: added, removed: removed, markdownBlock: block)
    }

    private static func largeFileDiff(old: [String], new: [String]) -> Result {
        let oldSet = Set(old)
        let newSet = Set(new)
        let added   = new.filter { !oldSet.contains($0) }.count
        let removed = old.filter { !newSet.contains($0) }.count
        let note = "_(Fichier volumineux — résumé uniquement)_\n\n**+\(added) ligne\(added > 1 ? "s" : "")** ajoutée\(added > 1 ? "s" : ""), **\(removed) ligne\(removed > 1 ? "s" : "")** supprimée\(removed > 1 ? "s" : "")."
        return Result(added: added, removed: removed, markdownBlock: note)
    }
}
