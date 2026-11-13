import Foundation

/// Countdown preciso fino all'orario di inizio di un esame.
public enum PreciseCountdown: Equatable, Sendable {
    /// Es. 11 "giorni" "e 20 ore", oppure 3 "ore" "e 20 minuti".
    case remaining(value: Int, unit: String, detail: String?)
    case lessThanAMinute
    case started
}

public extension Exam {
    /// Inizio dell'esame (giorno + orario), se l'orario è indicato.
    func startDate(calendar: Calendar = .current) -> Date? {
        guard let startTime else { return nil }
        return calendar.date(
            bySettingHour: startTime / 60, minute: startTime % 60, second: 0,
            of: calendar.startOfDay(for: date)
        )
    }

    /// "14:30", oppure nil se l'esame non ha un orario.
    var startTimeLabel: String? {
        guard let startTime else { return nil }
        return String(format: "%d:%02d", startTime / 60, startTime % 60)
    }

    /// Tempo reale che manca all'inizio; nil senza orario o per esami non programmati.
    func preciseCountdown(now: Date, calendar: Calendar = .current) -> PreciseCountdown? {
        guard isScheduled, let start = startDate(calendar: calendar) else { return nil }
        guard now < start else { return .started }

        let parts = calendar.dateComponents([.day, .hour, .minute], from: now, to: start)
        let days = parts.day ?? 0
        let hours = parts.hour ?? 0
        let minutes = parts.minute ?? 0

        if days > 0 {
            return .remaining(value: days, unit: days == 1 ? "giorno" : "giorni",
                              detail: hours > 0 ? "e \(hours) \(hours == 1 ? "ora" : "ore")" : nil)
        }
        if hours > 0 {
            return .remaining(value: hours, unit: hours == 1 ? "ora" : "ore",
                              detail: minutes > 0 ? "e \(minutes) \(minutes == 1 ? "minuto" : "minuti")" : nil)
        }
        if minutes > 0 {
            return .remaining(value: minutes, unit: minutes == 1 ? "minuto" : "minuti", detail: nil)
        }
        return .lessThanAMinute
    }
}
