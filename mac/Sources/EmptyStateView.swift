import SwiftUI

struct EmptyStateView: View {
    @Environment(AuditStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Aucun rapport d'audit")
                    .font(.title2.weight(.medium))
                Text("Ouvrez un dossier d'audit existant ou lancez une nouvelle analyse.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 12) {
                Button {
                    store.openAuditFolder()
                } label: {
                    Label("Ouvrir un dossier…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    store.showNewAudit = true
                } label: {
                    Label("Nouvel audit…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
