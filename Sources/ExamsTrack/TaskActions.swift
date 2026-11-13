import SwiftUI
import ExamsCore

/// Un task da modificare con il form, aperto da una schermata che mostra task di più esami.
struct TaskEditTarget: Identifiable {
    let examID: UUID
    let examDate: Date?
    let task: StudyTask

    var id: UUID { task.id }
}

extension ExamStore {
    /// Domani, se il task scade prima di domani e domani non è dopo l'esame; altrimenti nil.
    func tomorrowTarget(for task: StudyTask, inExam examID: UUID, today: Date, calendar: Calendar = .current) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        let tomorrowStart = calendar.startOfDay(for: tomorrow)
        guard calendar.startOfDay(for: task.dueDate) < tomorrowStart else { return nil }
        if let exam = exam(id: examID), exam.isScheduled, tomorrowStart > calendar.startOfDay(for: exam.date) {
            return nil
        }
        return tomorrow
    }
}

/// Menu contestuale di un task (pressione prolungata, o clic destro su iPad):
/// fatto/da fare, sposta a domani, sessione di studio, modifica, elimina.
private struct TaskContextMenu: ViewModifier {
    @Environment(ExamStore.self) private var store
    @Environment(StudySessionController.self) private var study
    @Environment(\.today) private var today
    let examID: UUID
    let task: StudyTask
    let onEdit: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                store.toggleTask(id: task.id, inExam: examID)
            } label: {
                Label(task.isDone ? "Segna da fare" : "Segna come fatto",
                      systemImage: task.isDone ? "circle" : "checkmark.circle")
            }
            if let tomorrow = store.tomorrowTarget(for: task, inExam: examID, today: today) {
                Button {
                    store.moveTask(id: task.id, inExam: examID, to: tomorrow)
                } label: {
                    Label("Sposta a domani", systemImage: "arrow.turn.down.right")
                }
            }
            if !task.isDone, let exam = store.exam(id: examID) {
                StudyDurationMenu(target: .init(examID: exam.id, examName: exam.name,
                                                colorIndex: exam.colorIndex ?? 0, taskID: task.id, taskTitle: task.title))
            }
            if let onEdit {
                Button(action: onEdit) {
                    Label("Modifica", systemImage: "pencil")
                }
            }
            Divider()
            Button(role: .destructive) {
                store.deleteTask(id: task.id, fromExam: examID)
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
}

extension View {
    func taskContextMenu(examID: UUID, task: StudyTask, onEdit: (() -> Void)? = nil) -> some View {
        modifier(TaskContextMenu(examID: examID, task: task, onEdit: onEdit))
    }
}

/// Azioni a scorrimento di un task in una lista: verso destra "Domani", verso sinistra fatto/da fare.
private struct TaskSwipeActions: ViewModifier {
    @Environment(ExamStore.self) private var store
    @Environment(\.today) private var today
    let examID: UUID
    let task: StudyTask

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let tomorrow = store.tomorrowTarget(for: task, inExam: examID, today: today) {
                    Button {
                        withAnimation { store.moveTask(id: task.id, inExam: examID, to: tomorrow) }
                    } label: {
                        Label("Domani", systemImage: "arrow.turn.down.right")
                    }
                    .tint(Theme.warning)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    withAnimation { store.toggleTask(id: task.id, inExam: examID) }
                } label: {
                    Label(task.isDone ? "Da fare" : "Fatto", systemImage: task.isDone ? "circle" : "checkmark.circle")
                }
                .tint(task.isDone ? Theme.textSecondary : Theme.success)
            }
    }
}

extension View {
    func taskSwipeActions(examID: UUID, task: StudyTask) -> some View {
        modifier(TaskSwipeActions(examID: examID, task: task))
    }
}

/// Avviso con i task in ritardo e il pulsante per ridistribuirli fino all'esame.
struct RescheduleBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(Theme.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 task in ritardo" : "\(count) task in ritardo")
                    .font(.ui(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Ridistribuiscili da oggi fino all'esame.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button("Ripianifica", action: action)
                .font(.ui(.subheadline, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.danger.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.35), lineWidth: 1))
    }
}

/// Contenuto trascinabile di un task: "idEsame|idTask".
enum TaskDragPayload {
    static func encode(examID: UUID, taskID: UUID) -> String {
        "\(examID.uuidString)|\(taskID.uuidString)"
    }

    static func decode(_ text: String) -> (examID: UUID, taskID: UUID)? {
        let parts = text.split(separator: "|")
        guard parts.count == 2, let exam = UUID(uuidString: String(parts[0])),
              let task = UUID(uuidString: String(parts[1])) else { return nil }
        return (exam, task)
    }
}
