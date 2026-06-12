import SwiftUI

struct FindBar: View {
    @Binding var query: String
    let onClose: () -> Void
    let onSubmit: (Bool) -> Void  // forward = true → next, false → previous
    @FocusState private var focused: Bool

    private static let separatorColor = Color(nsColor: .separatorColor)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in document", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onSubmit(true) }
                .frame(minWidth: 200)

            Divider().frame(height: 16)

            Button(action: { onSubmit(false) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous (⇧⌘G)")
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(action: { onSubmit(true) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next (⌘G)")
            .keyboardShortcut("g", modifiers: .command)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Self.separatorColor, lineWidth: 0.5)
        )
        .padding(12)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .onAppear { focused = true }
        .onChange(of: query) { _, new in
            if !new.isEmpty { onSubmit(true) }
        }
    }
}
