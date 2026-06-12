import SwiftUI

struct SidebarView: View {
    @Environment(AuditStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedSectionId) {

            // ── Entrées virtuelles ──────────────────────────────────────
            if store.hasChanges || store.meta != nil || store.factcheckExists
                || store.dataExists || store.sourceCount > 0 {
                Section {
                    if store.hasChanges {
                        Label {
                            Text("Modifications")
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .tag(-1)
                        .badge(store.changedSectionsCount)
                    }

                    if store.meta != nil {
                        Label {
                            Text("Reconnaissance")
                        } icon: {
                            Image(systemName: "doc.text.below.ecg")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        .tag(-2)
                    }

                    if store.factcheckExists {
                        Label {
                            Text("Vérification des faits")
                        } icon: {
                            Image(systemName: "checkmark.shield")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .tag(-3)
                    }

                    if store.dataExists {
                        Label {
                            Text("Chiffres-clés")
                        } icon: {
                            Image(systemName: "tablecells")
                                .font(.caption)
                                .foregroundStyle(.teal)
                        }
                        .tag(-4)
                    }

                    if store.sourceCount > 0 {
                        Label {
                            Text("Sources")
                        } icon: {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                        .tag(-5)
                        .badge(store.sourceCount)
                    }
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
