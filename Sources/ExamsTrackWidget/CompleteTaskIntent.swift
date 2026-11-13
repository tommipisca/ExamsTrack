import AppIntents
import WidgetKit
import ExamsCore

/// Spunta (o riapre) un task dal widget. Gira nell'estensione: scrive il file dell'App Group,
/// che l'app rilegge al ritorno in primo piano (e poi sincronizza con gli altri dispositivi).
/// Il task spuntato resta visibile, barrato, per `RecentlyCompleted.window` secondi.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Segna task come fatto"
    static let isDiscoverable = false

    @Parameter(title: "Esame") var examID: String
    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Fatto") var isDone: Bool

    init() {}

    init(examID: UUID, taskID: UUID, isDone: Bool) {
        self.examID = examID.uuidString
        self.taskID = taskID.uuidString
        self.isDone = isDone
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let exam = UUID(uuidString: examID), let task = UUID(uuidString: taskID) else { return .result() }
        let store = ExamStore(fileURL: AppGroup.dataFileURL())
        RecentlyCompleted(defaults: AppGroup.sharedDefaults).set(taskID: task, isDone: isDone, at: .now)
        store.setTaskDone(id: task, inExam: exam, isDone: isDone)
        if let error = store.lastError {
            NSLog("ExamsTrack widget: spunta non salvata (%@)", error.message)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
