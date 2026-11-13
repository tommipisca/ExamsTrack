import Foundation

public extension Exam {
    /// Posizione del segnaposto "Oggi" tra i task ordinati: prima del primo task che scade oggi o dopo.
    /// nil se l'esame è già passato.
    func todayMarkerIndex(today: Date, calendar: Calendar = .current) -> Int? {
        guard isActive(today: today, calendar: calendar) else { return nil }
        let startOfToday = calendar.startOfDay(for: today)
        return sortedTasks.firstIndex { calendar.startOfDay(for: $0.dueDate) >= startOfToday } ?? sortedTasks.count
    }
}

/// Quanto è vicino un esame, per scegliere il colore del countdown.
public enum Urgency: Equatable, Sendable {
    case calm
    case soon
    case urgent

    public init(days: Int) {
        switch days {
        case ...2: self = .urgent
        case ...7: self = .soon
        default: self = .calm
        }
    }
}
