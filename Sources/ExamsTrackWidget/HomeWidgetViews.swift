import SwiftUI
import WidgetKit
import ExamsCore

/// Colori del tema per i widget della schermata Home.
enum WidgetTheme {
    static let background = Color(hex: Palette.background)
    static let textPrimary = Color(hex: Palette.textPrimary)
    static let textSecondary = Color(hex: Palette.textSecondary)
    static let elevated = Color(hex: Palette.elevated)

    static func examColor(_ summary: NextExamSummary) -> Color {
        color(index: summary.colorIndex)
    }

    static func color(index: Int) -> Color {
        Color(hex: Palette.examColors[index % Palette.examColors.count])
    }

    /// Colore dell'esame di un task della lista "Da fare".
    static func taskColor(_ task: TaskPreview?) -> Color? {
        task.map { color(index: $0.colorIndex) }
    }

    /// Colore del countdown: quello dell'esame, poi ambra a 7 giorni e corallo a 2.
    static func countdownColor(_ summary: NextExamSummary) -> Color {
        switch Urgency(days: summary.daysRemaining) {
        case .calm: examColor(summary)
        case .soon: Color(hex: Palette.warning)
        case .urgent: Color(hex: Palette.danger)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Date {
    static let italian = Locale(identifier: "it_IT")

    var widgetLong: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Self.italian))
    }

    var widgetShort: String {
        formatted(.dateTime.day().month(.abbreviated).locale(Self.italian))
    }
}

/// Countdown grande: "12 giorni", "Oggi", "Domani".
private struct HomeCountdown: View {
    let summary: NextExamSummary
    let numberSize: CGFloat

    var body: some View {
        Group {
            switch summary.daysRemaining {
            case 0:
                Text("Oggi").font(.countdown(size: numberSize * 0.8))
            case 1:
                Text("Domani").font(.countdown(size: numberSize * 0.8))
            default:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(summary.daysRemaining)")
                        .font(.countdown(size: numberSize * 1.25))
                        .monospacedDigit()
                    Text("giorni")
                        .font(.system(.subheadline, weight: .semibold))
                }
            }
        }
        .foregroundStyle(WidgetTheme.countdownColor(summary))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
}

/// Anello di avanzamento con la percentuale al centro.
private struct HomeProgressRing: View {
    let summary: NextExamSummary

    var body: some View {
        let color = WidgetTheme.examColor(summary)
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: summary.progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(summary.progressPercent)%")
                .font(.system(.caption, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.textPrimary)
        }
    }
}

