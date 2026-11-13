import AppIntents
import SwiftUI
import WidgetKit
import ExamsCore

/// Corso da mostrare nel widget "Media e simulazione".
enum DegreeChoice: String, AppEnum {
    case automatic, triennale, magistrale

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Corso"
    static let caseDisplayRepresentations: [DegreeChoice: DisplayRepresentation] = [
        .automatic: "Automatico",
        .triennale: "Triennale",
        .magistrale: "Magistrale",
    ]
}

struct SelectDegreeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Scegli il corso"
    static let description = IntentDescription("Automatico: il corso mostrato nell'app, o la magistrale se c'è.")

    @Parameter(title: "Corso", default: .automatic)
    var degree: DegreeChoice

    init() {}
}

struct CareerEntry: TimelineEntry {
    let date: Date
    let summary: CareerSummary?
    var isUnavailable = false
}

struct CareerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CareerEntry {
        CareerEntry(date: .now, summary: CareerSummary(
            degree: .triennale, average: 27.45, earnedCFU: 120, totalCFU: 180,
            estimate: GraduationEstimate(minimum: 101, maximum: 108, honorsThreshold: 113, canGetHonors: false),
            simulatedAverage: 27.9,
            simulatedEstimate: GraduationEstimate(minimum: 104, maximum: 109, honorsThreshold: 113, canGetHonors: false)
        ))
    }

    func snapshot(for configuration: SelectDegreeIntent, in context: Context) async -> CareerEntry {
        context.isPreview ? placeholder(in: context) : entry(configuration)
    }

    func timeline(for configuration: SelectDegreeIntent, in context: Context) async -> Timeline<CareerEntry> {
        // Cambia solo quando cambiano i dati: l'app ricarica il widget a ogni salvataggio.
        let entry = entry(configuration)
        return Timeline(entries: [entry], policy: entry.isUnavailable ? .after(.now.addingTimeInterval(15 * 60)) : .never)
    }

    private func entry(_ configuration: SelectDegreeIntent) -> CareerEntry {
        guard let all = ExamStore.readOnly(from: AppGroup.dataFileURL()) else {
            return CareerEntry(date: .now, summary: nil, isUnavailable: true)
        }
        let visibility = DegreeVisibility.saved
        let degree: Degree = switch configuration.degree {
        case .automatic: CareerSummary.automaticDegree(exams: all.visible(visibility), visibility: visibility)
        case .triennale: .triennale
        case .magistrale: .magistrale
        }
        let thesis = ThesisType(rawValue: AppGroup.sharedDefaults.string(forKey: ThesisType.storageKey) ?? "") ?? .withReviewer
        return CareerEntry(date: .now, summary: CareerSummary.make(from: all, degree: degree, thesis: thesis))
    }
}

struct CareerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CareerWidget", intent: SelectDegreeIntent.self, provider: CareerProvider()) { entry in
            CareerWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.background }
                .widgetURL(ExamLink.careerURL)
        }
        .configurationDisplayName("Media e simulazione")
        .description("Media ponderata, crediti e voto di laurea stimato, anche con i voti simulati.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CareerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CareerEntry

    private var accent: Color { Color(hex: Palette.accent) }
    private var success: Color { Color(hex: Palette.success) }

    var body: some View {
        if let summary = entry.summary {
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 16) {
                    averageColumn(summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Color(hex: Palette.stroke)).frame(width: 1)
                    graduationColumn(summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    averageColumn(summary)
                    Spacer(minLength: 0)
                    if let estimate = summary.estimate {
                        smallLine("Laurea", CareerSummary.gradeText(estimate))
                    }
                    if let simulated = summary.simulatedAverage {
                        smallLine("Simulata", CareerSummary.averageText(simulated), color: success)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyHomeWidgetView(isUnavailable: entry.isUnavailable)
        }
    }

    private func averageColumn(_ summary: CareerSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.degree.label)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
            Text(CareerSummary.averageText(summary.average))
                .font(.countdown(size: 42))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("media ponderata")
                .font(.caption2)
                .foregroundStyle(WidgetTheme.textSecondary)
            Spacer(minLength: 4)
            ProgressView(value: summary.cfuProgress)
                .tint(accent)
            Text("\(summary.earnedCFU) di \(summary.totalCFU) CFU")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.textSecondary)
        }
    }

    private func graduationColumn(_ summary: CareerSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voto di laurea")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
            Text(summary.estimate.map(CareerSummary.gradeText) ?? "—")
                .font(.countdown(size: 36))
                .monospacedDigit()
                .foregroundStyle(accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(summary.estimate?.canGetHonors == true ? "stimato, lode possibile" : "stimato")
                .font(.caption2)
                .foregroundStyle(WidgetTheme.textSecondary)
            Spacer(minLength: 4)
            if let simulated = summary.simulatedAverage {
                Text("Con la simulazione")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(success)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CareerSummary.averageText(simulated))
                        .font(.system(.subheadline, weight: .bold))
                        .monospacedDigit()
                    if let estimate = summary.simulatedEstimate {
                        Text("laurea \(CareerSummary.gradeText(estimate))")
                            .font(.system(.subheadline, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(success)
            } else {
                Text("Nessuna simulazione")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
        }
    }

    private func smallLine(_ title: String, _ value: String, color: Color = WidgetTheme.textPrimary) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(WidgetTheme.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(.footnote, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}
