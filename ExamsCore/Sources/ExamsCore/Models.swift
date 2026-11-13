import Foundation

/// Una voce della checklist di un task (es. "Teoria", "Esercizi" dentro "Capitolo 4").
public struct Subtask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public struct StudyTask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var dueDate: Date
    /// Con sotto-task, vero solo quando sono tutti fatti (lo garantisce lo store).
    public var isDone: Bool
    public var subtasks: [Subtask]

    public init(id: UUID = UUID(), title: String, dueDate: Date, isDone: Bool = false, subtasks: [Subtask] = []) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isDone = isDone
        self.subtasks = subtasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        // Assenti nei dati salvati prima dei sotto-task.
        subtasks = try container.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
    }
}

public extension StudyTask {
    /// Quanto è fatto il task (0...1): 1 se fatto, altrimenti la frazione di sotto-task fatti.
    var completion: Double {
        if isDone { return 1 }
        guard !subtasks.isEmpty else { return 0 }
        return Double(subtasks.filter(\.isDone).count) / Double(subtasks.count)
    }

    /// "2/3"; nil senza sotto-task.
    var subtaskLabel: String? {
        subtasks.isEmpty ? nil : "\(subtasks.filter(\.isDone).count)/\(subtasks.count)"
    }
}

/// Corso di laurea a cui appartiene un esame.
public enum Degree: String, Codable, CaseIterable, Identifiable, Sendable {
    case triennale
    case magistrale

    public var id: Self { self }

    public var label: String {
        switch self {
        case .triennale: "Triennale"
        case .magistrale: "Magistrale"
        }
    }
}

public struct Exam: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Conta solo il giorno; l'orario è ignorato nei calcoli.
    public var date: Date
    public var tasks: [StudyTask]
    /// nil = esito non ancora inserito.
    public var passed: Bool?
    /// 18...30, significativo solo se `passed == true`.
    public var grade: Int?
    /// Lode, ammessa solo con `grade == 30`.
    public var honors: Bool
    public var degree: Degree
    /// Crediti formativi, peso dell'esame nella media.
    public var cfu: Int
    /// Triennale: corso di tipo "prova finale", con voto, che dà i punti bonus del voto di laurea.
    /// Magistrale: la tesi, che non ha voto ma un punteggio (`thesisPoints`).
    public var isFinalTest: Bool
    /// Punti assegnati alla tesi magistrale dalla commissione, da −1 a 8.
    public var thesisPoints: Double?
    /// Falso finché l'esame non ha una data: `date` va ignorata e non c'è countdown.
    public var isScheduled: Bool
    /// Orario di inizio in minuti dalla mezzanotte; nil se l'esame ha solo la data.
    /// È separato da `date`, che resta a mezzogiorno per i calcoli in giorni.
    public var startTime: Int?
    /// Indice in `Palette.examColors`; nil finché lo store non lo assegna.
    public var colorIndex: Int?
    /// Ultima modifica, per unire i dati tra dispositivi; nil per dati salvati prima della sincronizzazione.
    public var modifiedAt: Date?
    /// Voto ipotetico per il simulatore "e se", per esami ancora senza voto (18...30).
    public var simulatedGrade: Int?
    /// Ultima modifica della simulazione: separata da `modifiedAt`, così un voto ipotetico
    /// non può prevalere in sincronizzazione su un voto vero registrato su un altro dispositivo.
    public var simulationModifiedAt: Date?
    /// Note libere (programma, materiale, modalità d'esame...).
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        tasks: [StudyTask] = [],
        passed: Bool? = nil,
        grade: Int? = nil,
        honors: Bool = false,
        degree: Degree = .triennale,
        cfu: Int = Exam.defaultCFU,
        isFinalTest: Bool = false,
        thesisPoints: Double? = nil,
        isScheduled: Bool = true,
        startTime: Int? = nil,
        colorIndex: Int? = nil,
        modifiedAt: Date? = nil,
        simulatedGrade: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.tasks = tasks
        self.passed = passed
        self.grade = grade
        self.honors = honors
        self.degree = degree
        self.cfu = cfu
        self.isFinalTest = isFinalTest
        self.thesisPoints = thesisPoints
        self.isScheduled = isScheduled
        self.startTime = startTime
        self.colorIndex = colorIndex
        self.modifiedAt = modifiedAt
        self.simulatedGrade = simulatedGrade
        self.notes = ""
    }

    public static let defaultCFU = 6

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        tasks = try container.decode([StudyTask].self, forKey: .tasks)
        passed = try container.decodeIfPresent(Bool.self, forKey: .passed)
        grade = try container.decodeIfPresent(Int.self, forKey: .grade)
        honors = try container.decode(Bool.self, forKey: .honors)
        // Assente nei dati salvati prima dell'introduzione del tag.
        degree = try container.decodeIfPresent(Degree.self, forKey: .degree) ?? .triennale
        cfu = try container.decodeIfPresent(Int.self, forKey: .cfu) ?? Exam.defaultCFU
        isFinalTest = try container.decodeIfPresent(Bool.self, forKey: .isFinalTest) ?? false
        thesisPoints = try container.decodeIfPresent(Double.self, forKey: .thesisPoints)
        isScheduled = try container.decodeIfPresent(Bool.self, forKey: .isScheduled) ?? true
        startTime = try container.decodeIfPresent(Int.self, forKey: .startTime)
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        simulatedGrade = try container.decodeIfPresent(Int.self, forKey: .simulatedGrade)
        simulationModifiedAt = try container.decodeIfPresent(Date.self, forKey: .simulationModifiedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}
