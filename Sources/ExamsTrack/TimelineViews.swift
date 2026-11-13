import SwiftUI
import ExamsCore

/// Colonna della timeline: linea verticale continua con un simbolo al centro.
struct TimelineMarker<Content: View>: View {
    let color: Color
    let isFirst: Bool
    let isLast: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Circle().fill(Theme.background))
            .frame(width: 30)
            .frame(maxHeight: .infinity)
            .background {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isFirst ? Color.clear : color.opacity(0.35))
                        .frame(width: 2)
                    Rectangle()
                        .fill(isLast ? Color.clear : color.opacity(0.35))
                        .frame(width: 2)
                }
            }
    }
}

struct TimelineRow: View {
    let task: StudyTask
    let color: Color
    let isOverdue: Bool
    let isFirst: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    /// Riga raggiunta da un link del widget.
    var isHighlighted = false
    /// Spunta una voce della checklist.
    var onToggleSubtask: ((UUID) -> Void)?

    var body: some View {
        let markerColor = isOverdue ? Theme.danger : color

        VStack(spacing: 0) {
            HStack(spacing: 14) {
                TimelineMarker(color: color, isFirst: isFirst, isLast: false) {
                    Button(action: onToggle) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(markerColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: task.isDone) { _, isDone in isDone }
                    .accessibilityLabel(task.isDone ? "Segna come da fare" : "Segna come fatto")
                }
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.body)
                            .strikethrough(task.isDone, color: Theme.textSecondary)
                            .foregroundStyle(task.isDone ? Theme.textSecondary : Theme.textPrimary)
                        HStack(spacing: 6) {
                            Text(isOverdue ? "In ritardo, scadeva il \(task.dueDate.italianShort)" : task.dueDate.italianShort)
                                .foregroundStyle(isOverdue ? Theme.danger : Theme.textSecondary)
                            if let label = task.subtaskLabel {
                                Label(label, systemImage: "checklist")
                                    .foregroundStyle(Theme.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
            }

            if !task.subtasks.isEmpty {
                // La checklist sotto il task, con la linea della timeline che prosegue a sinistra.
                HStack(alignment: .top, spacing: 14) {
                    Rectangle()
                        .fill(color.opacity(0.35))
                        .frame(width: 2)
                        .frame(width: 30)
                        .frame(maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(task.subtasks) { subtask in
                            SubtaskRow(subtask: subtask, color: color) { onToggleSubtask?(subtask.id) }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(isHighlighted ? 0.2 : 0))
                .padding(.horizontal, -8)
        }
    }
}

/// Una voce della checklist: si spunta toccandola.
struct SubtaskRow: View {
    let subtask: Subtask
    let color: Color
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(subtask.isDone ? color : Theme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(subtask.title)
                    .font(.subheadline)
                    .strikethrough(subtask.isDone, color: Theme.textSecondary)
                    .foregroundStyle(subtask.isDone ? Theme.textSecondary : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: subtask.isDone)
        .accessibilityLabel(subtask.isDone ? "\(subtask.title), fatta. Segna da fare" : "\(subtask.title). Segna fatta")
    }
}

/// Segnaposto della data di oggi tra i task.
struct TodayMarkerRow: View {
    let color: Color
    let isFirst: Bool
    let today: Date

    var body: some View {
        HStack(spacing: 14) {
            TimelineMarker(color: color, isFirst: isFirst, isLast: false) {
                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: 10, height: 10)
                    .padding(6)
            }
            HStack(spacing: 8) {
                Text("Oggi")
                    .font(.ui(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(today.italianShort)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ultimo nodo della timeline: il giorno dell'esame.
struct ExamMilestoneRow: View {
    let exam: Exam
    let color: Color
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 14) {
            TimelineMarker(color: color, isFirst: isFirst, isLast: true) {
                Image(systemName: "graduationcap.circle.fill")
                    .font(.title)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Esame")
                    .font(.ui(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(exam.isScheduled ? exam.date.italianLong : "Data da definire")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 12)
            Spacer()
        }
    }
}
