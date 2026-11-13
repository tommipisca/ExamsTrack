import SwiftUI
import WidgetKit
import ExamsCore

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let today: TodaySummary
    var isUnavailable = false
}

struct TodayTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTasksEntry {
        TodayTasksEntry(date: .now, today: TodaySummary(
            tasks: [
                TaskPreview(title: "Ripasso capitolo 4", dueDate: .now, isOverdue: false, examName: "Analisi 1"),
                TaskPreview(title: "Esercizi di cinematica", dueDate: .now, isOverdue: false, examName: "Fisica", colorIndex: 1),
                TaskPreview(title: "Formulario", dueDate: .now, isOverdue: false, examName: "Analisi 1", isDone: true),
            ],
            doneToday: 1, totalToday: 3
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTasksEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let now = Date.now
        let recents = Set(RecentlyCompleted(defaults: AppGroup.sharedDefaults).active(at: now).keys)
        completion(entry(at: now, exams: widgetExams(), recentlyCompleted: recents))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTasksEntry>) -> Void) {
        let now = Date.now
        guard let exams = widgetExams() else {
            completion(Timeline(entries: [entry(at: now, exams: nil, recentlyCompleted: [])],
                                policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        let entries = widgetTimelineDates(now: now).map {
            entry(at: $0.date, exams: exams, recentlyCompleted: $0.recentlyCompleted)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, exams: [Exam]?, recentlyCompleted: Set<UUID>) -> TodayTasksEntry {
        guard let exams else { return TodayTasksEntry(date: date, today: TodaySummary(), isUnavailable: true) }
        return TodayTasksEntry(date: date, today: TodaySummary.make(from: exams, today: date,
                                                                    recentlyCompleted: recentlyCompleted))
    }
}

struct TodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayTasksWidget", provider: TodayTasksProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .widgetURL(ExamLink.todayURL)
        }
        .configurationDisplayName("Da fare oggi")
        .description("I task di oggi e quelli in ritardo di tutti gli esami, da spuntare.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Intestazione con il conto della giornata, poi tanti task quanti ci stanno: in ritardo, da fare, fatti.
struct TodayTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayTasksEntry

    private var today: TodaySummary { entry.today }
    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.isUnavailable {
                message("Sblocca l'iPhone per aggiornare", systemImage: "lock")
            } else if today.isEmpty {
                message("Niente in scadenza oggi", systemImage: "checkmark.seal")
            } else {
                FittingColumn(spacing: 6) {
                    ForEach(today.tasks, id: \.rowID) { task in
                        row(task)
                            .transition(.asymmetric(insertion: .push(from: .bottom),
                                                    removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Oggi")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                Spacer(minLength: 4)
                if today.overdueCount > 0 {
                    Text(isMedium ? "\(today.overdueCount) in ritardo" : "+\(today.overdueCount)")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Color(hex: Palette.danger))
                }
                if today.totalToday > 0 {
                    Text("\(today.doneToday) di \(today.totalToday)")
                        .font(.system(.caption, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            }
            if today.totalToday > 0 {
                ProgressView(value: today.progress)
                    .tint(today.doneToday == today.totalToday ? Color(hex: Palette.success) : Color(hex: Palette.accent))
            }
        }
    }

    private func row(_ task: TaskPreview) -> some View {
        let examColor = WidgetTheme.color(index: task.colorIndex)
        return HStack(spacing: 6) {
            WidgetTaskCheck(task: task, color: task.isOverdue ? Color(hex: Palette.danger) : examColor)
            WidgetTaskLink(task: task) {
                HStack(spacing: 6) {
                    WidgetTaskTitle(task: task, font: .footnote)
                        .layoutPriority(1)
                    if isMedium {
                        Text(task.examName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(examColor)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isMedium && task.isOverdue {
                        Text("in ritardo")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: Palette.danger))
                            .fixedSize()
                    }
                }
            }
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(WidgetTheme.textSecondary)
    }
}
