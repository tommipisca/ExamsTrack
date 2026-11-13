import Foundation

// MARK: Ordinamento della carriera

/// Ordine degli esami sostenuti nella scheda Carriera.
public enum CareerSort: String, CaseIterable, Identifiable, Sendable {
    case date
    case grade
    case cfu

    public var id: Self { self }

    public var label: String {
        switch self {
        case .date: "Data"
        case .grade: "Voto"
        case .cfu: "CFU"
        }
    }
}

public extension Array where Element == Exam {
    func sortedForCareer(by sort: CareerSort) -> [Exam] {
        switch sort {
        case .date:
            return sorted { ($0.date, $1.name) > ($1.date, $0.name) }
        case .grade:
            // 30 e lode sopra il 30; senza voto in fondo; a parità, il più recente.
            func key(_ exam: Exam) -> Int {
                guard let grade = exam.countedGrade else { return -1 }
                return exam.honors ? grade + 1 : grade
            }
            return sorted { (key($0), $0.date) > (key($1), $1.date) }
        case .cfu:
            return sorted { ($0.cfu, $1.name) > ($1.cfu, $0.name) }
        }
    }
}

// MARK: Dati del form d'esame

/// I campi modificabili dal form di un esame.
public struct ExamDetails: Equatable, Sendable {
    public var name: String
    public var date: Date
    public var degree: Degree
    public var cfu: Int
    public var isFinalTest: Bool
    public var isScheduled: Bool
    public var startTime: Int?

    public init(name: String, date: Date, degree: Degree, cfu: Int, isFinalTest: Bool, isScheduled: Bool, startTime: Int?) {
        self.name = name
        self.date = date
        self.degree = degree
        self.cfu = cfu
        self.isFinalTest = isFinalTest
        self.isScheduled = isScheduled
        self.startTime = startTime
    }

    public init(_ exam: Exam) {
        self.init(name: exam.name, date: exam.date, degree: exam.degree, cfu: exam.cfu,
                  isFinalTest: exam.isFinalTest, isScheduled: exam.isScheduled, startTime: exam.startTime)
    }

    /// Prende dal form solo i campi cambiati rispetto all'apertura; gli altri dalla versione più recente,
    /// così non si annullano le modifiche arrivate da un altro dispositivo mentre il form era aperto.
    public static func merging(original: ExamDetails, edited: ExamDetails, latest: ExamDetails) -> ExamDetails {
        func pick<T: Equatable>(_ field: KeyPath<ExamDetails, T>) -> T {
            edited[keyPath: field] != original[keyPath: field] ? edited[keyPath: field] : latest[keyPath: field]
        }
        return ExamDetails(
            name: pick(\.name), date: pick(\.date), degree: pick(\.degree), cfu: pick(\.cfu),
            isFinalTest: pick(\.isFinalTest), isScheduled: pick(\.isScheduled), startTime: pick(\.startTime)
        )
    }
}

public extension Exam {
    /// CFU tipici della tesi magistrale, proposti quando si segna un esame come tesi.
    static let thesisCFU = 20
}

// MARK: Piano di studio

public enum StudyPlanner {
    public static let reviewTitle = "Ripasso generale"

    /// Un task per argomento, distribuiti uniformemente da `start` fino a prima dei giorni di ripasso,
    /// più un "Ripasso generale" il giorno prima di `end`. Con poco tempo, tutto si concentra su `start`.
    public static func plan(
        topics: [String], start: Date, end: Date, reviewDays: Int, calendar: Calendar = .current
    ) -> [StudyTask] {
        let titles = topics
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        func day(_ offset: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: base) ?? base
        }

        // Giorni di studio: da start all'ultimo giorno prima del ripasso (e dell'esame).
        let lastStudyDay = calendar.date(byAdding: .day, value: -(max(reviewDays, 0) + 1), to: endDay) ?? endDay
        let studyDays = max(1, (calendar.dateComponents([.day], from: startDay, to: lastStudyDay).day ?? 0) + 1)

        var tasks = titles.enumerated().map { index, title in
            let position = Double((index + 1) * studyDays) / Double(titles.count)
            return StudyTask(title: title, dueDate: day(max(0, Int(position.rounded(.up)) - 1)))
        }
        if reviewDays > 0 {
            let dayBeforeEnd = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
            tasks.append(StudyTask(title: reviewTitle, dueDate: day(max(0, dayBeforeEnd - 1))))
        }
        return tasks
    }
}

// MARK: Ripianificazione dei task in ritardo

public extension StudyPlanner {
    /// I task di `exam` con quelli in ritardo ridistribuiti in modo uniforme da oggi al giorno prima
    /// dell'esame (o sui prossimi 7 giorni se l'esame non ha data). Gli altri task restano invariati.
    static func rescheduleOverdue(_ exam: Exam, today: Date, calendar: Calendar = .current) -> [StudyTask] {
        let overdue = exam.sortedTasks.filter { $0.isOverdue(today: today, calendar: calendar) }
        guard !overdue.isEmpty else { return exam.tasks }

        let startDay = calendar.startOfDay(for: today)
        let lastDay: Date
        if exam.isScheduled {
            let dayBeforeExam = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: exam.date)) ?? startDay
            lastDay = max(dayBeforeExam, startDay)
        } else {
            lastDay = calendar.date(byAdding: .day, value: 6, to: startDay) ?? startDay
        }
        let days = (calendar.dateComponents([.day], from: startDay, to: lastDay).day ?? 0) + 1

        var newDates: [UUID: Date] = [:]
        for (index, task) in overdue.enumerated() {
            let offset = index * days / overdue.count
            let day = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            newDates[task.id] = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        return exam.tasks.map { task in
            var task = task
            if let date = newDates[task.id] { task.dueDate = date }
            return task
        }
    }
}

public extension Exam {
    /// Task non fatti con scadenza passata.
    func overdueCount(today: Date, calendar: Calendar = .current) -> Int {
        tasks.filter { $0.isOverdue(today: today, calendar: calendar) }.count
    }
}

// MARK: Andamento della media

/// La media pesata subito dopo un esame superato.
public struct TrendPoint: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var examName: String
    public var grade: Int
    public var average: Double
}

public extension Array where Element == Exam {
    /// Media pesata cumulativa dopo ogni esame superato del corso, in ordine di data.
    func averageTrend(degree: Degree) -> [TrendPoint] {
        let graded = filter { $0.degree == degree && $0.countedGrade != nil }
            .sorted { ($0.date, $0.name) < ($1.date, $1.name) }
        var points = 0
        var credits = 0
        return graded.map { exam in
            let grade = exam.countedGrade ?? 0
            points += grade * exam.cfu
            credits += exam.cfu
            return TrendPoint(id: exam.id, date: exam.date, examName: exam.name, grade: grade,
                              average: Double(points) / Double(Swift.max(credits, 1)))
        }
    }
}
