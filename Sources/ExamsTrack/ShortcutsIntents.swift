import AppIntents
import Foundation
import ExamsCore

/// Un esame da sostenere, per le azioni di Comandi Rapidi.
struct StudyExamEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Esame"
    static let defaultQuery = StudyExamQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct StudyExamQuery: EntityQuery {
    @MainActor
    private func exams() -> [Exam] {
        AppServices.store.reloadFromDisk()
        return AppServices.store.exams.visible(.saved).active(today: .now)
    }

    func entities(for identifiers: [String]) async throws -> [StudyExamEntity] {
        await exams().filter { identifiers.contains($0.id.uuidString) }
            .map { StudyExamEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func suggestedEntities() async throws -> [StudyExamEntity] {
        await exams().map { StudyExamEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

/// "Cosa devo studiare oggi?": legge i task di oggi e quelli in ritardo.
struct WhatToStudyTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Cosa devo studiare oggi"
    static let description = IntentDescription("Elenca i task di oggi e quelli in ritardo di tutti gli esami.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.store.reloadFromDisk()
        let today = TodaySummary.make(from: AppServices.store.exams.visible(.saved), today: .now)
        let open = today.tasks.filter { !$0.isDone }
        guard !open.isEmpty else {
            return .result(dialog: today.totalToday > 0 ? "Hai già fatto tutto per oggi." : "Oggi non hai niente in programma.")
        }
        let list = open.prefix(5).map { "\($0.title) per \($0.examName)" }.joined(separator: "; ")
        let more = open.count > 5 ? " e altri \(open.count - 5)" : ""
        let late = today.overdueCount > 0 ? " Di questi, \(today.overdueCount) in ritardo." : ""
        let count = open.count == 1 ? "un task" : "\(open.count) task"
        return .result(dialog: "Oggi hai \(count): \(list)\(more).\(late)")
    }
}

/// Segna come fatto il primo task da fare di oggi (o il più vecchio in ritardo).
struct CompleteNextTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Segna fatto il prossimo task"
    static let description = IntentDescription("Spunta il primo task da fare oggi, partendo da quelli in ritardo.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppServices.store
        store.reloadFromDisk()
        guard let next = TodaySummary.make(from: store.exams.visible(.saved), today: .now).nextTask,
              let examID = next.examID, let taskID = next.taskID else {
            return .result(dialog: "Non c'è niente da fare oggi.")
        }
        store.setTaskDone(id: taskID, inExam: examID)
        if let error = store.lastError { return .result(dialog: "\(error.message)") }
        return .result(dialog: "Fatto: \(next.title) per \(next.examName).")
    }
}

/// Aggiunge un task a un esame, in scadenza oggi se non si indica una data.
struct AddStudyTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiungi un task"
    static let description = IntentDescription("Aggiunge un task di studio a un esame.")

    @Parameter(title: "Esame") var exam: StudyExamEntity
    @Parameter(title: "Task") var title: String
    @Parameter(title: "Entro il") var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Aggiungi \(\.$title) a \(\.$exam)") {
            \.$dueDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppServices.store
        store.reloadFromDisk()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let examID = UUID(uuidString: exam.id), store.exam(id: examID) != nil, !name.isEmpty else {
            return .result(dialog: "Non ho trovato l'esame.")
        }
        store.addTask(StudyTask(title: name, dueDate: dueDate ?? .now), toExam: examID)
        if let error = store.lastError { return .result(dialog: "\(error.message)") }
        return .result(dialog: "Aggiunto «\(name)» a \(exam.name).")
    }
}

/// Avvia una sessione di studio sul prossimo task: apre l'app, perché iOS avvia le Live Activity
/// solo con l'app in primo piano.
struct StartStudySessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Avvia una sessione di studio"
    static let description = IntentDescription("Timer di studio sul prossimo task di oggi, sulla schermata di blocco.")
    static let openAppWhenRun = true

    /// Senza durata, l'ultima scelta nell'app.
    @Parameter(title: "Minuti", inclusiveRange: (5, 180)) var minutes: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.store.reloadFromDisk()
        let duration = minutes ?? AppServices.study.lastMinutes
        let started = await AppServices.study.startSuggested(exams: AppServices.store.exams.visible(.saved), minutes: duration)
        return .result(dialog: started ? "Sessione di \(duration) minuti avviata." : "Non c'è nessun esame da preparare.")
    }
}

/// Gemella dell'azione del controllo "Sessione di studio" (stesso nome, nel widget): un'azione che apre l'app
/// non può girare nell'estensione, quindi iOS esegue questa, nell'app già in primo piano.
struct OpenStudySessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Avvia una sessione di studio"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.store.reloadFromDisk()
        _ = await AppServices.study.startSuggested(exams: AppServices.store.exams.visible(.saved))
        return .result()
    }
}

/// Le azioni dell'app per Comandi Rapidi. Niente frasi di Siri (`AppShortcutsProvider`): Siri non le abbinava
/// a un'app installata con xtool, quindi le azioni si usano dai comandi personali.
enum ExamsTrackIntents {
    /// Vedi `ExamsTrackApp.init`: tiene i tipi nel binario.
    static let types: [any AppIntent.Type] = [
        WhatToStudyTodayIntent.self, CompleteNextTaskIntent.self, AddStudyTaskIntent.self, StartStudySessionIntent.self,
        OpenStudySessionIntent.self,
    ]
}
