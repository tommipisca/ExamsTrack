import SwiftUI
import WidgetKit
import ExamsCore

struct NextExamWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: NextExamEntry

    var body: some View {
        content
            // Toccando il widget (fuori dai task e dagli altri esami) si apre la scheda "Oggi".
            .widgetURL(ExamLink.todayURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall where renderingMode == .vibrant:
            // Schermata di blocco di iPad: monocromatico, sullo sfondo, senza il fondo scuro.
            LockScreenSmallView(summary: entry.summary, today: entry.today, isUnavailable: entry.isUnavailable)
        case .systemSmall:
            SmallHomeWidgetView(summary: entry.summary, isUnavailable: entry.isUnavailable)
        case .systemMedium:
            MediumHomeWidgetView(summary: entry.summary, isUnavailable: entry.isUnavailable)
        case .systemLarge:
            LargeHomeWidgetView(summary: entry.summary, isUnavailable: entry.isUnavailable)
        case .systemExtraLarge:
            ExtraLargeHomeWidgetView(summary: entry.summary, isUnavailable: entry.isUnavailable)
        case .accessoryCircular:
            CircularNextExamView(summary: entry.summary, isUnavailable: entry.isUnavailable)
        default:
            RectangularNextExamView(summary: entry.summary, today: entry.today, isUnavailable: entry.isUnavailable)
        }
    }
}

/// Schermata di blocco: la giornata di studio (task di oggi, ritardi, il prossimo da fare)
/// sotto il nome e i giorni del prossimo esame. Il countdown grande resta nel widget rotondo.
struct RectangularNextExamView: View {
    let summary: NextExamSummary?
    let today: TodaySummary
    let isUnavailable: Bool

    var body: some View {
        if summary != nil || !today.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                if let summary {
                    HStack(spacing: 4) {
                        Text(summary.name)
                            .font(.examName(.headline))
                            .lineLimit(1)
                            .widgetAccentable()
                        Spacer(minLength: 4)
                        Text(Countdown.compactLabel(days: summary.daysRemaining))
                            .font(.system(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
                Text(dayLine)
                    .font(.subheadline)
                    .lineLimit(1)
                if let next = today.nextTask {
                    Label(next.title, systemImage: next.isOverdue ? "exclamationmark.circle" : "circle")
                        .font(.subheadline)
                        .lineLimit(1)
                } else if today.totalToday > 0 {
                    Label("Tutto fatto per oggi", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(isUnavailable ? "Sblocca l'iPhone per aggiornare" : "Nessun esame in programma")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Oggi: 2 di 5, 1 in ritardo", "Niente da fare oggi"...
    private var dayLine: String {
        let late = today.overdueCount > 0 ? "\(today.overdueCount) in ritardo" : nil
        if today.totalToday > 0 {
            return (["Oggi: \(today.doneToday) di \(today.totalToday)"] + [late].compactMap { $0 }).joined(separator: ", ")
        }
        return late ?? "Niente da fare oggi"
    }
}

struct CircularNextExamView: View {
    let summary: NextExamSummary?
    let isUnavailable: Bool

    var body: some View {
        if let summary, !summary.hasTasks {
            // Senza task: niente anello di avanzamento, solo i giorni mancanti.
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "graduationcap.fill")
                        .font(.caption2)
                    Text(Countdown.compactLabel(days: summary.daysRemaining))
                        .font(.system(.body, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(4)
            }
        } else if let summary {
            Gauge(value: summary.progress) {
                Text("")
            } currentValueLabel: {
                Text(Countdown.compactLabel(days: summary.daysRemaining))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: isUnavailable ? "lock" : "graduationcap")
                    Text("—")
                }
            }
        }
    }
}

/// Widget quadrato sulla schermata di blocco di iPad: countdown del prossimo esame e, sotto,
/// la giornata di studio con il prossimo task. iOS lo disegna in una sola tinta, quindi la gerarchia
/// è data da dimensioni e opacità, non dai colori degli esami.
struct LockScreenSmallView: View {
    let summary: NextExamSummary?
    let today: TodaySummary
    let isUnavailable: Bool

    var body: some View {
        if summary == nil && today.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: isUnavailable ? "lock" : "graduationcap")
                    .font(.title2)
                Text(isUnavailable ? "Sblocca per aggiornare" : "Nessun esame in programma")
                    .font(.system(.footnote, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if let summary {
                    Label(summary.name, systemImage: "graduationcap.fill")
                        .font(.system(.caption, weight: .semibold))
                        .lineLimit(1)
                        .widgetAccentable()
                    countdown(summary)
                    Text(summary.examDate.widgetLong)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                dayProgress
                nextTask
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func countdown(_ summary: NextExamSummary) -> some View {
        Group {
            switch summary.daysRemaining {
            case 0: Text("Oggi")
            case 1: Text("Domani")
            default:
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(summary.daysRemaining)")
                        .monospacedDigit()
                    Text("giorni")
                        .font(.system(.footnote, weight: .semibold))
                }
            }
        }
        .font(.countdown(size: 46))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }

    @ViewBuilder
    private var dayProgress: some View {
        if today.totalToday > 0 || today.overdueCount > 0 {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(today.totalToday > 0 ? "Oggi \(today.doneToday) di \(today.totalToday)" : "Oggi")
                        .monospacedDigit()
                    if today.overdueCount > 0 {
                        Text("\(today.overdueCount) in ritardo")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(.caption2, weight: .semibold))
                .lineLimit(1)
                if today.totalToday > 0 {
                    ProgressView(value: today.progress)
                        .widgetAccentable()
                }
            }
        }
    }

    @ViewBuilder
    private var nextTask: some View {
        if let next = today.nextTask {
            Label(next.title, systemImage: next.isOverdue ? "exclamationmark.circle" : "circle")
                .font(.caption)
                .lineLimit(2)
                .padding(.top, 2)
        } else {
            Label(today.totalToday > 0 ? "Tutto fatto per oggi" : "Niente da fare oggi",
                  systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
    }
}
