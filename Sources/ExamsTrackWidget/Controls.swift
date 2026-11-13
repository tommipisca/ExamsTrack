import AppIntents
import SwiftUI
import WidgetKit
import ExamsCore

/// Spunta il primo task da fare di oggi (o il più vecchio in ritardo), dal Centro di Controllo.
/// Gira nell'estensione come la spunta dei widget: scrive il file dell'App Group.
@available(iOS 18.0, *)
struct CompleteNextTodayTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Spunta il prossimo task di oggi"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = ExamStore(fileURL: AppGroup.dataFileURL())
        if let next = TodaySummary.make(from: store.exams.visible(.saved), today: .now).nextTask,
           let examID = next.examID, let taskID = next.taskID {
            RecentlyCompleted(defaults: AppGroup.sharedDefaults).set(taskID: taskID, isDone: true, at: .now)
            store.setTaskDone(id: taskID, inExam: examID)
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

/// Apre l'app e avvia una sessione di studio: le Live Activity partono solo con l'app in primo piano.
/// Un'azione con `openAppWhenRun` non può girare nell'estensione: iOS esegue la gemella con lo stesso nome
/// nell'app (`ExamsTrack/ShortcutsIntents.swift`). Questa serve al controllo per riferirsi all'azione; se mai
/// girasse qui, lascia comunque la richiesta che l'app trova all'apertura.
@available(iOS 18.0, *)
struct OpenStudySessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Avvia una sessione di studio"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        StudySession.requestStart(in: AppGroup.sharedDefaults)
        return .result()
    }
}

/// Il titolo del prossimo task di oggi, mostrato nel controllo.
@available(iOS 18.0, *)
struct NextTodayTaskValueProvider: ControlValueProvider {
    var previewValue: String? { "Ripasso capitolo 4" }

    func currentValue() async throws -> String? {
        guard let exams = widgetExams() else { return nil }
        return TodaySummary.make(from: exams, today: .now).nextTask?.title
    }
}

@available(iOS 18.0, *)
struct NextTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NextTaskControl", provider: NextTodayTaskValueProvider()) { title in
            ControlWidgetButton(action: CompleteNextTodayTaskIntent()) {
                Label(title ?? "Niente da fare oggi", systemImage: title == nil ? "checkmark.seal" : "checkmark.circle")
            }
        }
        .displayName("Prossimo task")
        .description("Spunta il primo task da fare di oggi.")
    }
}

@available(iOS 18.0, *)
struct StudySessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StudySessionControl") {
            ControlWidgetButton(action: OpenStudySessionIntent()) {
                Label("Sessione di studio", systemImage: "timer")
            }
        }
        .displayName("Sessione di studio")
        .description("Avvia un timer sul prossimo task di oggi, con l'ultima durata scelta.")
    }
}
