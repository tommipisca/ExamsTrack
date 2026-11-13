#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity del giorno dell'esame: countdown all'orario di inizio sulla schermata di blocco
/// e nella Dynamic Island. Condivisa tra l'app, che la avvia, e il widget, che la disegna.
public struct ExamActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Inizio dell'esame: può cambiare se si modifica l'orario.
        public var start: Date

        public init(start: Date) {
            self.start = start
        }
    }

    public var examID: UUID
    public var examName: String
    /// Indice in `Palette.examColors`.
    public var colorIndex: Int

    public init(examID: UUID, examName: String, colorIndex: Int) {
        self.examID = examID
        self.examName = examName
        self.colorIndex = colorIndex
    }
}

/// Live Activity di una sessione di studio: timer fino a `end` per un esame (e un task).
public struct StudySessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var end: Date

        public init(end: Date) {
            self.end = end
        }
    }

    public var examID: UUID
    public var examName: String
    public var colorIndex: Int
    public var taskID: UUID?
    public var taskTitle: String?
    public var start: Date

    public init(examID: UUID, examName: String, colorIndex: Int, taskID: UUID? = nil, taskTitle: String?, start: Date) {
        self.examID = examID
        self.taskID = taskID
        self.examName = examName
        self.colorIndex = colorIndex
        self.taskTitle = taskTitle
        self.start = start
    }
}
#endif

import Foundation

/// Sessione di studio a tempo (tipo Pomodoro).
public enum StudySession {
    /// Durate proposte nei menu, in minuti; con "Altra durata…" se ne sceglie una qualsiasi in `range`.
    public static let durations = [25, 50]
    public static let range = 5...180
    /// Ultima durata scelta, nelle preferenze condivise: la usano anche Siri e il controllo.
    public static let lastDurationKey = "studySessionLastMinutes"

    /// Richiesta di avviare una sessione lasciata dal controllo del Centro di Controllo, che apre l'app:
    /// l'app la trova al ritorno in primo piano.
    public static let pendingRequestKey = "studySessionPendingRequest"
    /// Oltre questo tempo la richiesta è vecchia (l'app non si è aperta) e si ignora.
    public static let pendingRequestLifetime: TimeInterval = 2 * 60

    public static func requestStart(in defaults: UserDefaults, at date: Date = .now) {
        defaults.set(date.timeIntervalSince1970, forKey: pendingRequestKey)
    }

    /// Vero se c'è una richiesta recente; in ogni caso la consuma.
    public static func takePendingRequest(from defaults: UserDefaults, now: Date = .now) -> Bool {
        let requested = defaults.double(forKey: pendingRequestKey)
        defaults.removeObject(forKey: pendingRequestKey)
        guard requested > 0 else { return false }
        let age = now.timeIntervalSince1970 - requested
        return age >= 0 && age < pendingRequestLifetime
    }

    /// Ultima durata usata (25 la prima volta), sempre dentro `range`.
    public static func lastDuration(in defaults: UserDefaults) -> Int {
        let saved = defaults.integer(forKey: lastDurationKey)
        return saved == 0 ? durations[0] : min(max(saved, range.lowerBound), range.upperBound)
    }

    /// Durate da proporre in un menu: quelle fisse più l'ultima usata, se diversa.
    public static func menuDurations(last: Int) -> [Int] {
        durations.contains(last) ? durations : (durations + [last]).sorted()
    }
    /// Identificatore della notifica di fine sessione: la pianificazione dei promemoria non la tocca.
    public static let notificationID = "study-session-end"

    /// Notifica di fine sessione con i pulsanti: con "Segna fatto" se la sessione era su un task.
    public enum EndNotification {
        public static let categoryWithTask = "study-session-end.task"
        public static let category = "study-session-end.exam"
        public static let markDoneAction = "study-session.done"
        public static let moreTimeAction = "study-session.more"
        public static let pauseAction = "study-session.pause"
        /// Minuti di "Altri … minuti".
        public static let extraMinutes = 10

        public static let examIDKey = "examID"
        public static let taskIDKey = "taskID"
    }

    /// Su cosa studiare se non si sceglie: il primo task da fare oggi (o in ritardo) di tutti gli esami,
    /// altrimenti il prossimo esame senza task.
    public static func suggestion(exams: [Exam], today: Date, calendar: Calendar = .current)
        -> (examID: UUID, examName: String, colorIndex: Int, taskID: UUID?, taskTitle: String?)? {
        if let task = TodaySummary.make(from: exams, today: today, calendar: calendar).nextTask, let examID = task.examID {
            return (examID, task.examName, task.colorIndex, task.taskID, task.title)
        }
        guard let next = exams.nextExam(today: today, calendar: calendar) else { return nil }
        return (next.id, next.name, next.colorIndex ?? 0, nil, nil)
    }
}

/// Quando mostrare la Live Activity di un esame.
public enum ExamActivityPlan {
    /// iOS chiude una Live Activity dopo 8 ore: la si avvia solo da quel momento prima dell'inizio.
    public static let leadTime: TimeInterval = 8 * 60 * 60
    /// Dopo l'inizio resta ancora un po' ("in bocca al lupo"), poi l'app la chiude.
    public static let lingerAfterStart: TimeInterval = 30 * 60

    /// L'esame che merita la Live Activity adesso: da sostenere, con orario, che inizia entro `leadTime`
    /// (o è iniziato da meno di `lingerAfterStart`). Se sono più d'uno, il primo che inizia.
    public static func exam(in exams: [Exam], now: Date, calendar: Calendar = .current) -> (exam: Exam, start: Date)? {
        exams.active(today: now, calendar: calendar)
            .compactMap { exam in exam.startDate(calendar: calendar).map { (exam: exam, start: $0) } }
            .filter { $0.exam.isScheduled && $0.start - leadTime <= now && now < $0.start + lingerAfterStart }
            .min { $0.start < $1.start }
    }
}
