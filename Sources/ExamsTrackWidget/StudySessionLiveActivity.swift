import ActivityKit
import SwiftUI
import WidgetKit
import ExamsCore

/// Sessione di studio: timer sulla schermata di blocco e nella Dynamic Island.
struct StudySessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudySessionAttributes.self) { context in
            StudySessionLockScreenView(context: context)
                .activityBackgroundTint(WidgetTheme.background)
                .activitySystemActionForegroundColor(WidgetTheme.textPrimary)
                .widgetURL(ExamLink.todayURL)
        } dynamicIsland: { context in
            let color = WidgetTheme.color(index: context.attributes.colorIndex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.examName, systemImage: "timer")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StudyTimer(context: context, font: .system(.title3, weight: .bold))
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let task = context.attributes.taskTitle {
                            Text(task)
                                .font(.footnote)
                                .foregroundStyle(WidgetTheme.textPrimary)
                                .lineLimit(1)
                        }
                        StudyProgress(context: context, color: color)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(color)
            } compactTrailing: {
                StudyTimer(context: context, font: .system(.caption, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(color)
            }
            .widgetURL(ExamLink.todayURL)
            .keylineTint(color)
        }
    }
}

/// Minuti e secondi che mancano alla fine, aggiornati dal sistema; poi "Pausa".
private struct StudyTimer: View {
    let context: ActivityViewContext<StudySessionAttributes>
    let font: Font

    var body: some View {
        Group {
            if context.isStale || context.state.end <= .now {
                Text("Pausa")
            } else {
                Text(timerInterval: Date.now...context.state.end, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(font)
    }
}

/// Barra del tempo trascorso, animata dal sistema senza aggiornamenti dall'app.
private struct StudyProgress: View {
    let context: ActivityViewContext<StudySessionAttributes>
    let color: Color

    var body: some View {
        let start = context.attributes.start
        let end = max(context.state.end, start.addingTimeInterval(1))
        ProgressView(timerInterval: start...end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(color)
    }
}

private struct StudySessionLockScreenView: View {
    let context: ActivityViewContext<StudySessionAttributes>

    var body: some View {
        let color = WidgetTheme.color(index: context.attributes.colorIndex)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskTitle ?? "Sessione di studio")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textPrimary)
                        .lineLimit(1)
                    Text(context.isStale ? "Sessione finita: fai una pausa" : context.attributes.examName)
                        .font(.subheadline)
                        .foregroundStyle(context.isStale ? WidgetTheme.textSecondary : color)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                StudyTimer(context: context, font: .countdown(size: 36))
                    .foregroundStyle(color)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            if !context.isStale {
                StudyProgress(context: context, color: color)
            }
        }
        .padding(16)
    }
}
