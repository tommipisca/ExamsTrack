import SwiftUI
import ExamsCore

/// Riquadro del prossimo esame (in lista) e intestazione del dettaglio.
struct ExamCard: View {
    let exam: Exam
    let today: Date
    var showsName = true

    var body: some View {
        let days = exam.daysRemaining(today: today)
        let color = Theme.color(for: exam)

        HStack(alignment: .top, spacing: 16) {
            // Il colore dell'esame come segno a margine, non come velatura del riquadro.
            Capsule()
                .fill(color)
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if showsName {
                            Text(exam.name)
                                .font(.examName(.title2))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                        }
                        Text(dateLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        DegreeTag(degree: exam.degree)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    // Senza task non c'è avanzamento da mostrare.
                    if !exam.tasks.isEmpty {
                        ProgressRing(progress: exam.progress, color: color)
                            .frame(width: 58, height: 58)
                    }
                }

                if !exam.isScheduled {
                    Text("Da programmare")
                        .font(.countdown(size: 40))
                        .foregroundStyle(color)
                } else if days >= 0, exam.startTime != nil {
                    // Con l'orario: tempo reale fino all'inizio, aggiornato ogni minuto.
                    TimelineView(.everyMinute) { context in
                        if let countdown = exam.preciseCountdown(now: context.date) {
                            PreciseCountdownText(countdown: countdown, color: Theme.countdownColor(days: days, examColor: color))
                        }
                    }
                } else if days >= 0 {
                    CountdownText(days: days, color: Theme.countdownColor(days: days, examColor: color))
                } else {
                    Text(exam.outcomeLabel)
                        .font(.examName(.title2))
                        .foregroundStyle(Theme.textPrimary)
                }

                Text(exam.tasks.isEmpty ? "Nessun task: aggiungine uno per pianificare lo studio" : "\(exam.completedTaskCount) di \(exam.tasks.count) task completati")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .combine)
    }
}

extension ExamCard {
    /// "lunedì 24 novembre 2026, ore 14:30"
    fileprivate var dateLine: String {
        guard exam.isScheduled else { return "Data da definire" }
        guard let time = exam.startTimeLabel else { return exam.date.italianLong }
        return "\(exam.date.italianLong), ore \(time)"
    }
}

/// Countdown preciso: "11 giorni" grande con "e 20 ore" sotto, fino a "In corso".
struct PreciseCountdownText: View {
    let countdown: PreciseCountdown
    let color: Color
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber: CGFloat = 76

    var body: some View {
        switch countdown {
        case .remaining(let value, let unit, let detail):
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(value)")
                        .font(.countdown(size: bigNumber))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(unit)
                        .font(.ui(.title3, weight: .semibold))
                        .opacity(0.8)
                }
                if let detail {
                    Text(detail)
                        .font(.ui(.title3, weight: .semibold))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(color)
        case .lessThanAMinute:
            Text("Meno di un minuto")
                .font(.countdown(size: 40))
                .foregroundStyle(color)
        case .started:
            Label("In corso", systemImage: "pencil.and.outline")
                .font(.countdown(size: 40))
                .foregroundStyle(color)
        }
    }
}

/// Riga compatta di un esame in arrivo: barra colorata, nome, giorni e avanzamento.
struct UpcomingExamRow: View {
    let exam: Exam
    let today: Date

    var body: some View {
        let days = exam.daysRemaining(today: today)
        let color = Theme.color(for: exam)

        HStack(spacing: 12) {
            ColorBar(color: color)
            VStack(alignment: .leading, spacing: 3) {
                // Nelle colonne strette il nome va a capo invece di essere troncato.
                Text(exam.name)
                    .font(.examName(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(exam.isScheduled ? exam.date.italianShort : "Da programmare")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    DegreeTag(degree: exam.degree)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            // Countdown e avanzamento non si comprimono mai: si restringe solo il nome.
            VStack(alignment: .trailing, spacing: 6) {
                if exam.isScheduled {
                    CountdownText(days: days, color: Theme.countdownColor(days: days, examColor: color), isLarge: false)
                }
                if !exam.tasks.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView(value: exam.progress)
                            .tint(color)
                            .frame(width: 56)
                        Text("\(exam.progressPercent)%")
                            .font(.ui(.caption2, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 6)
        // VoiceOver legge la riga come un unico elemento.
        .accessibilityElement(children: .combine)
    }
}

/// Riga di un esame passato, con l'esito in un badge.
struct PastExamRow: View {
    let exam: Exam

    var body: some View {
        HStack(spacing: 12) {
            ColorBar(color: Theme.color(for: exam))
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.name)
                    .font(.examName(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(exam.date.italianShort)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            GradeBadge(exam: exam)
        }
        .padding(.vertical, 4)
        // VoiceOver legge la riga come un unico elemento.
        .accessibilityElement(children: .combine)
    }
}

/// Segno verticale con il colore dell'esame.
struct ColorBar: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 4, height: 36)
            .accessibilityHidden(true)
    }
}
