import SwiftUI
import ExamsCore

/// Crea un nuovo task (`task == nil`) o modifica titolo e scadenza di uno esistente.
struct TaskFormView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let examID: UUID
    /// Limite per la scadenza; nil se l'esame non è ancora programmato.
    let examDate: Date?
    let task: StudyTask?
    @State private var title: String
    @State private var dueDate: Date
    /// Voci della checklist in modifica: quelle esistenti tengono id e stato.
    @State private var subtasks: [Subtask]
    @FocusState private var focusedSubtask: UUID?

    init(examID: UUID, examDate: Date?, task: StudyTask?) {
        self.examID = examID
        self.examDate = examDate
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _subtasks = State(initialValue: task?.subtasks ?? [])
        let today = Calendar.current.startOfDay(for: .now)
        _dueDate = State(initialValue: task?.dueDate ?? examDate.map { min(today, $0) } ?? today)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cosa devi fare, es. Ripasso capitoli 1-3", text: $title)
                    if let examDate {
                        DatePicker("Entro il", selection: $dueDate, in: ...examDate, displayedComponents: .date)
                    } else {
                        DatePicker("Entro il", selection: $dueDate, displayedComponents: .date)
                    }
                } footer: {
                    if examDate != nil {
                        Text("La scadenza non può superare il giorno dell'esame.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach($subtasks) { $subtask in
                        HStack(spacing: 10) {
                            Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(subtask.isDone ? Theme.success : Theme.textSecondary)
                                .onTapGesture { subtask.isDone.toggle() }
                                .accessibilityLabel(subtask.isDone ? "Segna da fare" : "Segna fatta")
                            TextField("Voce, es. Esercizi", text: $subtask.title)
                                .focused($focusedSubtask, equals: subtask.id)
                                .submitLabel(.next)
                                .onSubmit(addSubtask)
                        }
                    }
                    .onDelete { subtasks.remove(atOffsets: $0) }
                    .onMove { subtasks.move(fromOffsets: $0, toOffset: $1) }
                    Button(action: addSubtask) {
                        Label("Aggiungi voce", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Sotto-task")
                } footer: {
                    Text("Facoltativi: una checklist del task. Il task è fatto quando lo sono tutte le voci, e quelle già fatte contano nell'avanzamento dell'esame.")
                }
                .listRowBackground(Theme.surface)
            }
            .themedListBackground()
            .navigationTitle(task == nil ? "Nuovo task" : "Modifica task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationBackground(Theme.background)
        .storeErrorAlert()
    }

    private func addSubtask() {
        // Una sola riga vuota alla volta: Invio su una voce vuota non ne aggiunge altre.
        if let last = subtasks.last, last.title.trimmingCharacters(in: .whitespaces).isEmpty {
            focusedSubtask = last.id
            return
        }
        let new = Subtask(title: "")
        subtasks.append(new)
        focusedSubtask = new.id
    }

    private func save() {
        let cleanSubtasks = subtasks
            .map { var sub = $0; sub.title = sub.title.trimmingCharacters(in: .whitespacesAndNewlines); return sub }
            .filter { !$0.title.isEmpty }
        if var edited = task {
            edited.title = trimmedTitle
            edited.dueDate = dueDate
            edited.subtasks = cleanSubtasks
            store.updateTask(edited, inExam: examID)
        } else {
            store.addTask(StudyTask(title: trimmedTitle, dueDate: dueDate, subtasks: cleanSubtasks), toExam: examID)
        }
        // Se il salvataggio fallisce resta aperto, così l'avviso compare qui.
        if store.lastError == nil {
            dismiss()
        }
    }
}
