import SwiftUI
import ExamsCore

/// Note dell'esame nel dettaglio: anteprima che apre l'editor.
struct ExamNotesCard: View {
    let exam: Exam
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "note.text")
                    .font(.title3)
                    .foregroundStyle(Theme.color(for: exam))
                if exam.notes.isEmpty {
                    Text("Aggiungi note: programma, materiale, modalità d'esame…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text(exam.notes)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(exam.notes.isEmpty ? "Aggiungi note" : "Note: \(exam.notes)")
    }
}

/// Modifica delle note: si salva tutto insieme con "Salva", non a ogni tasto.
struct NotesEditorView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exam: Exam
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(exam: Exam) {
        self.exam = exam
        _text = State(initialValue: exam.notes)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                .padding()
                .background(Theme.background)
                .navigationTitle("Note di \(exam.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            store.setNotes(examID: exam.id, notes: text)
                            if store.lastError == nil { dismiss() }
                        }
                    }
                }
                .onAppear { isFocused = true }
        }
        .presentationBackground(Theme.background)
        .storeErrorAlert()
    }
}

/// Piano di studio automatico: argomenti distribuiti fino all'esame, con ripasso finale.
struct StudyPlanView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exam: Exam

    @State private var topicsText = ""
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var deadline: Date
    @State private var reviewDays = 2

    init(exam: Exam) {
        self.exam = exam
        let fallback = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        _deadline = State(initialValue: exam.isScheduled ? exam.date : fallback)
    }

    private var topics: [String] {
        topicsText.components(separatedBy: .newlines)
    }

    private var preview: [StudyTask] {
        StudyPlanner.plan(topics: topics, start: start, end: deadline, reviewDays: reviewDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Un argomento per riga, es.\nLimiti\nDerivate\nIntegrali", text: $topicsText, axis: .vertical)
                        .lineLimit(5...12)
                } header: {
                    Text("Argomenti").sectionHeaderStyle()
                }
                .listRowBackground(Theme.surface)

                Section {
                    DatePicker("Inizio", selection: $start, in: ...deadline, displayedComponents: .date)
                    if !exam.isScheduled {
                        DatePicker("Entro il", selection: $deadline, in: start..., displayedComponents: .date)
                    }
                    Stepper(value: $reviewDays, in: 0...14) {
                        HStack {
                            Text("Giorni di ripasso")
                            Spacer()
                            Text("\(reviewDays)")
                                .font(.ui(.body, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Periodo").sectionHeaderStyle()
                } footer: {
                    Text(exam.isScheduled
                         ? "Gli argomenti si distribuiscono fino all'esame, lasciando liberi gli ultimi giorni per il ripasso."
                         : "L'esame non ha una data: scegli entro quando finire.")
                }
                .listRowBackground(Theme.surface)

                if !preview.isEmpty {
                    Section {
                        ForEach(Array(preview.enumerated()), id: \.offset) { _, task in
                            LabeledContent(task.title, value: task.dueDate.italianShort)
                        }
                    } header: {
                        Text("Anteprima: \(preview.count) task").sectionHeaderStyle()
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedListBackground()
            .navigationTitle("Pianifica lo studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea task") {
                        for task in preview {
                            store.addTask(task, toExam: exam.id)
                        }
                        if store.lastError == nil { dismiss() }
                    }
                    .disabled(!topics.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
        }
        .presentationBackground(Theme.background)
        .storeErrorAlert()
    }
}