struct SmallHomeWidgetView: View {
    let summary: NextExamSummary?
    let isUnavailable: Bool

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(.examName(.subheadline))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                HomeCountdown(summary: summary, numberSize: 44)
                if summary.hasTasks {
                    HStack(spacing: 6) {
                        ProgressView(value: summary.progress)
                            .tint(WidgetTheme.examColor(summary))
                        Text("\(summary.progressPercent)%")
                            .font(.system(.caption2, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                } else {
                    Text(summary.examDate.widgetShort)
                        .font(.caption)
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            EmptyHomeWidgetView(isUnavailable: isUnavailable)
        }
    }
}

struct MediumHomeWidgetView: View {
    let summary: NextExamSummary?
    let isUnavailable: Bool

    var body: some View {
        if let summary {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(summary.name)
                            .font(.examName(.headline))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(1)
                        if DegreeVisibility.saved == .both {
                            Text(summary.degree.label)
                                .font(.system(.caption2, weight: .semibold))
                                .foregroundStyle(WidgetTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(WidgetTheme.elevated))
                        }
                    }
                    HomeCountdown(summary: summary, numberSize: 40)
                    Text(summary.examDate.widgetLong)
                        .font(.caption)
                        .foregroundStyle(WidgetTheme.textSecondary)
                    Spacer(minLength: 0)
                    nextTask(summary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if summary.hasTasks {
                    VStack(spacing: 6) {
                        HomeProgressRing(summary: summary)
                            .frame(width: 58, height: 58)
                        Text("\(summary.completedTasks) di \(summary.totalTasks)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyHomeWidgetView(isUnavailable: isUnavailable)
        }
    }

    @ViewBuilder
    private func nextTask(_ summary: NextExamSummary) -> some View {
        if let task = summary.upcomingTasks.first {
            let examColor = WidgetTheme.color(index: task.colorIndex)
            HStack(alignment: .top, spacing: 8) {
                WidgetTaskCheck(task: task, color: task.isOverdue ? Color(hex: Palette.danger) : examColor)
                WidgetTaskLink(task: task) {
                    VStack(alignment: .leading, spacing: 1) {
                        WidgetTaskTitle(task: task, font: .footnote.weight(.medium))
                        HStack(spacing: 4) {
                            Text(task.examName)
                                .foregroundStyle(examColor)
                                .lineLimit(1)
                            Text(task.isOverdue ? "scaduto il \(task.dueDate.widgetShort)" : "entro il \(task.dueDate.widgetShort)")
                                .foregroundStyle(task.isOverdue ? Color(hex: Palette.danger) : WidgetTheme.textSecondary)
                                .fixedSize()
                        }
                        .font(.caption2)
                    }
                }
            }
            .id(task.rowID)
            .transition(.push(from: .bottom))
        } else if summary.hasTasks {
            Text("Tutti i task completati")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(hex: Palette.success))
        } else {
            Text("Nessun task pianificato")
                .font(.footnote)
                .foregroundStyle(WidgetTheme.textSecondary)
        }
    }
}

struct LargeHomeWidgetView: View {
    let summary: NextExamSummary?
    let isUnavailable: Bool

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 12) {
                WidgetExamHeader(summary: summary, numberSize: 44)
                WidgetDivider()
                WidgetTaskList(summary: summary, limit: 4)
                if !summary.followingExams.isEmpty {
                    WidgetDivider()
                    WidgetFollowingExams(exams: Array(summary.followingExams.prefix(2)), isDetailed: false)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyHomeWidgetView(isUnavailable: isUnavailable)
        }
    }
}

/// Solo iPad: a sinistra il prossimo esame e i suoi task, a destra i prossimi esami.
struct ExtraLargeHomeWidgetView: View {
    let summary: NextExamSummary?
    let isUnavailable: Bool

    var body: some View {
        if let summary {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    WidgetExamHeader(summary: summary, numberSize: 56)
                    WidgetDivider()
                    WidgetTaskList(summary: summary, limit: 6)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Rectangle()
                    .fill(Color(hex: Palette.stroke))
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 14) {
                    if summary.followingExams.isEmpty {
                        Text("Prossimi esami")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(WidgetTheme.textSecondary)
                        Text("Nessun altro esame in programma")
                            .font(.footnote)
                            .foregroundStyle(WidgetTheme.textSecondary)
                    } else {
                        // Riempie l'altezza della colonna: tanti esami quanti ci stanno.
                        WidgetFollowingExams(exams: summary.followingExams, isDetailed: true)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyHomeWidgetView(isUnavailable: isUnavailable)
        }
    }
}

struct WidgetDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: Palette.stroke))
            .frame(height: 1)
    }
}

/// Prossimo esame: nome, corso, countdown, data e avanzamento.
private struct WidgetExamHeader: View {
    let summary: NextExamSummary
    let numberSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(summary.name)
                        .font(.examName(.headline))
                        .foregroundStyle(WidgetTheme.textPrimary)
                        .lineLimit(1)
                    if DegreeVisibility.saved == .both {
                        Text(summary.degree.label)
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(WidgetTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(WidgetTheme.elevated))
                    }
                }
                HomeCountdown(summary: summary, numberSize: numberSize)
                Text(summary.examDate.widgetLong)
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if summary.hasTasks {
                VStack(spacing: 6) {
                    HomeProgressRing(summary: summary)
                        .frame(width: 62, height: 62)
                    Text("\(summary.completedTasks) di \(summary.totalTasks)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            }
        }
    }
}

/// Task da fare di tutti gli esami, col colore del proprio esame; quelli in ritardo in corallo.
private struct WidgetTaskList: View {
    let summary: NextExamSummary
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Da fare")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
            if summary.upcomingTasks.isEmpty {
                Text(summary.hasTasks ? "Tutti i task completati" : "Nessun task pianificato")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(summary.hasTasks ? Color(hex: Palette.success) : WidgetTheme.textSecondary)
            }
            ForEach(Array(summary.upcomingTasks.prefix(limit)), id: \.rowID) { task in
                let examColor = WidgetTheme.color(index: task.colorIndex)
                HStack(spacing: 8) {
                    WidgetTaskCheck(task: task, color: task.isOverdue ? Color(hex: Palette.danger) : examColor)
                    WidgetTaskLink(task: task) {
                        HStack(spacing: 8) {
                            WidgetTaskTitle(task: task, font: .footnote)
                                .layoutPriority(1)
                            Text(task.examName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(examColor)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(task.isOverdue ? "scaduto" : task.dueDate.widgetShort)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(task.isOverdue ? Color(hex: Palette.danger) : WidgetTheme.textSecondary)
                        }
                    }
                }
                // Spuntato, il task resta qualche secondo barrato e poi esce; i successivi risalgono.
                .transition(.asymmetric(insertion: .push(from: .bottom),
                                        removal: .opacity.combined(with: .move(edge: .leading))))
            }
        }
    }
}

