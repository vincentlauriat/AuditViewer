import SwiftUI

/// Entrée « virtuelle » de la barre latérale (id négatif). Construite en tant que
/// donnée pour être listée via `ForEach` : la sélection d'une `List` n'écrit le
/// binding que pour les lignes issues d'un `ForEach`, pas pour des vues statiques
/// conditionnelles (sinon le clic ne navigue pas — cf. l'entrée « Sources »).
private struct VirtualEntry: Identifiable {
    let id: Int
    let title: String
    let icon: String
    let color: Color
    var badge: Int? = nil
}

struct SidebarView: View {
    @Environment(AuditStore.self) private var store

    private var virtualEntries: [VirtualEntry] {
        var items: [VirtualEntry] = []
        if store.hasChanges {
            items.append(VirtualEntry(id: -1, title: "Modifications",
                                      icon: "arrow.triangle.2.circlepath", color: .orange,
                                      badge: store.changedSectionsCount))
        }
        if store.meta != nil {
            items.append(VirtualEntry(id: -2, title: "Reconnaissance",
                                      icon: "doc.text.below.ecg", color: .accentColor))
        }
        if store.factcheckExists {
            items.append(VirtualEntry(id: -3, title: "Vérification des faits",
                                      icon: "checkmark.shield", color: .green))
        }
        if store.dataExists {
            items.append(VirtualEntry(id: -4, title: "Chiffres-clés",
                                      icon: "tablecells", color: .teal))
        }
        if store.sourceCount > 0 {
            items.append(VirtualEntry(id: -5, title: "Sources",
                                      icon: "link", color: .cyan, badge: store.sourceCount))
        }
        return items
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedSectionId) {

            // ── Entrées virtuelles ──────────────────────────────────────
            if !virtualEntries.isEmpty {
                Section {
                    ForEach(virtualEntries) { entry in
                        Label {
                            Text(entry.title)
                        } icon: {
                            Image(systemName: entry.icon)
                                .font(.caption)
                                .foregroundStyle(entry.color)
                        }
                        .tag(entry.id)
                        .badge(entry.badge ?? 0)
                    }
                } header: {
                    Text("Synthèse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            // ── Sections de l'audit ─────────────────────────────────────
            Section {
                ForEach(store.sections.filter { $0.exists || !$0.isOptional }) { section in
                    Label {
                        HStack(spacing: 4) {
                            Text(section.title)
                                .foregroundStyle(section.exists ? .primary : .tertiary)
                            Spacer()
                            if let diff = section.diffResult, diff.hasDiff {
                                Text(diff.badge)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.12), in: Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: section.exists ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(section.exists ? Color.accentColor : Color.secondary.opacity(0.4))
                            .font(.caption)
                    }
                    .tag(section.id)
                    .help(section.filename)
                }
            } header: {
                if !store.subject.isEmpty {
                    Text(store.subject)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(2)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: store.selectedSectionId) { _, id in
            store.loadSection(id)
            // Sélectionner une section ramène au document (on quitte la carte)
            if store.viewMode == .graph { store.viewMode = .document }
        }
    }
}
