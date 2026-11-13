import ActivityKit
import SwiftUI
import WidgetKit
import ExamsCore

/// Il giorno dell'esame: countdown all'inizio sulla schermata di blocco e nella Dynamic Island.
/// La avvia l'app (vedi `ExamActivityController`); dopo l'inizio diventa "in bocca al lupo".
struct ExamLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExamActivityAttributes.self) { context in
            ExamActivityLockScreenView(context: context)
                .activityBackgroundTint(WidgetTheme.background)
                .activitySystemActionForegroundColor(WidgetTheme.textPrimary)
                .widgetURL(ExamLink.url(for: context.attributes.examID))
        } dynamicIsland: { context in
            let color = WidgetTheme.color(index: context.attributes.colorIndex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.examName, systemImage: "graduationcap.fill")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExamActivityTimer(context: context, font: .system(.title3, weight: .bold))
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "In bocca al lupo!" : "Inizio alle \(context.state.start.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            } compactLeading: {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(color)
            } compactTrailing: {
                ExamActivityTimer(context: context, font: .system(.caption, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(color)
            }
            .widgetURL(ExamLink.url(for: context.attributes.examID))
            .keylineTint(color)
        }
    }
}

/// Tempo che manca all'inizio, aggiornato dal sistema; dopo l'inizio "Ora".
private struct ExamActivityTimer: View {
    let context: ActivityViewContext<ExamActivityAttributes>
    let font: Font

    var body: some View {
        Group {
            if context.isStale || context.state.start <= .now {
                Text("Ora")
            } else {
                Text(timerInterval: Date.now...context.state.start, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(font)
    }
}

private struct ExamActivityLockScreenView: View {
    let context: ActivityViewContext<ExamActivityAttributes>

    var body: some View {
        let color = WidgetTheme.color(index: context.attributes.colorIndex)
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.examName)
                    .font(.examName(.headline))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                Text(context.isStale ? "In bocca al lupo!" : "Inizio alle \(context.state.start.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            Spacer(minLength: 8)
            ExamActivityTimer(context: context, font: .countdown(size: 40))
                .foregroundStyle(color)
                .frame(maxWidth: 140, alignment: .trailing)
        }
        .padding(16)
    }
}
