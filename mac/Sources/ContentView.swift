import SwiftUI

struct ContentView: View {
    @Environment(AuditStore.self) private var store

    @SceneStorage("zoomRatio") private var zoomRatio: Double = 1.0
    @AppStorage("themeMode") private var themeMode: String = ThemeMode.auto.rawValue
    @State private var showFind: Bool = false
    @State private var findQuery: String = ""

    /// Schéma natif imposé selon le mode de thème (nil = suit le système).
    private var preferredScheme: ColorScheme? {
        switch ThemeMode(rawValue: themeMode) ?? .auto {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }

    private static let zoomStep: Double = 0.1
    private static let zoomMin:  Double = 0.5
    private static let zoomMax:  Double = 3.0

    var body: some View {
        Group {
            if store.auditDir == nil {
                if store.browseMode {
                    AuditListView()
                } else {
                    EmptyStateView()
                }
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
                } detail: {
                    detailPane
                }
            }
        }
        // Nouvel audit → panel 3 colonnes
        .onChange(of: store.showNewAudit) { _, show in
            if show {
                AuditPanelController.shared.open(store: store, mode: .new)
                store.showNewAudit = false
            }
        }
        // Mise à jour → panel 3 colonnes
        .onChange(of: store.showUpdateSheet) { _, show in
            if show {
                AuditPanelController.shared.open(store: store, mode: .update)
                store.showUpdateSheet = false
            }
        }
        // Console standalone (bouton barre d'outils)
        .onChange(of: store.showLogs) { _, show in
            if show {
                LogsPanelController.shared.open(store: store)
                store.showLogs = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFindBar)) { _ in
            if showFind { showFind = false; findQuery = "" } else { showFind = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            zoomRatio = min(Self.zoomMax, zoomRatio + Self.zoomStep)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            zoomRatio = max(Self.zoomMin, zoomRatio - Self.zoomStep)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
            zoomRatio = 1.0
        }
        .preferredColorScheme(preferredScheme)
        .onChange(of: themeMode) { _, _ in
            // Notifie les WKWebView (carte + markdown) de réappliquer le thème.
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        Group {
            if store.viewMode == .kpis, let auditDir = store.auditDir {
                // Mode KPIs fullscreen
                VStack(spacing: 0) {
                    Text("Chiffres clés")
                        .font(.title2.weight(.semibold))
                        .padding(16)

                    ScrollView {
                        KPIGridView(dir: auditDir)
                            .padding(16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Mode Document / Carte (avec panneau KPIs optionnel)
                HStack(spacing: 0) {
                    // Contenu principal
                    ZStack(alignment: .top) {
                        if store.viewMode == .graph {
                            GraphWebView(
                                json: store.graphJSON(for: store.graphScope),
                                scope: store.graphScope,
                                store: store
                            )
                            .background(Color(nsColor: .textBackgroundColor))
                            .frame(minWidth: 480, minHeight: 320)
                            .id(store.graphScope)
                        } else {
                            WebView(markdown: store.currentMarkdown, zoom: zoomRatio)
                                .background(Color(nsColor: .textBackgroundColor))
                                .frame(minWidth: 480, minHeight: 320)
                        }

                        if showFind && store.viewMode == .document {
                            FindBar(
                                query: $findQuery,
                                onClose: { showFind = false; findQuery = "" },
                                onSubmit: { forward in
                                    NotificationCenter.default.post(
                                        name: .findRequest,
                                        object: nil,
                                        userInfo: ["query": findQuery, "forward": forward]
                                    )
                                }
                            )
                            .frame(maxWidth: 420)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Panneau d'infos d'un nœud Source/Acteur (double-clic sur la carte)
                        if store.viewMode == .graph, let info = store.graphInfo {
                            GraphInfoPanel(info: info, store: store)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showFind)
        .animation(.easeInOut(duration: 0.15), value: store.graphInfo?.id)
        .toolbar { toolbarItems }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if store.browseMode {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.backToList()
                } label: {
                    Label("Audits", systemImage: "chevron.left")
                }
                .help("Revenir à la liste des audits")
            }
        }

        ToolbarItem(placement: .navigation) {
            Picker("Vue", selection: Binding(
                get: { store.viewMode },
                set: { store.viewMode = $0 }
            )) {
                Label("Document", systemImage: "doc.text").tag(AuditStore.ViewMode.document)
                Label("Carte", systemImage: "point.3.connected.trianglepath.dotted").tag(AuditStore.ViewMode.graph)
                Label("Chiffres clés", systemImage: "chart.bar").tag(AuditStore.ViewMode.kpis)
            }
            .pickerStyle(.segmented)
            .help("Basculer entre le document, la carte et les chiffres clés")
        }

        if store.viewMode == .graph {
            ToolbarItem(placement: .navigation) {
                Picker("Périmètre", selection: Binding(
                    get: { store.graphScope },
                    set: { store.graphScope = $0 }
                )) {
                    Text("Audit courant").tag(AuditStore.GraphScope.local)
                    Text("Global").tag(AuditStore.GraphScope.global)
                }
                .pickerStyle(.segmented)
                .help("Carte de l'audit courant ou de tous les audits")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Picker(selection: $themeMode) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            } label: {
                Label("Thème", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
            .help("Thème d'affichage : Auto / Clair / Sombre")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                AuditPanelController.shared.open(store: store, mode: .new)
            } label: {
                Label("Nouvel audit", systemImage: "plus")
            }
            .help("Nouveau rapport d'audit (⌘N)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                store.openAuditFolder()
            } label: {
                Label("Ouvrir", systemImage: "folder")
            }
            .help("Ouvrir un dossier d'audit (⌘O)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                AuditPanelController.shared.open(store: store, mode: .update)
            } label: {
                Label("Mettre à jour", systemImage: "arrow.clockwise")
            }
            .help("Relancer l'audit pour voir les évolutions")
            .disabled(store.auditDir == nil)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.exportCurrentSectionToDocx()
            } label: {
                Label("Exporter en Word", systemImage: "arrow.down.doc")
            }
            .help("Exporter la section en cours au format .docx (Word)")
            .disabled(!store.canExportDocx)

            Button {
                store.exportCurrentSectionToPDF()
            } label: {
                Label("Exporter en PDF", systemImage: "doc.richtext")
            }
            .help("Exporter la section en cours au format PDF avec page de garde")
            .disabled(!store.canExportPDF)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                LogsPanelController.shared.open(store: store)
            } label: {
                Label("Console", systemImage: "terminal")
                    .overlay(alignment: .topTrailing) {
                        if store.isRunningAudit {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .help("Afficher la console Claude (logs en temps réel)")
            .disabled(store.logEntries.isEmpty && !store.isRunningAudit)
        }

        ToolbarItem(placement: .status) {
            if !store.subject.isEmpty {
                HStack(spacing: 4) {
                    Text(store.subject)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if store.hasChanges {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
