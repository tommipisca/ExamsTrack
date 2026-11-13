import Foundation

/// "Oggi" su iPad: a sinistra il prossimo esame e l'agenda di tutti gli esami,
/// a destra gli altri esami da sostenere.
public struct TodayBoard: Sendable {
    public var next: Exam?
    /// Task di tutti gli esami da sostenere: in ritardo, di oggi, dei prossimi giorni e più avanti.
    public var agenda: Agenda
    /// Gli altri esami da sostenere: prima i programmati per data, in fondo quelli da programmare.
    public var others: [Exam]

    public static func make(exams: [Exam], today: Date, calendar: Calendar = .current) -> TodayBoard {
        let next = exams.nextExam(today: today, calendar: calendar)
        return TodayBoard(
            next: next,
            agenda: exams.agenda(today: today, calendar: calendar),
            others: exams.active(today: today, calendar: calendar).filter { $0.id != next?.id }
        )
    }
}
