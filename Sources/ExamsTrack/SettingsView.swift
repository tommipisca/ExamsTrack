import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit
import ExamsCore

/// Scheda "Impostazioni": notifiche e backup dei dati.
struct SettingsView: View {
    @Environment(ExamStore.self) private var store
    @Environment(NotificationSettingsStore.self) private var notificationStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(DisplayPreferences.startTab) private var startTab: AppTab = .today
    @AppStorage(DisplayPreferences.careerFilter) private var careerFilter: Degree = .triennale
    @AppStorage(ThesisType.storageKey, store: AppGroup.sharedDefaults) private var thesisType: ThesisType = .withReviewer
    @AppStorage(DegreeVisibility.storageKey, store: AppGroup.sharedDefaults)
    private var visibility: DegreeVisibility = .both
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var exportDocument: BackupDocument?
    @Environment(SyncService.self) private var sync
    @State private var showingImporter = false
    /// Cosa si sta scegliendo con l'unico selettore di file della schermata.
    @State private var importKind: ImportKind = .backup

    private enum ImportKind {
        case backup, syncFolder
    }
    @State private var pendingImport: Data?
    @State private var backupMessage: String?

    var body: some View {
        @Bindable var notificationStore = notificationStore

        NavigationStack {
            List {
                displaySection
                if visibility.includes(.magistrale) {
                    careerSection
                }
                syncSection
                notificationsSection(settings: $notificationStore.settings)
                backupSection
                installationSection
            }
            .tabScreenStyle()
            .navigationTitle("Impostazioni")
            .task(id: scenePhase) { authorization = await NotificationScheduler.authorizationStatus() }
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: .json,
                defaultFilename: ExamStore.backupFileName()
            ) { result in
                if case .success = result {
                    backupMessage = "Backup esportato."
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: importKind == .syncFolder ? [.folder] : [.json]
            ) { result in
                guard case .success(let url) = result else { return }
                switch importKind {
                case .backup:
                    readBackup(at: url)
                case .syncFolder:
                    sync.link(folder: url)
                    Task { await sync.sync(store: store) }
                }
            }
            .confirmationDialog(
                "Sostituire tutti i dati con il backup?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                titleVisibility: .visible
            ) {
                Button("Sostituisci i dati", role: .destructive) {
                    Task { await importPendingBackup() }
                }
            } message: {
                Text("Esami, task e voti attuali verranno sostituiti da quelli del file.")
            }
            .alert("Backup", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(backupMessage ?? "")
            }
        }
        .storeErrorAlert()
    }

    // MARK: Visualizzazione

