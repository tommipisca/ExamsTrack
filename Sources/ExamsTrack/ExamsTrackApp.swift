import SwiftUI
import UIKit
import WidgetKit
import AppIntents
import ExamsCore

/// Oggetti condivisi tra l'interfaccia e le azioni di Comandi Rapidi, che girano nello stesso processo:
/// usando lo stesso store, una modifica fatta da un comando compare subito anche nell'app aperta.
@MainActor
enum AppServices {
    static let store = ExamStore(fileURL: AppGroup.dataFileURL()) {
        reloadWidgetsAndControls()
    }
    static let study = StudySessionController()
    /// Vedi `ExamsTrackApp.init`.
    static var registeredIntents: [any AppIntent.Type] = []

    static func reloadWidgetsAndControls() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }
}

@main
struct ExamsTrackApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppServices.store
    @State private var study = AppServices.study

    init() {
        // Il tipo di tesi passa dalle preferenze dell'app a quelle condivise, una volta.
        let shared = AppGroup.sharedDefaults
        if shared.string(forKey: ThesisType.storageKey) == nil,
           let legacy = UserDefaults.standard.string(forKey: DisplayPreferences.legacyThesisType) {
            shared.set(legacy, forKey: ThesisType.storageKey)
        }
        // Il linker scarta i tipi delle azioni che nessuno usa: qui li si usa a runtime.
        AppServices.registeredIntents = ExamsTrackIntents.types
        // Pulsanti della notifica di fine sessione di studio.
        StudyNotificationHandler.install()
    }
    /// Data di riferimento per countdown, archivio e ritardi; aggiornata al ritorno in primo piano e a mezzanotte.
    @State private var today = Date.now
    @State private var notificationSettings = NotificationSettingsStore()
    @State private var sync = SyncService()
    @AppStorage(DegreeVisibility.storageKey, store: AppGroup.sharedDefaults)
    private var visibility: DegreeVisibility = .both

    /// Cambia quando cambiano i dati da cui dipendono le notifiche.
    private struct NotificationInputs: Equatable {
        var exams: [Exam]
        var settings: NotificationSettings
        var today: Date
        var visibility: DegreeVisibility
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(study)
                .environment(\.today, today)
                .environment(notificationSettings)
                .environment(sync)
                .environment(\.degreeVisibility, visibility)
                // Il widget legge la stessa preferenza: va ridisegnato quando cambia.
                .onChange(of: visibility) { WidgetCenter.shared.reloadAllTimelines() }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, sync.isEnabled {
                        // Uscendo dall'app (anche subito dopo una modifica) invia i dati prima della sospensione.
                        // Se iOS concede meno tempo del previsto, il compito si chiude comunque (niente chiusura forzata).
                        var backgroundTask = UIBackgroundTaskIdentifier.invalid
                        backgroundTask = UIApplication.shared.beginBackgroundTask {
                            UIApplication.shared.endBackgroundTask(backgroundTask)
                            backgroundTask = .invalid
                        }
                        Task {
                            await sync.sync(store: store)
                            if backgroundTask != .invalid {
                                UIApplication.shared.endBackgroundTask(backgroundTask)
                            }
                        }
                    }
                    if phase == .active {
                        today = .now
                        // Prende i task spuntati dal widget mentre l'app era in pausa, prima di salvare o sincronizzare.
                        store.reloadFromDisk()
                        Task {
                            await study.refresh()
                            // Richiesta dal controllo "Sessione di studio" del Centro di Controllo.
                            if StudySession.takePendingRequest(from: AppGroup.sharedDefaults) {
                                _ = await study.startSuggested(exams: store.exams.visible(visibility))
                            }
                        }
                        // Al ritorno in primo piano prende le modifiche fatte sull'altro dispositivo.
                        Task { await sync.sync(store: store) }
                    }
                }
                // Dopo ogni modifica (e all'avvio) sincronizza, con 2 secondi di attesa per raggruppare
                // le modifiche ravvicinate: una nuova modifica annulla l'attesa precedente.
                .task(id: store.exams) {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await sync.sync(store: store)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    today = .now
                }
                // Live Activity del giorno dell'esame: all'apertura e a ogni modifica di esami o del giorno.
                .task(id: NotificationInputs(
                    exams: store.exams, settings: notificationSettings.settings, today: today, visibility: visibility
                )) {
                    await ExamActivityController.refresh(exams: store.exams.visible(visibility))
                }
                // Ripianifica le notifiche a ogni modifica di esami, task o preferenze.
                .task(id: NotificationInputs(
                    exams: store.exams, settings: notificationSettings.settings, today: today, visibility: visibility
                )) {
                    // Niente notifiche per gli esami del corso nascosto.
                    await NotificationScheduler.reschedule(
                        exams: store.exams.visible(visibility), settings: notificationSettings.settings
                    )
                }
        }
    }
}

private struct TodayKey: EnvironmentKey {
    static var defaultValue: Date { .now }
}

extension EnvironmentValues {
    var today: Date {
        get { self[TodayKey.self] }
        set { self[TodayKey.self] = newValue }
    }
}

private struct DegreeVisibilityKey: EnvironmentKey {
    static let defaultValue: DegreeVisibility = .both
}

extension EnvironmentValues {
    /// Corsi di laurea mostrati (preferenza in Impostazioni → Visualizzazione).
    var degreeVisibility: DegreeVisibility {
        get { self[DegreeVisibilityKey.self] }
        set { self[DegreeVisibilityKey.self] = newValue }
    }
}
