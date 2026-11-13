import Foundation

/// Un task da mostrare nel widget grande.
public struct TaskPreview: Equatable, Sendable {
    public var title: String
    public var dueDate: Date
    public var isOverdue: Bool
    /// Vero per un task appena spuntato dal widget, mostrato barrato per qualche secondo.
    public var isDone: Bool
    /// Esame a cui appartiene: la lista "Da fare" mescola tutti gli esami.
    public var examName: String
    /// Indice in `Palette.examColors`.
    public var colorIndex: Int
    /// Per spuntare il task dal widget; nil nei dati di esempio.
    public var examID: UUID?
    public var taskID: UUID?

    public init(title: String, dueDate: Date, isOverdue: Bool, examName: String = "", colorIndex: Int = 0,
                examID: UUID? = nil, taskID: UUID? = nil, isDone: Bool = false) {
        self.isDone = isDone
        self.examID = examID
        self.taskID = taskID
        self.title = title
        self.dueDate = dueDate
        self.isOverdue = isOverdue
        self.examName = examName
        self.colorIndex = colorIndex
    }
}

/// Un esame successivo da mostrare nel widget grande.
public struct ExamPreview: Equatable, Sendable {
    public var examID: UUID?
    public var name: String
    public var daysRemaining: Int
    public var colorIndex: Int
    public var examDate: Date
    public var progress: Double
    /// Senza task l'avanzamento non si mostra.
    public var hasTasks: Bool

    public init(
        name: String, daysRemaining: Int, colorIndex: Int,
        examDate: Date = .now, progress: Double = 0, hasTasks: Bool = false, examID: UUID? = nil
    ) {
        self.examID = examID
        self.name = name
        self.daysRemaining = daysRemaining
        self.colorIndex = colorIndex
        self.examDate = examDate
        self.progress = progress
        self.hasTasks = hasTasks
    }
}

/// Ciò che il widget mostra del prossimo esame.
public struct NextExamSummary: Equatable, Sendable {
    /// Per aprire l'esame toccando il widget.
    public var examID: UUID?
    public var name: String
    public var daysRemaining: Int
    public var progress: Double
    public var progressPercent: Int
    /// Senza task l'avanzamento non ha senso e non va mostrato.
    public var hasTasks: Bool
    public var examDate: Date
    public var degree: Degree
    public var completedTasks: Int
    public var totalTasks: Int
    /// Indice in `Palette.examColors`.
    public var colorIndex: Int
    /// Primo task non fatto in ordine di scadenza su tutti gli esami da sostenere, anche se in ritardo.
    public var nextTaskTitle: String?
    public var nextTaskDueDate: Date?
    public var nextTaskExamName: String?
    /// Fino a 6 task non fatti di tutti gli esami da sostenere, per scadenza (anche in ritardo),
    /// più quelli appena spuntati dal widget, al loro posto.
    public var upcomingTasks: [TaskPreview]
    /// Esami programmati dopo il prossimo, fino a `followingExamLimit`: il widget ne mostra quanti ci stanno.
    public var followingExams: [ExamPreview]

    public init(
        name: String,
        daysRemaining: Int,
        progress: Double,
        progressPercent: Int,
        hasTasks: Bool = true,
        examDate: Date = .now,
        degree: Degree = .triennale,
        completedTasks: Int = 0,
        totalTasks: Int = 0,
        colorIndex: Int = 0,
        nextTaskTitle: String? = nil,
        nextTaskDueDate: Date? = nil,
        nextTaskExamName: String? = nil,
        upcomingTasks: [TaskPreview] = [],
        followingExams: [ExamPreview] = [],
        examID: UUID? = nil
    ) {
        self.examID = examID
        self.name = name
        self.daysRemaining = daysRemaining
        self.progress = progress
        self.progressPercent = progressPercent
        self.hasTasks = hasTasks
        self.examDate = examDate
        self.degree = degree
        self.completedTasks = completedTasks
        self.totalTasks = totalTasks
        self.colorIndex = colorIndex
        self.nextTaskTitle = nextTaskTitle
        self.nextTaskDueDate = nextTaskDueDate
        self.nextTaskExamName = nextTaskExamName
        self.upcomingTasks = upcomingTasks
        self.followingExams = followingExams
    }

    public static let followingExamLimit = 12

    /// `recentlyCompleted`: task già fatti da mostrare ancora, barrati (vedi `RecentlyCompleted`).
    /// `focusedExamID`: esame scelto nella configurazione del widget. Se è ancora da sostenere e programmato,
    /// il widget mostra quello, altrimenti il prossimo esame.
    /// `tasksFromAllExams`: i task di tutti gli esami da sostenere, oppure solo di quello mostrato.
    public static func make(
        from exams: [Exam], today: Date, focusedExamID: UUID? = nil, tasksFromAllExams: Bool = true,
        recentlyCompleted: Set<UUID> = [], calendar: Calendar = .current
    ) -> NextExamSummary? {
        let active = exams.active(today: today, calendar: calendar)
        let focused = focusedExamID.flatMap { id in active.first { $0.id == id && $0.isScheduled } }
        guard let exam = focused ?? exams.nextExam(today: today, calendar: calendar) else { return nil }
        let taskSource: [Exam] = tasksFromAllExams ? active : [exam]
        let open = taskSource
            .flatMap { other in
                other.tasks.filter { !$0.isDone || recentlyCompleted.contains($0.id) }.map { (exam: other, task: $0) }
            }
            .sorted { ($0.task.dueDate, $0.exam.name, $0.task.title) < ($1.task.dueDate, $1.exam.name, $1.task.title) }
        let nextTask = open.first
        return NextExamSummary(
            name: exam.name,
            daysRemaining: exam.daysRemaining(today: today, calendar: calendar),
            progress: exam.progress,
            progressPercent: exam.progressPercent,
            hasTasks: !exam.tasks.isEmpty,
            examDate: exam.date,
            degree: exam.degree,
            completedTasks: exam.completedTaskCount,
            totalTasks: exam.tasks.count,
            colorIndex: exam.colorIndex ?? 0,
            nextTaskTitle: nextTask?.task.title,
            nextTaskDueDate: nextTask?.task.dueDate,
            nextTaskExamName: nextTask?.exam.name,
            upcomingTasks: open.prefix(6).map { item in
                TaskPreview(title: item.task.title, dueDate: item.task.dueDate,
                            isOverdue: item.task.isOverdue(today: today, calendar: calendar),
                            examName: item.exam.name, colorIndex: item.exam.colorIndex ?? 0,
                            examID: item.exam.id, taskID: item.task.id, isDone: item.task.isDone)
            },
            followingExams: exams.active(today: today, calendar: calendar)
                .filter { $0.isScheduled && $0.id != exam.id }
                .prefix(followingExamLimit)
                .map { other in
                    ExamPreview(name: other.name,
                                daysRemaining: other.daysRemaining(today: today, calendar: calendar),
                                colorIndex: other.colorIndex ?? 0,
                                examDate: other.date,
                                progress: other.progress,
                                hasTasks: !other.tasks.isEmpty,
                                examID: other.id)
                },
            examID: exam.id
        )
    }
}

/// Inizio del giorno successivo a `date`, quando il widget deve aggiornare il countdown.
public func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: startOfDay)!
}
