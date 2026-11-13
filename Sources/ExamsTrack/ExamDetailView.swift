import SwiftUI
import ExamsCore

struct ExamDetailView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.today) private var today
    @Environment(TaskFocus.self) private var focus: TaskFocus?
    let examID: UUID
    /// Task appena raggiunto da un link del widget, evidenziato per un attimo.
    @State private var highlightedTaskID: UUID?

    @State private var showingEditExam = false
    @State private var showingNewTask = false
    @State private var editingTask: StudyTask?
    @State private var showingNotes = false
    @State private var showingPlanner = false

    /// Elemento della timeline: un task o il segnaposto di oggi.
    private enum TimelineItem: Identifiable {
        case task(StudyTask)
        case today

        var id: String {
            switch self {
            case .task(let task): task.id.uuidString
            case .today: "today"
            }
        }
    }

    var body: some View {
        if let exam = store.exam(id: examID) {
            content(for: exam)
        } else {
            ContentUnavailableView("Esame eliminato", systemImage: "trash")
        }
    }

    /// Scorre fino al task indicato dal widget e lo evidenzia per un paio di secondi.
    private func reveal(_ taskID: UUID?, in exam: Exam, proxy: ScrollViewProxy) async {
        guard let taskID, exam.tasks.contains(where: { $0.id == taskID }) else { return }
        // Lascia finire l'apertura del dettaglio, altrimenti lo scorrimento si perde.
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.snappy) {
            proxy.scrollTo(taskID.uuidString, anchor: .center)
            highlightedTaskID = taskID
        }
        try? await Task.sleep(for: .seconds(1.8))
        withAnimation(.easeOut(duration: 0.6)) { highlightedTaskID = nil }
        if focus?.taskID == taskID { focus?.taskID = nil }
    }

    private func timelineItems(for exam: Exam) -> [TimelineItem] {
        var items = exam.sortedTasks.map(TimelineItem.task)
        if let index = exam.todayMarkerIndex(today: today) {
            items.insert(.today, at: index)
        }
        return items
    }

    private func content(for exam: Exam) -> some View {
        let color = Theme.color(for: exam)
        let items = timelineItems(for: exam)

        return ScrollViewReader { proxy in
        List {
            Section {
                ExamCard(exam: exam, today: today, showsName: false)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            if !exam.isActive(today: today) {
                OutcomeSection(exam: exam)
            }

            Section {
                ExamNotesCard(exam: exam) { showingNotes = true }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            let overdue = exam.overdueCount(today: today)
            if overdue > 0 {
                Section {
                    RescheduleBanner(count: overdue) {
                        withAnimation { store.rescheduleOverdue(examID: exam.id, today: today) }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .task(let task):
                        TimelineRow(
                            task: task,
                            color: color,
                            isOverdue: task.isOverdue(today: today),
                            isFirst: index == 0,
                            onToggle: { store.toggleTask(id: task.id, inExam: exam.id) },
                            onEdit: { editingTask = task },
                            isHighlighted: highlightedTaskID == task.id,
                            onToggleSubtask: { subtaskID in
                                withAnimation(.snappy) {
                                    store.toggleSubtask(id: subtaskID, inTask: task.id, inExam: exam.id)
                                }
                            }
                        )
                        .taskContextMenu(examID: exam.id, task: task) { editingTask = task }
                        .swipeActions(edge: .trailing) {
                            Button("Elimina", role: .destructive) {
                                store.deleteTask(id: task.id, fromExam: exam.id)
                            }
                        }
                    case .today:
                        TodayMarkerRow(color: color, isFirst: index == 0, today: today)
                    }
                }
                ExamMilestoneRow(exam: exam, color: color, isFirst: items.isEmpty)
            } header: {
                HStack {
                    Text("Piano di studio").sectionHeaderStyle()
                    Spacer()
                    if exam.isActive(today: today) {
                        Button {
                            showingPlanner = true
                        } label: {
                            Label("Pianifica", systemImage: "wand.and.stars")
                                .font(.ui(.subheadline, weight: .semibold))
                        }
                        .tint(color)
                        .padding(.trailing, 8)
                    }
                    Button {
                        showingNewTask = true
                    } label: {
                        Label("Aggiungi task", systemImage: "plus")
                            .font(.ui(.subheadline, weight: .semibold))
                    }
                    .tint(color)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .task(id: focus?.taskID) { await reveal(focus?.taskID, in: exam, proxy: proxy) }
        }
        .listStyle(.plain)
        .themedListBackground()
        .floatingTabBarClearance()
        .readableContentWidth()
        .navigationTitle(exam.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica") { showingEditExam = true }
            }
        }
        .sheet(isPresented: $showingEditExam) {
            ExamFormView(exam: exam)
        }
        .sheet(isPresented: $showingNotes) {
            NotesEditorView(exam: exam)
        }
        .sheet(isPresented: $showingPlanner) {
            StudyPlanView(exam: exam)
        }
        .sheet(isPresented: $showingNewTask) {
            TaskFormView(examID: exam.id, examDate: exam.isScheduled ? exam.date : nil, task: nil)
        }
        .sheet(item: $editingTask) { task in
            TaskFormView(examID: exam.id, examDate: exam.isScheduled ? exam.date : nil, task: task)
        }
    }
}
