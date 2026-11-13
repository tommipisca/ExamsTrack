import SwiftUI
import WidgetKit
import ExamsCore

struct NextExamEntry: TimelineEntry {
    let date: Date
    let summary: NextExamSummary?
    /// La giornata di studio (dell'esame scelto, o di tutti), per la schermata di blocco.
    var today = TodaySummary()
    /// Dati presenti ma non leggibili (es. iPhone non ancora sbloccato dopo il riavvio).
    var isUnavailable = false
}

/// Istanti della timeline: adesso, la scomparsa di ogni task spuntato da poco, la prossima mezzanotte.
/// Per ciascuno, i task ancora da mostrare barrati.
func widgetTimelineDates(now: Date) -> [(date: Date, recentlyCompleted: Set<UUID>)] {
    let recents = RecentlyCompleted(defaults: AppGroup.sharedDefaults).active(at: now)
    let midnight = nextMidnight(after: now)
    let dates = [now] + Set(recents.values).sorted().filter { $0 < midnight } + [midnight]
    return dates.map { date in (date, Set(recents.filter { $0.value > date }.keys)) }
}

/// Esami del corso visibile; nil se il file c'è ma non si legge.
func widgetExams() -> [Exam]? {
    ExamStore.readOnly(from: AppGroup.dataFileURL())?.visible(.saved)
}

struct NextExamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextExamEntry {
        NextExamEntry(
            date: .now,
            summary: NextExamSummary(
                name: "Analisi 1", daysRemaining: 12, progress: 0.58, progressPercent: 58,
                examDate: Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now,
                completedTasks: 7, totalTasks: 12, nextTaskTitle: "Ripasso capitolo 4",
                nextTaskDueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
                nextTaskExamName: "Analisi 1",
                upcomingTasks: [
                    TaskPreview(title: "Ripasso capitolo 4", dueDate: .now.addingTimeInterval(3 * 86_400), isOverdue: false,
                                examName: "Analisi 1"),
                    TaskPreview(title: "Esercizi di cinematica", dueDate: .now.addingTimeInterval(5 * 86_400), isOverdue: false,
                                examName: "Fisica", colorIndex: 1),
                    TaskPreview(title: "Esercizi sugli integrali", dueDate: .now.addingTimeInterval(6 * 86_400), isOverdue: false,
                                examName: "Analisi 1"),
                ],
                followingExams: [
                    ExamPreview(name: "Fisica", daysRemaining: 34, colorIndex: 1,
                                examDate: .now.addingTimeInterval(34 * 86_400), progress: 0.4, hasTasks: true),
                    ExamPreview(name: "Chimica", daysRemaining: 51, colorIndex: 2,
                                examDate: .now.addingTimeInterval(51 * 86_400)),
                ]
            ),
            today: TodaySummary(
                tasks: [TaskPreview(title: "Ripasso capitolo 4", dueDate: .now, isOverdue: false, examName: "Analisi 1")],
                doneToday: 1, totalToday: 3
            )
        )
    }

    func snapshot(for configuration: SelectExamIntent, in context: Context) async -> NextExamEntry {
        if context.isPreview { return placeholder(in: context) }
        let now = Date.now
        guard let exams = widgetExams() else { return NextExamEntry(date: now, summary: nil, isUnavailable: true) }
        let recents = Set(RecentlyCompleted(defaults: AppGroup.sharedDefaults).active(at: now).keys)
        return entry(at: now, exams: exams, configuration: configuration, recentlyCompleted: recents)
    }

    func timeline(for configuration: SelectExamIntent, in context: Context) async -> Timeline<NextExamEntry> {
        let now = Date.now
        guard let exams = widgetExams() else {
            // Riprova fra 15 minuti: di solito il telefono nel frattempo è stato sbloccato.
            return Timeline(entries: [NextExamEntry(date: now, summary: nil, isUnavailable: true)],
                            policy: .after(now.addingTimeInterval(15 * 60)))
        }
        let entries = widgetTimelineDates(now: now).map {
            entry(at: $0.date, exams: exams, configuration: configuration, recentlyCompleted: $0.recentlyCompleted)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(at date: Date, exams: [Exam], configuration: SelectExamIntent,
                       recentlyCompleted: Set<UUID>) -> NextExamEntry {
        let focused = configuration.exam.flatMap { UUID(uuidString: $0.id) }
        let allTasks = configuration.includeOtherExams
        let summary = NextExamSummary.make(from: exams, today: date, focusedExamID: focused,
                                           tasksFromAllExams: allTasks, recentlyCompleted: recentlyCompleted)
        // La giornata (schermata di blocco) segue la stessa scelta: tutti gli esami, o solo quello mostrato.
        let todayFocus = allTasks ? nil : summary?.examID
        return NextExamEntry(
            date: date, summary: summary,
            today: TodaySummary.make(from: exams, today: date, focusedExamID: todayFocus,
                                     recentlyCompleted: recentlyCompleted)
        )
    }
}

struct NextExamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextExamWidget", intent: SelectExamIntent.self, provider: NextExamProvider()) { entry in
            NextExamWidgetView(entry: entry)
                // Sulla schermata di blocco iOS ignora questo sfondo; in Home dà il tema scuro.
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName("Prossimo esame")
        .description("Giorni rimanenti, avanzamento e task da fare. Tieni premuto per scegliere un esame.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
