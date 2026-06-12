import SwiftUI

// MARK: - Palette Obsidian (Catppuccin Mocha)

enum OBColor {
    static let base    = Color(red: 0.118, green: 0.118, blue: 0.180) // #1e1e2e
    static let surface = Color(red: 0.149, green: 0.153, blue: 0.224) // #262739
    static let overlay = Color(red: 0.192, green: 0.196, blue: 0.275) // #313244
    static let text    = Color(red: 0.804, green: 0.839, blue: 0.957) // #cdd6f4
    static let subtle  = Color(red: 0.553, green: 0.580, blue: 0.671) // #8d91ac
    static let blue    = Color(red: 0.537, green: 0.706, blue: 0.980) // #89b4fa
    static let green   = Color(red: 0.651, green: 0.890, blue: 0.631) // #a6e3a1
    static let yellow  = Color(red: 0.976, green: 0.886, blue: 0.686) // #f9e2af
    static let red     = Color(red: 0.953, green: 0.545, blue: 0.659) // #f38ba8
    static let purple  = Color(red: 0.796, green: 0.651, blue: 0.969) // #cba6f7
    static let cyan    = Color(red: 0.537, green: 0.863, blue: 0.922) // #89dceb
    static let peach   = Color(red: 0.980, green: 0.729, blue: 0.522) // #fab387
}

// MARK: - LogsView

struct LogsView: View {
    @Environment(AuditStore.self) private var store

    @State private var autoScroll = true
    @State private var highlightedId: UUID? = nil
    @State private var pulseActive = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            logList
            statusBar
        }
        .background(OBColor.base)
        .frame(minWidth: 480, minHeight: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startPulse() }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 14) {
            Spacer()

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OBColor.subtle)

            Text("\(store.logEntries.count) entrées")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OBColor.subtle)

            Button {
                withAnimation(.easeOut(duration: 0.3)) { store.logEntries.removeAll() }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(OBColor.subtle)
            }
            .buttonStyle(.borderless)
            .help("Effacer les logs")
            .disabled(store.logEntries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OBColor.surface)
    }

    // MARK: - Log list

    private var logList: some View {
        Group {
            if store.logEntries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.logEntries) { entry in
                                LogRow(
                                    entry: entry,
                                    isHighlighted: entry.id == highlightedId,
                                    isLast: entry.id == store.logEntries.last?.id,
                                    pulse: pulseActive
                                )
                                .id(entry.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding(.vertical, 6)
                        .animation(.spring(duration: 0.35, bounce: 0.1), value: store.logEntries.count)
                    }
                    .onChange(of: store.logEntries.count) { _, _ in
                        guard let last = store.logEntries.last else { return }
                        flashHighlight(last.id)
                        if autoScroll {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(OBColor.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundStyle(OBColor.overlay)
            Text("En attente d'événements…")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(OBColor.subtle)
            Text("Lance un audit pour voir les logs en temps réel")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(OBColor.overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Indicateur d'activité
            ZStack {
                if store.isRunningAudit {
                    Circle()
                        .fill(OBColor.green.opacity(pulseActive ? 0.3 : 0.0))
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(OBColor.green.opacity(pulseActive ? 0.15 : 0.0))
                        .frame(width: 22, height: 22)
                }
                Circle()
                    .fill(store.isRunningAudit ? OBColor.green : OBColor.overlay)
                    .frame(width: 8, height: 8)
            }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulseActive)

            Text(store.isRunningAudit ? "● \(store.subject)" : "○ inactif")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(store.isRunningAudit ? OBColor.green : OBColor.subtle)

            Spacer()

            if let last = store.logEntries.last {
                Text(Self.timeFormatter.string(from: last.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OBColor.overlay)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OBColor.surface)
    }

    // MARK: - Helpers

    private func flashHighlight(_ id: UUID) {
        highlightedId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.6)) { highlightedId = nil }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulseActive = true
        }
    }
}

// MARK: - LogRow

private struct LogRow: View {
    let entry: LogEntry
    let isHighlighted: Bool
    let isLast: Bool
    let pulse: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Timestamp
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(OBColor.overlay)
                .frame(width: 84, alignment: .trailing)
                .padding(.trailing, 10)

            // Séparateur vertical coloré
            RoundedRectangle(cornerRadius: 1)
                .fill(kindColor.opacity(isHighlighted ? 0.9 : 0.35))
                .frame(width: 2, height: 18)
                .padding(.trailing, 10)

            // Icône
            Image(systemName: entry.icon)
                .font(.system(size: 11))
                .foregroundStyle(kindColor)
                .frame(width: 16)
                .scaleEffect(isLast && pulse && needsPulse ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .padding(.trailing, 8)

            // Message
            Text(entry.message)
                .font(.system(size: 12, design: entry.kind == .bash ? .monospaced : .default))
                .foregroundStyle(isHighlighted ? OBColor.text : labelColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(background)
        .contentShape(Rectangle())
    }

    private var background: some View {
        Group {
            if isHighlighted {
                kindColor.opacity(0.10)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 4)
            } else {
                Color.clear
            }
        }
    }

    private var kindColor: Color {
        switch entry.kind {
        case .search: return OBColor.blue
        case .fetch:  return OBColor.cyan
        case .write:  return OBColor.green
        case .bash:   return OBColor.peach
        case .agent:  return OBColor.purple
        case .read:   return OBColor.subtle
        case .text:   return OBColor.text
        case .info:   return OBColor.subtle
        case .error:  return OBColor.red
        case .done:   return OBColor.green
        }
    }

    private var labelColor: Color {
        switch entry.kind {
        case .error: return OBColor.red
        case .done:  return OBColor.green
        case .info:  return OBColor.subtle
        default:     return OBColor.text.opacity(0.82)
        }
    }

    private var needsPulse: Bool {
        switch entry.kind {
        case .search, .fetch, .agent, .bash: return true
        default: return false
        }
    }
}