    private var displaySection: some View {
        Section {
            Picker("Scheda all'apertura", selection: $startTab) {
                ForEach(AppTab.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            Picker("Corsi di laurea", selection: $visibility.animation()) {
                ForEach(DegreeVisibility.allCases) { Text($0.label).tag($0) }
            }
            if visibility.fixedDegree == nil {
                Picker("Carriera default", selection: $careerFilter) {
                    ForEach(Degree.allCases) { Text($0.label).tag($0) }
                }
            }
        } header: {
            Text("Visualizzazione").sectionHeaderStyle()
        } footer: {
            Text("Con un solo corso, gli esami dell'altro restano salvati e sincronizzati ma non compaiono da nessuna parte, neanche nel widget e nelle notifiche. Scheda all'apertura e filtro carriera valgono dal prossimo avvio.")
        }
        .listRowBackground(Theme.surface)
        .tint(Theme.accent)
    }

    // MARK: Carriera

    private var careerSection: some View {
        Section {
            Picker("Tesi magistrale", selection: $thesisType) {
                ForEach(ThesisType.allCases) { Text($0.label).tag($0) }
            }
            // Il widget "Media e simulazione" stima il voto di laurea con questa scelta.
            .onChange(of: thesisType) { WidgetCenter.shared.reloadTimelines(ofKind: "CareerWidget") }
        } header: {
            Text("Carriera").sectionHeaderStyle()
        } footer: {
            Text("Serve alla stima del voto di laurea magistrale: la tesi vale fino a 7 punti con controrelatore, fino a 4 senza. La lode è possibile solo con controrelatore.")
        }
        .listRowBackground(Theme.surface)
        .tint(Theme.accent)
    }

    // MARK: Notifiche

    private func notificationsSection(settings: Binding<NotificationSettings>) -> some View {
        Group {
            if authorization == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifiche disattivate", systemImage: "bell.slash")
                            .font(.ui(.body, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                        Text("Per ricevere i promemoria, attiva le notifiche di ExamsTrack nelle Impostazioni di iOS.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Apri Impostazioni di iOS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.ui(.subheadline, weight: .semibold))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.surface)
                }
            }

            Section {
                let active = ReminderOffset.allCases.filter { settings.wrappedValue.examReminders.contains($0) }
                let available = ReminderOffset.allCases.filter { !settings.wrappedValue.examReminders.contains($0) }

                if active.isEmpty {
                    Text("Nessun promemoria per gli esami")
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.surface)
                }
                ForEach(active) { offset in
                    HStack {
                        Label(offset.label, systemImage: "bell.fill")
                            .labelStyle(ReminderLabelStyle())
                        Spacer()
                        Button {
                            remove(offset, from: settings)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Rimuovi \(offset.label)")
                    }
                    .listRowBackground(Theme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Rimuovi", role: .destructive) { remove(offset, from: settings) }
                    }
                }

                if !available.isEmpty {
                    Menu {
                        ForEach(available) { offset in
                            Button(offset.label) {
                                _ = withAnimation { settings.wrappedValue.examReminders.insert(offset) }
                            }
                        }
                    } label: {
                        Label("Aggiungi promemoria", systemImage: "plus.circle.fill")
                            .font(.ui(.body, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .listRowBackground(Theme.surface)
                }
            } header: {
                Text("Promemoria esami").sectionHeaderStyle()
            } footer: {
                Text("Valgono per tutti gli esami programmati. Gli esami da programmare non hanno promemoria.")
            }

            Section {
                Toggle("Task in scadenza oggi", isOn: settings.dailyTaskSummary)
                    .listRowBackground(Theme.surface)
                DatePicker("Orario delle notifiche", selection: time(settings), displayedComponents: .hourAndMinute)
                    .listRowBackground(Theme.surface)
            } header: {
                Text("Promemoria giornaliero").sectionHeaderStyle()
            } footer: {
                Text("Nei giorni in cui scadono dei task ricevi l'elenco di quelli ancora da fare.")
            }
        }
        .tint(Theme.accent)
    }

    private func remove(_ offset: ReminderOffset, from settings: Binding<NotificationSettings>) {
        _ = withAnimation { settings.wrappedValue.examReminders.remove(offset) }
    }

    /// L'orario come data di oggi, per il selettore di ore e minuti.
    private func time(_ settings: Binding<NotificationSettings>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.wrappedValue.hour, minute: settings.wrappedValue.minute, second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.wrappedValue.hour = parts.hour ?? 9
                settings.wrappedValue.minute = parts.minute ?? 0
            }
        )
    }

    // MARK: Backup

    // MARK: Sincronizzazione

    private var syncSection: some View {
        Section {
            if let folder = sync.folderName {
                LabeledContent("Cartella", value: folder)
                    .listRowBackground(Theme.surface)
                LabeledContent("Ultima sincronizzazione") {
                    if sync.isSyncing {
                        ProgressView()
                    } else {
                        Text(sync.lastSync.map { $0.formatted(.relative(presentation: .named).locale(Locale(identifier: "it_IT"))) } ?? "Mai")
                    }
                }
                .listRowBackground(Theme.surface)
                LabeledContent("Ultimo backup automatico") {
                    Text(sync.lastAutoBackup.map { $0.formatted(.relative(presentation: .named).locale(Locale(identifier: "it_IT"))) } ?? "Mai")
                }
                .listRowBackground(Theme.surface)
                if let error = sync.errorMessage {
                    Label(error, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .listRowBackground(Theme.surface)
                }
                Button {
                    Task { await sync.sync(store: store) }
                } label: {
                    Label("Sincronizza ora", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(sync.isSyncing)
                .listRowBackground(Theme.surface)
                Button("Scollega cartella", role: .destructive) { sync.unlink() }
                    .listRowBackground(Theme.surface)
            } else {
                Button {
                    importKind = .syncFolder
                    showingImporter = true
                } label: {
                    Label("Scegli cartella in iCloud Drive", systemImage: "icloud")
                }
                .listRowBackground(Theme.surface)
            }
        } header: {
            Text("Sincronizzazione").sectionHeaderStyle()
        } footer: {
            Text("Scegli la stessa cartella su iPhone e iPad: i dati si uniscono esame per esame e, se modifichi lo stesso esame su entrambi, vince la modifica più recente. Le modifiche dell'altro dispositivo arrivano quando riapri l'app o trascini verso il basso una lista. Ogni giorno viene salvato un backup nella sottocartella Backup (gli ultimi 14).")
        }
    }

    // MARK: Installazione

    private var installationSection: some View {
        Section {
            if let expiration = ProvisioningProfile.embeddedExpirationDate() {
                let days = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: expiration)
                ).day ?? 0
                LabeledContent("Scadenza dell'app") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(days <= 0 ? "Oggi" : days == 1 ? "Domani" : "Tra \(days) giorni")
                            .font(.ui(.body, weight: .semibold))
                            .foregroundStyle(days <= 1 ? Theme.danger : days <= 3 ? Theme.warning : Theme.textPrimary)
                        Text(expiration.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()
                            .locale(Locale(identifier: "it_IT"))))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.surface)
            } else {
                LabeledContent("Scadenza dell'app", value: "Non disponibile")
                    .listRowBackground(Theme.surface)
            }
        } header: {
            Text("Installazione").sectionHeaderStyle()
        } footer: {
            Text("Con l'account sviluppatore gratuito l'app va reinstallata ogni 7 giorni con xtool dev: il giorno prima ricevi una notifica. I dati restano.")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                do {
                    exportDocument = BackupDocument(data: try store.exportBackup())
                } catch {
                    backupMessage = "Impossibile creare il backup."
                }
            } label: {
                Label("Esporta dati", systemImage: "square.and.arrow.up")
            }
            .listRowBackground(Theme.surface)

            Button {
                importKind = .backup
                showingImporter = true
            } label: {
                Label("Importa backup", systemImage: "square.and.arrow.down")
            }
            .listRowBackground(Theme.surface)
        } header: {
            Text("Backup").sectionHeaderStyle()
        } footer: {
            Text("Salva il file in File o su iCloud Drive. Con l'account gratuito, se l'app viene eliminata i dati si perdono: esporta ogni tanto.")
        }
    }

    private func readBackup(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try Data(contentsOf: url)
        } catch {
            backupMessage = "Impossibile leggere il file scelto."
        }
    }

    private func importPendingBackup() async {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            // Prima prende gli esami creati sull'altro dispositivo: così il ripristino elimina anche quelli,
            // invece di vederli ricomparire alla sincronizzazione successiva.
            await sync.sync(store: store)
            try store.importBackup(data)
            await sync.sync(store: store)
            backupMessage = "Backup importato: \(store.exams.count) esami ripristinati."
        } catch let error as BackupError {
            backupMessage = error.message
        } catch {
            backupMessage = BackupError.unreadable.message
        }
    }
}

/// Icona del promemoria piccola e nel colore del tema, accanto al testo.
private struct ReminderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.footnote)
                .foregroundStyle(Theme.accent)
            configuration.title
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// File JSON del backup, per l'esportazione con il selettore di file.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
