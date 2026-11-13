import Foundation

/// Un task con l'esame a cui appartiene, per le viste che mescolano più esami.
public struct AgendaItem: Identifiable, Equatable, Sendable {
    public var examID: UUID
    public var examName: String
    /// Indice in `Palette.examColors`.
    public var colorIndex: Int
    public var task: StudyTask

    public var id: UUID { task.id }
}

/// Uno dei prossimi giorni con i suoi task (anche vuoto: su iPad è un punto di arrivo
/// per spostarci un task trascinandolo).
public struct AgendaDay: Identifiable, Equatable, Sendable {
    /// Mezzogiorno del giorno, come le scadenze dei task.
    public var date: Date
    /// Prima quelli da fare, poi quelli già spuntati.
    public var items: [AgendaItem]

    public var id: Date { date }
}

/// Cosa c'è da fare oggi e nei prossimi giorni, su tutti gli esami ancora da sostenere.
public struct Agenda: Equatable, Sendable {
    public static let dayCount = 7

    /// Task non fatti con scadenza passata.
    public var overdue: [AgendaItem]
    /// Task in scadenza oggi, anche già fatti (in fondo).
    public var dueToday: [AgendaItem]
    /// I prossimi `dayCount` giorni da domani, anche vuoti; i task già fatti restano visibili.
    public var days: [AgendaDay] = []
    /// Task non fatti dopo quei giorni.
    public var later: [AgendaItem] = []

    public var isEmpty: Bool { overdue.isEmpty && dueToday.isEmpty }
}

public extension Array where Element == Exam {
    func agenda(today: Date, calendar: Calendar = .current) -> Agenda {
        let startOfToday = calendar.startOfDay(for: today)
        let items = active(today: today, calendar: calendar).flatMap { exam in
            exam.tasks.map { AgendaItem(examID: exam.id, examName: exam.name, colorIndex: exam.colorIndex ?? 0, task: $0) }
        }
        let ordered = items.sorted {
            ($0.task.dueDate, $0.examName, $0.task.title) < ($1.task.dueDate, $1.examName, $1.task.title)
        }

        /// Task di un giorno: prima quelli da fare, poi quelli già spuntati, mantenendo l'ordine.
        func on(_ day: Date) -> [AgendaItem] {
            let ofDay = ordered.filter { calendar.startOfDay(for: $0.task.dueDate) == day }
            return ofDay.filter { !$0.task.isDone } + ofDay.filter(\.task.isDone)
        }

        let days: [Date] = (1...Agenda.dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startOfToday)
        }
        let lastDay = days.last ?? startOfToday
        return Agenda(
            overdue: ordered.filter { $0.task.isOverdue(today: today, calendar: calendar) },
            dueToday: on(startOfToday),
            days: days.map { day in
                AgendaDay(date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day, items: on(day))
            },
            later: ordered.filter { !$0.task.isDone && calendar.startOfDay(for: $0.task.dueDate) > lastDay }
        )
    }
}
