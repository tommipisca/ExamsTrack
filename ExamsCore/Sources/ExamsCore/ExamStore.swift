import Foundation
import Observation

public enum StoreError: Error, Equatable, Sendable {
    case corruptedData
    case saveFailed
    case readFailed

    public var message: String {
        switch self {
        case .corruptedData:
            "I dati salvati erano illeggibili: sono stati spostati in exams.corrupt.json e l'elenco è ripartito da zero."
        case .saveFailed:
            "Impossibile salvare le modifiche."
        case .readFailed:
            "Impossibile leggere i dati salvati. Per non sovrascriverli, le modifiche non verranno salvate: chiudi e riapri l'app."
        }
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case unreadable

    public var message: String {
        "Il file non è un backup di ExamsTrack leggibile. I dati attuali non sono stati modificati."
    }
}

/// Contenuto di un file di backup.
struct BackupFile: Codable {
    var version: Int
    var exportedAt: Date
    var exams: [Exam]
}

@MainActor
@Observable
public final class ExamStore {
    public private(set) var exams: [Exam] = []
    public var lastError: StoreError?
    /// Chiamato dopo ogni salvataggio riuscito (l'app lo usa per ricaricare il widget).
    @ObservationIgnored public var onSave: (() -> Void)?

    private let fileURL: URL
    private let calendar: Calendar
    private let now: () -> Date
    /// Esami eliminati (id → data), salvati accanto ai dati per la sincronizzazione.
    private var deletions: [String: Date] = [:]
    /// Vero se il file esiste ma non è stato possibile leggerlo: in quel caso non si salva, per non sovrascriverlo.
    private var isReadBlocked = false

    private var deletionsURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("deletions.json")
    }

    public init(
        fileURL: URL,
        calendar: Calendar = .current,
        onSave: (() -> Void)? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.onSave = onSave
        self.now = now
        load()
    }

    // MARK: Sincronizzazione

    /// Dati e eliminazioni da confrontare con quelli degli altri dispositivi.
    public var syncSnapshot: SyncSnapshot {
        SyncSnapshot(exams: exams, deletions: deletions)
    }

    /// Applica il risultato di un'unione; non salva se non cambia nulla.
    public func applySynced(_ snapshot: SyncSnapshot) {
        guard snapshot.exams != exams || snapshot.deletions != deletions else { return }
        exams = snapshot.exams
        deletions = snapshot.deletions
        assignMissingColors()
        save()
    }

    /// Rilegge i dati dal file, se qualcun altro (il widget) li ha cambiati mentre l'app era in pausa.
    /// Se il file non si legge tiene quelli in memoria.
    public func reloadFromDisk() {
        guard !isReadBlocked,
              let data = try? Data(contentsOf: fileURL),
              let saved = try? Self.makeDecoder().decode([Exam].self, from: data) else { return }
        let reloaded = saved.map(normalized)
        if reloaded != exams {
            exams = reloaded
        }
        if let data = try? Data(contentsOf: deletionsURL),
           let saved = try? Self.makeDecoder().decode([String: Date].self, from: data), saved != deletions {
            deletions = saved
        }
    }

    // MARK: Lettura

    /// Corso proposto per un nuovo esame: quello dell'ultimo esame inserito.
    public var defaultDegree: Degree {
        exams.last?.degree ?? .triennale
    }

    public func exam(id: UUID) -> Exam? {
        exams.first { $0.id == id }
    }

