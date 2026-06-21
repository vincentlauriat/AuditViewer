import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(LANServer.self) private var lanServer
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

            // ── Partage sur le réseau local (viewer Apple TV) ──────────────
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "appletv")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Partager sur le réseau local")
                                .font(.headline)
                            Text("Diffuse les audits en lecture seule pour le lecteur Apple TV (Bonjour + HTTP).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { lanServer.isRunning },
                            set: { _ in lanServer.toggle(root: KeychainStore.researchRoot) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if lanServer.isRunning {
                        Label(
                            lanServer.port.map { "Actif — port \($0) · \(lanServer.requestsServed) requête(s) servie(s)" }
                                ?? "Démarrage…",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                    } else if let err = lanServer.lastError {
                        Label("Erreur : \(err)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Inactif.", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
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
