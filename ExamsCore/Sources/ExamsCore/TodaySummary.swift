import Foundation

/// La giornata di studio per i widget "Da fare oggi" e della schermata di blocco.
public struct TodaySummary: Equatable, Sendable {
    /// Prima i task in ritardo (con quelli appena spuntati, ancora barrati), poi quelli di oggi:
    /// da fare, poi già fatti.
    public var tasks: [TaskPreview]
    /// Task in scadenza oggi già fatti, e in tutto.
    public var doneToday: Int
    public var totalToday: Int
    /// Task non fatti con scadenza passata.
    public var overdueCount: Int

    public var progress: Double { totalToday == 0 ? 0 : Double(doneToday) / Double(totalToday) }
    /// Il primo task ancora da fare, in ritardo o di oggi.
    public var nextTask: TaskPreview? { tasks.first { !$0.isDone } }
    public var isEmpty: Bool { tasks.isEmpty }

    public init(tasks: [TaskPreview] = [], doneToday: Int = 0, totalToday: Int = 0, overdueCount: Int = 0) {
        self.tasks = tasks
        self.doneToday = doneToday
        self.totalToday = totalToday
        self.overdueCount = overdueCount
    }

    /// `focusedExamID`: come in `NextExamSummary.make`, limita la giornata a quell'esame se è da sostenere.
    public static func make(
        from exams: [Exam], today: Date, focusedExamID: UUID? = nil, recentlyCompleted: Set<UUID> = [],
        calendar: Calendar = .current
    ) -> TodaySummary {
        let startOfToday = calendar.startOfDay(for: today)
        let active = exams.active(today: today, calendar: calendar)
        let scope = focusedExamID.flatMap { id in active.first { $0.id == id }.map { [$0] } } ?? active
        let items = scope.flatMap { exam in exam.tasks.map { (exam: exam, task: $0) } }
            .sorted { ($0.task.dueDate, $0.exam.name, $0.task.title) < ($1.task.dueDate, $1.exam.name, $1.task.title) }

        let past = items.filter { calendar.startOfDay(for: $0.task.dueDate) < startOfToday }
        let overdue = past.filter { !$0.task.isDone || recentlyCompleted.contains($0.task.id) }
        let todays = items.filter { calendar.startOfDay(for: $0.task.dueDate) == startOfToday }
        let ordered = overdue + todays.filter { !$0.task.isDone } + todays.filter(\.task.isDone)

        return TodaySummary(
            tasks: ordered.map { item in
                TaskPreview(title: item.task.title, dueDate: item.task.dueDate,
                            isOverdue: item.task.isOverdue(today: today, calendar: calendar),
                            examName: item.exam.name, colorIndex: item.exam.colorIndex ?? 0,
                            examID: item.exam.id, taskID: item.task.id, isDone: item.task.isDone)
            },
            doneToday: todays.filter(\.task.isDone).count,
            totalToday: todays.count,
            overdueCount: past.filter { !$0.task.isDone }.count
        )
    }
}