    /// Lettura per il widget, senza modificare file: [] se non ci sono dati,
    /// nil se il file esiste ma non si legge (es. protetto prima del primo sblocco).
    nonisolated public static func readOnly(from url: URL) -> [Exam]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? makeDecoder().decode([Exam].self, from: data)
    }

    // MARK: Esami

    public func addExam(_ exam: Exam) {
        var exam = exam
        if exam.colorIndex == nil {
            exam.colorIndex = nextColorIndex
        }
        exam.modifiedAt = timestamp()
        exams.append(normalized(exam))
        save()
    }

    /// Colore che riceverà il prossimo esame creato: il meno usato della tavolozza.
    public var nextColorIndex: Int {
        Palette.balancedColorIndex(used: exams.compactMap(\.colorIndex))
    }

    /// Assegna un colore agli esami che non ce l'hanno, nell'ordine in cui compaiono.
    /// Restituisce vero se ha cambiato qualcosa.
    @discardableResult
    private func assignMissingColors() -> Bool {
        var changed = false
        for index in exams.indices where exams[index].colorIndex == nil {
            exams[index].colorIndex = nextColorIndex
            changed = true
        }
        return changed
    }

    public func updateExam(_ exam: Exam) {
        mutateExam(exam.id) { $0 = exam }
    }

    /// Cambia solo i dati del form (nome, data, corso, CFU, prova finale), senza toccare task ed esito.
    public func updateExamDetails(
        id: UUID, name: String, date: Date, degree: Degree, cfu: Int, isFinalTest: Bool, isScheduled: Bool,
        startTime: Int?
    ) {
        mutateExam(id) { exam in
            exam.name = name
            exam.date = date
            exam.degree = degree
            exam.cfu = cfu
            exam.isFinalTest = isFinalTest
            exam.isScheduled = isScheduled
            exam.startTime = startTime
        }
    }

    public func deleteExam(id: UUID) {
        // Sempre dopo l'ultima modifica nota, anche se l'orologio di questo dispositivo è indietro.
        let deletedAt = stamp(after: exam(id: id)?.modifiedAt)
        exams.removeAll { $0.id == id }
        deletions[id.uuidString] = deletedAt
        save()
    }

    // MARK: Task

    public func addTask(_ task: StudyTask, toExam examID: UUID) {
        mutateExam(examID) { $0.tasks.append(task) }
    }

    public func updateTask(_ task: StudyTask, inExam examID: UUID) {
        mutateExam(examID) { exam in
            guard let index = exam.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            exam.tasks[index] = task
        }
    }

    public func deleteTask(id: UUID, fromExam examID: UUID) {
        mutateExam(examID) { $0.tasks.removeAll { $0.id == id } }
    }

    /// Sposta un task a un altro giorno (mai oltre il giorno dell'esame).
    public func moveTask(id: UUID, inExam examID: UUID, to day: Date) {
        mutateExam(examID) { exam in
            guard let index = exam.tasks.firstIndex(where: { $0.id == id }) else { return }
            exam.tasks[index].dueDate = day
        }
    }

    /// Ridistribuisce i task in ritardo di un esame da oggi fino all'esame.
    public func rescheduleOverdue(examID: UUID, today: Date = .now) {
        mutateExam(examID) { exam in
            exam.tasks = StudyPlanner.rescheduleOverdue(exam, today: today, calendar: calendar)
        }
    }

    /// Segna un task come fatto (o da fare); non salva se è già in quello stato,
    /// così un doppio tocco dal widget non lo riapre.
    public func setTaskDone(id: UUID, inExam examID: UUID, isDone: Bool = true) {
        guard exam(id: examID)?.tasks.first(where: { $0.id == id })?.isDone == !isDone else { return }
        toggleTask(id: id, inExam: examID)
    }

    /// Spunta (o riapre) un task; con sotto-task, li spunta (o riapre) tutti.
    public func toggleTask(id: UUID, inExam examID: UUID) {
        mutateExam(examID) { exam in
            guard let index = exam.tasks.firstIndex(where: { $0.id == id }) else { return }
            exam.tasks[index].isDone.toggle()
            let isDone = exam.tasks[index].isDone
            for sub in exam.tasks[index].subtasks.indices {
                exam.tasks[index].subtasks[sub].isDone = isDone
            }
        }
    }

    /// Spunta una voce della checklist; il task risulta fatto quando lo sono tutte.
    public func toggleSubtask(id: UUID, inTask taskID: UUID, inExam examID: UUID) {
        mutateExam(examID) { exam in
            guard let index = exam.tasks.firstIndex(where: { $0.id == taskID }),
                  let sub = exam.tasks[index].subtasks.firstIndex(where: { $0.id == id }) else { return }
            exam.tasks[index].subtasks[sub].isDone.toggle()
        }
    }

    // MARK: Esito

    /// Imposta l'esito normalizzando: voto 18...30 solo se superato (default 18), lode solo con 30.
    public func setOutcome(examID: UUID, passed: Bool?, grade: Int?, honors: Bool) {
        mutateExam(examID) { exam in
            exam.passed = passed
            if exam.isMasterThesis {
                // La tesi non ha voto né lode: solo il punteggio, che resta finché è superata.
                exam.grade = nil
                exam.honors = false
                if passed != true {
                    exam.thesisPoints = nil
                }
            } else if passed == true {
                let normalized = min(max(grade ?? 18, 18), 30)
                exam.grade = normalized
                exam.honors = honors && normalized == 30
            } else {
                exam.grade = nil
                exam.honors = false
            }
        }
    }

    // MARK: Backup

    /// Tutti gli esami in un file JSON da salvare fuori dall'app.
    public func exportBackup(now: Date = .now) throws -> Data {
        try Self.makeEncoder().encode(BackupFile(version: 1, exportedAt: now, exams: exams))
    }

    /// Sostituisce tutti i dati con quelli del backup; accetta anche un `exams.json` dell'app.
    /// Se il file non si legge, i dati attuali restano invariati.
    public func importBackup(_ data: Data) throws {
        let decoder = Self.makeDecoder()
        let imported: [Exam]
        if let backup = try? decoder.decode(BackupFile.self, from: data) {
            imported = backup.exams
        } else if let plain = try? decoder.decode([Exam].self, from: data) {
            imported = plain
        } else {
            throw BackupError.unreadable
        }
        // Il backup sostituisce tutto, anche sugli altri dispositivi: gli esami assenti risultano eliminati.
        let importedIDs = Set(imported.map(\.id))
        let timestamp = timestamp()
        for exam in exams where !importedIDs.contains(exam.id) {
            deletions[exam.id.uuidString] = timestamp
        }
        for id in importedIDs {
            deletions[id.uuidString] = nil
        }
        exams = SyncMerger.unique(imported).map { exam in
            var exam = normalized(exam)
            exam.modifiedAt = timestamp
            return exam
        }
        assignMissingColors()
        // Un ripristino esplicito sostituisce anche un file che non si riusciva a leggere.
        isReadBlocked = false
        save()
    }

    nonisolated public static func backupFileName(now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "ExamsTrack-backup-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func setNotes(examID: UUID, notes: String) {
        mutateExam(examID) { $0.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Voto ipotetico del simulatore (18...30), nil per toglierlo.
    public func setSimulatedGrade(examID: UUID, grade: Int?) {
        // Non passa da mutateExam: la simulazione ha una data di modifica tutta sua.
        guard let index = exams.firstIndex(where: { $0.id == examID }) else { return }
        exams[index].simulatedGrade = grade.map { min(max($0, 18), 30) }
        exams[index].simulationModifiedAt = timestamp()
        save()
    }

    /// Toglie tutti i voti ipotetici di un corso.
    public func clearSimulation(degree: Degree) {
        let stamp = timestamp()
        var changed = false
        for index in exams.indices where exams[index].degree == degree && exams[index].simulatedGrade != nil {
            exams[index].simulatedGrade = nil
            exams[index].simulationModifiedAt = stamp
            changed = true
        }
        if changed { save() }
    }

    /// Punteggio della tesi magistrale: da −1 a 8, a passi di mezzo punto.
    public func setThesisPoints(examID: UUID, points: Double) {
        mutateExam(examID) { exam in
            exam.thesisPoints = (min(max(points, -1), 8) * 2).rounded() / 2
        }
    }

    // MARK: Persistenza

    private func mutateExam(_ id: UUID, _ change: (inout Exam) -> Void) {
        guard let index = exams.firstIndex(where: { $0.id == id }) else { return }
        change(&exams[index])
        exams[index] = normalized(exams[index])
        exams[index].modifiedAt = stamp(after: exams[index].modifiedAt)
        save()
    }

    /// Adesso, al secondo: è la precisione con cui le date vengono salvate,
    /// così un esame riletto dal file è identico a quello in memoria.
    private func timestamp() -> Date {
        Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
    }

    /// Data di modifica sempre successiva a quella precedente (orologio logico): così una modifica
    /// fatta qui vince anche se l'orologio di un altro dispositivo era avanti.
    private func stamp(after previous: Date?) -> Date {
        max(timestamp(), (previous ?? .distantPast).addingTimeInterval(1))
    }

    /// Date a mezzogiorno (stabili ai cambi di fuso) e scadenze dei task non oltre il giorno dell'esame.
    private func normalized(_ exam: Exam) -> Exam {
        var exam = exam
        exam.date = noon(of: exam.date)
        if let startTime = exam.startTime, !(0..<24 * 60).contains(startTime) {
            exam.startTime = nil
        }
        for index in exam.tasks.indices {
            let dueDate = noon(of: exam.tasks[index].dueDate)
            exam.tasks[index].dueDate = exam.isScheduled ? min(dueDate, exam.date) : dueDate
            // Un task con checklist è fatto quando lo sono tutte le voci.
            let subtasks = exam.tasks[index].subtasks
            if !subtasks.isEmpty {
                exam.tasks[index].isDone = subtasks.allSatisfy(\.isDone)
            }
        }
        return exam
    }

    private func noon(of date: Date) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private func load() {
        let fileManager = FileManager.default
        if let data = try? Data(contentsOf: deletionsURL),
           let saved = try? Self.makeDecoder().decode([String: Date].self, from: data) {
            deletions = saved
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            exams = try Self.makeDecoder().decode([Exam].self, from: data).map(normalized)
            // Dati salvati prima dei colori assegnati: li completa e li salva una volta.
            if assignMissingColors() {
                save()
            }
        } catch let error as DecodingError {
            let corruptURL = fileURL.deletingLastPathComponent().appendingPathComponent("exams.corrupt.json")
            try? fileManager.removeItem(at: corruptURL)
            try? fileManager.moveItem(at: fileURL, to: corruptURL)
            NSLog("ExamsTrack: dati illeggibili spostati in exams.corrupt.json (%@)", String(describing: error))
            exams = []
            lastError = .corruptedData
        } catch {
            NSLog("ExamsTrack: lettura dei dati fallita (%@)", String(describing: error))
            isReadBlocked = true
            lastError = .readFailed
        }
    }

    private func save() {
        guard !isReadBlocked else {
            lastError = .readFailed
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Prima le eliminazioni: se l'app si chiudesse a metà, un esame eliminato non ricomparirebbe.
            try Self.makeEncoder().encode(deletions).write(to: deletionsURL, options: .atomic)
            let data = try Self.makeEncoder().encode(exams)
            try data.write(to: fileURL, options: .atomic)
            onSave?()
        } catch {
            NSLog("ExamsTrack: salvataggio fallito (%@)", String(describing: error))
            lastError = .saveFailed
        }
    }

    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
