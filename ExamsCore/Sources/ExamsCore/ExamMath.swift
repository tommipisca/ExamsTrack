import Foundation

public extension Exam {
    /// Giorni di calendario da oggi alla data dell'esame (0 = oggi, negativo = passato).
    func daysRemaining(today: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Da sostenere: esame non ancora programmato, oppure con data oggi o futura.
    func isActive(today: Date, calendar: Calendar = .current) -> Bool {
        !isScheduled || daysRemaining(today: today, calendar: calendar) >= 0
    }

    var completedTaskCount: Int {
        tasks.filter(\.isDone).count
    }

    /// Avanzamento (0...1): ogni task vale uno, quelli con sotto-task in parte fatti valgono la loro frazione;
    /// 0 se non ci sono task.
    var progress: Double {
        tasks.isEmpty ? 0 : tasks.reduce(0) { $0 + $1.completion } / Double(tasks.count)
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    var sortedTasks: [StudyTask] {
        tasks.sorted { ($0.dueDate, $0.title) < ($1.dueDate, $1.title) }
    }

    var outcomeLabel: String {
        switch passed {
        case nil:
            return "Esito da inserire"
        case false?:
            return "Non superato"
        case true? where isMasterThesis:
            guard let points = thesisPointsLabel, let value = thesisPoints else { return "Superato" }
            return "Superato, \(points) \(abs(value) == 1 ? "punto" : "punti")"
        case true?:
            guard let grade else { return "Superato" }
            return honors && grade == 30 ? "Superato 30L" : "Superato \(grade)"
        }
    }
}

public extension StudyTask {
    func isOverdue(today: Date, calendar: Calendar = .current) -> Bool {
        !isDone && calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: today)
    }
}

public extension Array where Element == Exam {
    /// Esami di oggi o futuri, dal più vicino; a parità di data, per nome.
    /// Esami da sostenere: prima i programmati per data (poi nome), in fondo i non programmati in ordine alfabetico.
    func active(today: Date, calendar: Calendar = .current) -> [Exam] {
        let pending = filter { $0.isActive(today: today, calendar: calendar) }
        let scheduled = pending.filter(\.isScheduled)
            .sorted { ($0.date, $0.name) < ($1.date, $1.name) }
        let unscheduled = pending.filter { !$0.isScheduled }
            .sorted { lhs, rhs in
                switch lhs.name.localizedStandardCompare(rhs.name) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: lhs.id.uuidString < rhs.id.uuidString
                }
            }
        return scheduled + unscheduled
    }

    /// Esami passati, dal più recente.
    func archived(today: Date, calendar: Calendar = .current) -> [Exam] {
        filter { !$0.isActive(today: today, calendar: calendar) }
            .sorted { $0.date > $1.date }
    }

    /// Carriera didattica: esami passati di un corso, dal più recente.
    func career(degree: Degree, today: Date, calendar: Calendar = .current) -> [Exam] {
        archived(today: today, calendar: calendar).filter { $0.degree == degree }
    }

    /// Prossimo esame con una data: quelli non programmati non hanno countdown.
    func nextExam(today: Date, calendar: Calendar = .current) -> Exam? {
        active(today: today, calendar: calendar).first(where: \.isScheduled)
    }
}
