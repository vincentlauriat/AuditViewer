import SwiftUI

// MARK: - Vue squelette (Phase 2)
//
// Valide le transport : découverte Bonjour → sélection serveur → liste d'audits.
// La présentation 10-foot complète (TabView, rendu markdown, KPIs, sources, focus
// engine soigné) est l'objet de la Phase 3.

struct ContentViewTVOS: View {
    @Environment(AuditStoreTVOS.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section("Serveurs") {
                    if store.servers.isEmpty {
                        Text("Aucun serveur détecté.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.servers) { server in
                        Button {
                            Task { await store.select(server) }
                        } label: {
                            HStack {
                                Image(systemName: "macbook")
                                Text(server.name)
                                Spacer()
                                if store.selected == server {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                if !store.audits.isEmpty {
                    Section("Audits — \(store.selected?.name ?? "")") {
                        ForEach(store.audits) { audit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(audit.subject ?? audit.id)
                                    .font(.headline)
                                HStack(spacing: 12) {
                                    if let type = audit.subjectType { Text(type) }
                                    if let status = audit.status { Text(status) }
                                    if let date = audit.auditDate { Text(date) }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Audit Viewer")
            .overlay(alignment: .bottom) {
                if store.isLoading {
                    ProgressView().padding()
                } else {
                    Text(store.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .onAppear { store.startDiscovery() }
    }
}
