import Foundation

/// Quanto prima di un esame arriva un promemoria.
public enum ReminderOffset: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneMonth, twoWeeks, oneWeek, threeDays, twoDays, oneDay, sameDay

    public var id: Self { self }

    public var label: String {
        switch self {
        case .oneMonth: "1 mese prima"
        case .twoWeeks: "2 settimane prima"
        case .oneWeek: "1 settimana prima"
        case .threeDays: "3 giorni prima"
        case .twoDays: "2 giorni prima"
        case .oneDay: "1 giorno prima"
        case .sameDay: "Il giorno stesso"
        }
    }

    /// Spostamento all'indietro rispetto al giorno dell'esame.
    var components: DateComponents {
        switch self {
        case .oneMonth: DateComponents(month: -1)
        case .twoWeeks: DateComponents(day: -14)
        case .oneWeek: DateComponents(day: -7)
        case .threeDays: DateComponents(day: -3)
        case .twoDays: DateComponents(day: -2)
        case .oneDay: DateComponents(day: -1)
        case .sameDay: DateComponents(day: 0)
        }
    }
}

/// Preferenze delle notifiche, uguali per tutti gli esami.
public struct NotificationSettings: Codable, Equatable, Sendable {
    public var examReminders: Set<ReminderOffset>
    /// Ogni giorno con task in scadenza, un riepilogo di quei task.
    public var dailyTaskSummary: Bool
    public var hour: Int
    public var minute: Int

    public init(examReminders: Set<ReminderOffset>, dailyTaskSummary: Bool, hour: Int, minute: Int) {
        self.examReminders = examReminders
        self.dailyTaskSummary = dailyTaskSummary
        self.hour = hour
        self.minute = minute
    }

    public static let `default` = NotificationSettings(
        examReminders: [.oneWeek, .oneDay, .sameDay], dailyTaskSummary: true, hour: 9, minute: 0
    )

    public var isAnyEnabled: Bool { !examReminders.isEmpty || dailyTaskSummary }
}

/// Una notifica locale da pianificare.
public struct PlannedNotification: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var fireDate: Date
}

public enum NotificationPlanner {
    /// iOS tiene al massimo 64 notifiche locali in attesa per app.
    public static let maximumPending = 64

    /// Notifiche future per esami e task, dalle più vicine, entro il limite di iOS.
    public static func plan(
        exams: [Exam], settings: NotificationSettings, now: Date, calendar: Calendar = .current,
        appExpiration: Date? = nil,
        warnedExpiration: Date? = nil
    ) -> [PlannedNotification] {
        func at(_ day: Date) -> Date? {
            calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day)
        }

        let active = exams.active(today: now, calendar: calendar)
        var planned: [PlannedNotification] = []

        for exam in active where exam.isScheduled {
            let examDay = calendar.startOfDay(for: exam.date)
            for offset in settings.examReminders {
                guard let day = calendar.date(byAdding: offset.components, to: examDay),
                      var fireDate = at(day) else { continue }
                // Il giorno dell'esame, almeno un'ora prima dell'inizio se l'orario è indicato.
                if offset == .sameDay, let start = exam.startDate(calendar: calendar) {
                    fireDate = min(fireDate, start.addingTimeInterval(-3600))
                }
                guard fireDate > now else { continue }
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: examDay).day ?? 0
                planned.append(PlannedNotification(
                    id: "exam-\(exam.id.uuidString)-\(offset.rawValue)",
                    title: exam.name,
                    body: examBody(days: days),
                    fireDate: fireDate
                ))
            }
        }

        if settings.dailyTaskSummary {
            let open = active.flatMap { exam in
                exam.tasks.filter { !$0.isDone }.map { (task: $0, examName: exam.name) }
            }
            let byDay = Dictionary(grouping: open) { calendar.startOfDay(for: $0.task.dueDate) }
            for (day, items) in byDay {
                guard let fireDate = at(day), fireDate > now else { continue }
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                let sorted = items.sorted { ($0.task.title, $0.examName) < ($1.task.title, $1.examName) }
                planned.append(PlannedNotification(
                    id: "tasks-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
                    title: "\(items.count) task in scadenza oggi",
                    body: sorted.map { "\($0.task.title) (\($0.examName))" }.joined(separator: ", "),
                    fireDate: fireDate
                ))
            }
        }

        if let appExpiration,
           let warning = expirationWarning(appExpiration, now: now, calendar: calendar, at: at,
                                           alreadyWarned: warnedExpiration == appExpiration) {
            planned.append(warning)
        }

        return Array(planned.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(maximumPending))
    }

    /// Avviso di scadenza dell'app: il giorno prima all'orario scelto, oppure subito se quell'ora è passata.
    /// Vale anche con i promemoria spenti, perché un'app scaduta non si apre più.
    private static func expirationWarning(
        _ expiration: Date, now: Date, calendar: Calendar, at: (Date) -> Date?, alreadyWarned: Bool
    ) -> PlannedNotification? {
        let soon = now.addingTimeInterval(60)
        guard expiration > soon,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: expiration)),
              let preferred = at(dayBefore) else { return nil }
        // L'avviso immediato (ora del giorno prima già passata) arriva una volta sola per profilo,
        // non a ogni nuova pianificazione.
        if preferred <= now, alreadyWarned { return nil }
        let fireDate = preferred > now ? preferred : soon
        let isSameDay = calendar.isDate(fireDate, inSameDayAs: expiration)
        return PlannedNotification(
            id: "app-expiration",
            title: isSameDay ? "ExamsTrack scade oggi" : "ExamsTrack scade domani",
            body: "Reinstallala con xtool dev dal computer per continuare a usarla: i tuoi dati restano.",
            fireDate: fireDate
        )
    }

    private static func examBody(days: Int) -> String {
        switch days {
        case 0: "Esame oggi: in bocca al lupo!"
        case 1: "Esame domani"
        default: "Esame tra \(days) giorni"
        }
    }
}
