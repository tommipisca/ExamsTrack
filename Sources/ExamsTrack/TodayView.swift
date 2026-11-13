import SwiftUI
import ExamsCore

/// Scheda "Oggi": prossimo esame e task di tutti gli esami: in ritardo, di oggi, dei prossimi giorni e più avanti.
struct TodayView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.today) private var today
    @Environment(\.degreeVisibility) private var visibility
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editTarget: TaskEditTarget?
    @State private var showingQuickAdd = false

    var body: some View {
        if sizeClass == .regular {
            // iPad con spazio in larghezza: due colonne, come il widget gigante.
            NavigationStack {
                TodayBoardView()
            }
            .storeErrorAlert()
        } else {
            compactBody
        }
    }

    private func edit(_ item: AgendaItem) {
        let exam = store.exam(id: item.examID)
        editTarget = TaskEditTarget(examID: item.examID, examDate: exam?.isScheduled == true ? exam?.date : nil, task: item.task)
    }

    @ViewBuilder
    private var compactBody: some View {
        let exams = store.exams.visible(visibility)
        let next = exams.nextExam(today: today)
        let agenda = exams.agenda(today: today)

        NavigationStack {
            List {
                StudySessionSection()

                if let next {
                    Section {
                        // Link invisibile sotto il riquadro: niente freccia, tutto il riquadro è toccabile.
                        ZStack {
                            NavigationLink(value: next.id) { EmptyView() }
                                .opacity(0)
                            ExamCard(exam: next, today: today)
                        }
                        // Nessun margine orizzontale: la lista raggruppata rientra già la riga,
                        // così il riquadro è largo quanto le altre righe.
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Prossimo esame").sectionHeaderStyle()
                    }
                }

                if !agenda.overdue.isEmpty {
                    Section {
                        ForEach(agenda.overdue) { AgendaRow(item: $0, isOverdue: true) { edit($0) } }
                    } header: {
                        HStack {
                            Text("In ritardo").sectionHeaderStyle()
                            Spacer()
                            Button {
                                // Ridistribuisce i ritardi di ogni esame da oggi fino al suo esame.
                                let examIDs = Set(agenda.overdue.map(\.examID))
                                withAnimation {
                                    for examID in examIDs { store.rescheduleOverdue(examID: examID, today: today) }
                                }
                            } label: {
                                Label("Ripianifica", systemImage: "clock.arrow.circlepath")
                                    .font(.ui(.subheadline, weight: .semibold))
                                    .textCase(nil)
                            }
                            .tint(Theme.danger)
                        }
                    }
                }

                Section {
                    if agenda.dueToday.isEmpty {
                        Label("Niente in scadenza oggi", systemImage: "checkmark.seal")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(agenda.dueToday) { AgendaRow(item: $0, isOverdue: false) { edit($0) } }
                } header: {
                    Text("Da fare oggi").sectionHeaderStyle()
                }

                // Solo i giorni con qualcosa: su iPhone non si trascina, i giorni vuoti non servono.
                ForEach(agenda.days.filter { !$0.items.isEmpty }) { day in
                    Section {
                        ForEach(day.items) { AgendaRow(item: $0, isOverdue: false) { edit($0) } }
                    } header: {
                        Text(day.date.agendaDayLabel(today: today)).sectionHeaderStyle()
                    }
                }

                if !agenda.later.isEmpty {
                    Section {
                        ForEach(agenda.later) { AgendaRow(item: $0, isOverdue: false, showsDate: true) { edit($0) } }
                    } header: {
                        Text("Più avanti").sectionHeaderStyle()
                    }
                }
            }
            .tabScreenStyle()
            .navigationTitle("Oggi")
            .toolbar { TodayToolbar(showingQuickAdd: $showingQuickAdd) }
            .sheet(item: $editTarget) { target in
                TaskFormView(examID: target.examID, examDate: target.examDate, task: target.task)
            }
            .sheet(isPresented: $showingQuickAdd) { QuickAddTaskView() }
        }
        .storeErrorAlert()
    }
}

/// Task in agenda: si spunta dal cerchio, si apre l'esame toccando il resto della riga.
private struct AgendaRow: View {
    @Environment(ExamStore.self) private var store
    let item: AgendaItem
    let isOverdue: Bool
    var showsDate = false
    let onEdit: (AgendaItem) -> Void

    var body: some View {
        let color = Theme.color(index: item.colorIndex)

        NavigationLink(value: item.examID) {
            HStack(spacing: 12) {
                Button {
                    store.toggleTask(id: item.task.id, inExam: item.examID)
                } label: {
                    Image(systemName: item.task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isOverdue ? Theme.danger : color)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .sensoryFeedback(.success, trigger: item.task.isDone) { _, isDone in isDone }
                .accessibilityLabel(item.task.isDone ? "Segna come da fare" : "Segna come fatto")

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.task.title)
                        .strikethrough(item.task.isDone, color: Theme.textSecondary)
                        .foregroundStyle(item.task.isDone ? Theme.textSecondary : Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(item.examName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(color)
                        if let label = item.task.subtaskLabel {
                            Label(label, systemImage: "checklist")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if isOverdue {
                            Text("scadeva il \(item.task.dueDate.italianShort)")
                                .font(.footnote)
                                .foregroundStyle(Theme.danger)
                        } else if showsDate {
                            Text(item.task.dueDate.italianShort)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Theme.surface)
        .taskContextMenu(examID: item.examID, task: item.task) { onEdit(item) }
        .taskSwipeActions(examID: item.examID, task: item.task)
    }
}
