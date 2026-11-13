import SwiftUI
import ExamsCore

/// Pulsanti di "Oggi": nuovo task al volo e sessione di studio sul prossimo task.
struct TodayToolbar: ToolbarContent {
    @Environment(ExamStore.self) private var store
    @Environment(StudySessionController.self) private var study
    @Environment(\.degreeVisibility) private var visibility
    @Binding var showingQuickAdd: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let target = study.suggestedTarget(exams: store.exams.visible(visibility)) {
                StudyDurationMenu(target: target, header: "Sul prossimo task di oggi")
            }

            Button {
                showingQuickAdd = true
            } label: {
                Label("Nuovo task", systemImage: "plus")
            }
            .disabled(store.exams.visible(visibility).active(today: .now).isEmpty)
        }
    }
}

/// "Sessione di studio": le durate fisse, l'ultima usata e "Altra durata…" con il selettore.
struct StudyDurationMenu: View {
    @Environment(StudySessionController.self) private var study
    let target: StudySessionController.Target
    var header: String?

    var body: some View {
        Menu {
            Section(header ?? target.taskTitle ?? target.examName) {
                ForEach(StudySession.menuDurations(last: study.lastMinutes), id: \.self) { minutes in
                    Button("\(minutes) minuti") {
                        Task { await study.start(target, minutes: minutes) }
                    }
                }
                Button {
                    study.durationRequest = target
                } label: {
                    Label("Altra durata…", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Label("Sessione di studio", systemImage: "timer")
        }
    }
}

/// Selettore della durata di una sessione: ruota a passi di 5 minuti, da 5 a 180.
struct StudyDurationSheet: View {
    @Environment(StudySessionController.self) private var study
    @Environment(\.dismiss) private var dismiss
    let target: StudySessionController.Target
    @State private var minutes: Int

    init(target: StudySessionController.Target, initialMinutes: Int) {
        self.target = target
        // Arrotondata ai 5 minuti della ruota.
        _minutes = State(initialValue: max(StudySession.range.lowerBound, (initialMinutes + 2) / 5 * 5))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(target.taskTitle ?? target.examName)
                    .font(.ui(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                if target.taskTitle != nil {
                    Text(target.examName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.color(index: target.colorIndex))
                }
                Picker("Durata", selection: $minutes) {
                    ForEach(Array(stride(from: StudySession.range.lowerBound, through: StudySession.range.upperBound, by: 5)),
                            id: \.self) { value in
                        Text(Self.label(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle("Sessione di studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Avvia") {
                        Task { await study.start(target, minutes: minutes) }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
    }

    /// "45 minuti", "1 ora e 30 minuti".
    static func label(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        guard hours > 0 else { return "\(minutes) minuti" }
        let hourText = hours == 1 ? "1 ora" : "\(hours) ore"
        return rest == 0 ? hourText : "\(hourText) e \(rest) minuti"
    }
}

/// Nuovo task scegliendo l'esame al volo; scadenza oggi.
struct QuickAddTaskView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.today) private var today
    @Environment(\.degreeVisibility) private var visibility

    @State private var examID: UUID?
    @State private var title = ""
    @State private var dueDate = Date.now

    private var exams: [Exam] { store.exams.visible(visibility).active(today: today) }
    private var selectedExam: Exam? { exams.first { $0.id == examID } }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Esame", selection: $examID) {
                        ForEach(exams) { exam in
                            Text(exam.name).tag(Optional(exam.id))
                        }
                    }
                    TextField("Cosa devi fare, es. Ripasso capitoli 1-3", text: $title)
                    if let examDate = selectedExam.flatMap({ $0.isScheduled ? $0.date : nil }) {
                        DatePicker("Entro il", selection: $dueDate, in: ...examDate, displayedComponents: .date)
                    } else {
                        DatePicker("Entro il", selection: $dueDate, displayedComponents: .date)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .themedListBackground()
            .navigationTitle("Nuovo task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(trimmedTitle.isEmpty || selectedExam == nil)
                }
            }
            .onAppear {
                // Proposto il prossimo esame, altrimenti il primo da sostenere.
                if examID == nil {
                    examID = (exams.nextExam(today: today) ?? exams.first)?.id
                }
                dueDate = today
            }
            .onChange(of: examID) {
                // Scadenza mai oltre il giorno dell'esame.
                if let exam = selectedExam, exam.isScheduled, dueDate > exam.date { dueDate = exam.date }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
        .storeErrorAlert()
    }

    private func save() {
        guard let examID else { return }
        store.addTask(StudyTask(title: trimmedTitle, dueDate: dueDate), toExam: examID)
        if store.lastError == nil { dismiss() }
    }
}

/// La sessione di studio in corso: timer e pulsante per terminarla.
private struct StudySessionContent: View {
    @Environment(StudySessionController.self) private var study
    let session: StudySessionController.Session

    var body: some View {
        let color = Theme.color(index: session.colorIndex)
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle ?? "Sessione di studio")
                    .font(.ui(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(session.examName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 8)
            if session.end > .now {
                Text(timerInterval: Date.now...session.end, countsDown: true)
                    .font(.ui(.title3, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(minWidth: 64, alignment: .trailing)
            } else {
                Text("Finita")
                    .font(.ui(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.success)
            }
            Button("Termina") {
                Task { await study.stop() }
            }
            .font(.ui(.subheadline, weight: .semibold))
            .buttonStyle(.bordered)
            .tint(color)
        }
        // Alla fine del timer la sessione esce da "Oggi" (la notifica avvisa anche ad app chiusa).
        .task(id: session.end) {
            let remaining = session.end.timeIntervalSinceNow
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining + 1)) }
            guard !Task.isCancelled else { return }
            await study.refresh()
        }
    }
}

/// Su iPhone: sezione in cima alla lista di "Oggi".
struct StudySessionSection: View {
    @Environment(StudySessionController.self) private var study

    var body: some View {
        if let session = study.current {
            Section {
                StudySessionContent(session: session)
                    .listRowBackground(Theme.surface)
            } header: {
                Text("Sessione di studio").sectionHeaderStyle()
            }
        }
    }
}

/// Su iPad: riquadro in cima alla colonna sinistra.
struct StudySessionCard: View {
    @Environment(StudySessionController.self) private var study

    var body: some View {
        if let session = study.current {
            StudySessionContent(session: session)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }
}
