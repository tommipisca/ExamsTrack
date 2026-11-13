import AppIntents
import WidgetKit
import ExamsCore

/// Un esame da scegliere nella configurazione del widget.
struct ExamEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Esame"
    static let defaultQuery = ExamEntityQuery()

    /// UUID dell'esame come testo, oppure `automaticID`.
    var id: String
    var name: String

    /// Voce "segui il prossimo esame": iOS non sempre permette di svuotare la scelta,
    /// quindi la visuale generica è una voce dell'elenco come le altre.
    static let automaticID = "automatic"
    static let automatic = ExamEntity(id: automaticID, name: "Prossimo esame (automatico)")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Gli esami proponibili: da sostenere e già programmati, del corso visibile, dal più vicino.
struct ExamEntityQuery: EntityQuery {
    private func exams() -> [Exam] {
        (ExamStore.readOnly(from: AppGroup.dataFileURL()) ?? [])
            .visible(.saved)
            .active(today: .now)
            .filter(\.isScheduled)
    }

    func entities(for identifiers: [String]) async throws -> [ExamEntity] {
        // Anche esami non più proponibili (già sostenuti), così la configurazione ne mostra ancora il nome.
        let exams = (ExamStore.readOnly(from: AppGroup.dataFileURL()) ?? [])
            .filter { identifiers.contains($0.id.uuidString) }
            .map { ExamEntity(id: $0.id.uuidString, name: $0.name) }
        return identifiers.contains(ExamEntity.automaticID) ? [.automatic] + exams : exams
    }

    func suggestedEntities() async throws -> [ExamEntity] {
        [.automatic] + exams().map { ExamEntity(id: $0.id.uuidString, name: $0.name) }
    }

    /// Un widget appena aggiunto segue il prossimo esame.
    func defaultResult() async -> ExamEntity? {
        .automatic
    }
}

/// Configurazione del widget "Prossimo esame": senza scelta segue il prossimo esame.
struct SelectExamIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Scegli l'esame"
    static let description = IntentDescription("Scegli un esame, o \"Prossimo esame\" per seguire sempre il più vicino.")

    @Parameter(title: "Esame")
    var exam: ExamEntity?

    /// Spento: solo i task dell'esame mostrato (scelto o prossimo). Acceso: quelli di tutti gli esami.
    @Parameter(title: "Mostra anche i task degli altri esami", default: false)
    var includeOtherExams: Bool

    init() {}
}
