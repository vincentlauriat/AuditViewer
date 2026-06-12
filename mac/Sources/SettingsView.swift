import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var rootPath: String = KeychainStore.researchRoot?.path ?? ""
    @State private var saved: Bool = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Répertoire de recherche")
                                .font(.headline)
                            Text("Racine utilisée pour ouvrir et créer les rapports d'audit.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    HStack(spacing: 8) {
                        TextField("Chemin non défini", text: $rootPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .truncationMode(.middle)
                            .onChange(of: rootPath) { _, _ in saved = false }

                        Button("Choisir…") { pickDirectory() }
                            .controlSize(.regular)
                    }

                    HStack {
                        if rootPath.isEmpty {
                            Label("Non défini — les dossiers courants seront utilisés par défaut.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !FileManager.default.fileExists(atPath: rootPath) {
                            Label("Ce chemin n'existe pas.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Label("Chemin valide.", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        if !rootPath.isEmpty {
                            Button("Effacer") {
                                rootPath = ""
                                save()
                            }
                            .controlSize(.small)
                            .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack {
                    Spacer()
                    if saved {
                        Label("Enregistré dans le Keychain", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                    Button("Enregistrer") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(saved)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .onAppear {
            rootPath = KeychainStore.researchRoot?.path ?? ""
            saved = !rootPath.isEmpty
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choisir le répertoire racine des audits"
        panel.prompt = "Choisir"
        if !rootPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: rootPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path
        save()
    }

    private func save() {
        let trimmed = rootPath.trimmingCharacters(in: .whitespaces)
        KeychainStore.researchRoot = trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed)
        withAnimation { saved = true }
    }
}