extension TaskPreview {
    /// Identità stabile della riga, perché WidgetKit animi l'uscita del task giusto.
    var rowID: String { taskID?.uuidString ?? "\(title)|\(dueDate.timeIntervalSince1970)" }
}

/// Cerchio di un task: toccandolo si spunta (o si riapre, nei secondi in cui resta barrato).
/// Col `Toggle` iOS ridisegna subito il cerchio pieno, senza aspettare che l'azione finisca.
struct WidgetTaskCheck: View {
    let task: TaskPreview
    let color: Color

    var body: some View {
        if let examID = task.examID, let taskID = task.taskID {
            Toggle(isOn: task.isDone, intent: CompleteTaskIntent(examID: examID, taskID: taskID, isDone: !task.isDone)) {
                Text(task.title)
            }
            .toggleStyle(WidgetCheckStyle(color: color))
            .accessibilityLabel(task.isDone ? "Segna \(task.title) come da fare" : "Segna \(task.title) come fatto")
        } else {
            WidgetCheckCircle(isOn: task.isDone, color: color)
        }
    }
}

/// Mostra solo il cerchio: il titolo accanto è un link a parte.
struct WidgetCheckStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        WidgetCheckCircle(isOn: configuration.isOn, color: color)
    }
}

/// Cerchio vuoto, o pieno con la spunta quando il task è fatto.
struct WidgetCheckCircle: View {
    let isOn: Bool
    let color: Color

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .animation(.snappy, value: isOn)
    }
}

/// Titolo del task, barrato quando è appena stato spuntato.
struct WidgetTaskTitle: View {
    let task: TaskPreview
    let font: Font

    var body: some View {
        Text(task.title)
            .font(font)
            .strikethrough(task.isDone, color: WidgetTheme.textSecondary)
            .foregroundStyle(task.isDone ? WidgetTheme.textSecondary : WidgetTheme.textPrimary)
            .lineLimit(1)
    }
}

/// Il resto della riga: apre l'esame del task, con la timeline all'altezza del task.
struct WidgetTaskLink<Content: View>: View {
    let task: TaskPreview
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let examID = task.examID, let taskID = task.taskID {
            Link(destination: ExamLink.url(for: examID, taskID: taskID)) {
                content().contentShape(Rectangle())
            }
        } else {
            content()
        }
    }
}

/// Esami successivi: compatti (nome e giorni) o dettagliati (con data e avanzamento).
private struct WidgetFollowingExams: View {
    let exams: [ExamPreview]
    let isDetailed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isDetailed ? 12 : 7) {
            Text(isDetailed ? "Prossimi esami" : "Dopo")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
            if isDetailed {
                FittingColumn(spacing: 12) { rows }
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        ForEach(Array(exams.enumerated()), id: \.offset) { _, exam in
            if let id = exam.examID {
                // Ogni esame dell'elenco apre il proprio dettaglio.
                Link(destination: ExamLink.url(for: id)) { row(exam) }
            } else {
                row(exam)
            }
        }
    }

    private func row(_ exam: ExamPreview) -> some View {
        let color = Color(hex: Palette.examColors[exam.colorIndex % Palette.examColors.count])
        return HStack(alignment: isDetailed ? .top : .center, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 4, height: isDetailed ? 38 : 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exam.name)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(1)
                        if isDetailed {
                            Text(exam.examDate.widgetLong)
                                .font(.caption2)
                                .foregroundStyle(WidgetTheme.textSecondary)
                            if exam.hasTasks {
                                ProgressView(value: exam.progress)
                                    .tint(color)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    Text(exam.daysRemaining == 0 ? "Oggi" : exam.daysRemaining == 1 ? "Domani" : "\(exam.daysRemaining) g")
                        .font(.system(isDetailed ? .subheadline : .footnote, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isDetailed ? color : WidgetTheme.textSecondary)
        }
    }
}

/// Colonna che occupa tutta l'altezza proposta e mostra, dall'alto, solo le righe che ci stanno per intero;
/// le altre finiscono fuori dal widget, che le ritaglia.
struct FittingColumn: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height }
        let total = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: width, height: proposal.height ?? total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var isFull = false
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            if !isFull && y + height <= bounds.maxY + 0.5 {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            } else {
                isFull = true
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 10_000), proposal: .zero)
            }
        }
    }
}

struct EmptyHomeWidgetView: View {
    let isUnavailable: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isUnavailable ? "lock" : "graduationcap")
                .font(.title2)
                .foregroundStyle(Color(hex: Palette.accent))
            Text(isUnavailable ? "Sblocca l'iPhone per aggiornare" : "Nessun esame in programma")
                .font(.system(.footnote, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(WidgetTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
