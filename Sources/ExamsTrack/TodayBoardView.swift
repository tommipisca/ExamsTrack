import SwiftUI
import ExamsCore

/// "Oggi" su iPad: a sinistra (più larga) il prossimo esame e l'agenda di tutti gli esami (oggi in grande,
/// i prossimi 7 giorni e più avanti in piccolo); a destra (più stretta, scorre da sola) gli altri esami.
struct TodayBoardView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.today) private var today
    @Environment(\.degreeVisibility) private var visibility
    @State private var editTarget: TaskEditTarget?
    @State private var showingQuickAdd = false
    /// Giorno su cui si sta trascinando un task, per evidenziarlo.
    @State private var dropTarget: Date?

    var body: some View {
        let board = TodayBoard.make(exams: store.exams.visible(visibility), today: today)

        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    leftColumn(board)
                        .padding(.vertical, 8)
                }
                .frame(width: (proxy.size.width - 24) * 0.6)

                ScrollView {
                    rightColumn(board)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
        }
        .floatingTabBarClearance()
        .syncRefreshable()
        .background(Theme.background)
        .navigationTitle("Oggi")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar { TodayToolbar(showingQuickAdd: $showingQuickAdd) }
        .sheet(isPresented: $showingQuickAdd) { QuickAddTaskView() }
        .navigationDestination(for: UUID.self) { ExamDetailView(examID: $0) }
        .sheet(item: $editTarget) { target in
            TaskFormView(examID: target.examID, examDate: target.examDate, task: target.task)
        }
    }

    private func edit(_ item: AgendaItem) {
        let exam = store.exam(id: item.examID)
        editTarget = TaskEditTarget(examID: item.examID, examDate: exam?.isScheduled == true ? exam?.date : nil, task: item.task)
    }

    private func row(_ item: AgendaItem, isLarge: Bool, showsDate: Bool = false) -> some View {
        BoardTaskRow(item: item, color: Theme.color(index: item.colorIndex), isLarge: isLarge,
                     isOverdue: item.task.isOverdue(today: today), showsDate: showsDate)
            .taskContextMenu(examID: item.examID, task: item.task) { edit(item) }
            .draggable(TaskDragPayload.encode(examID: item.examID, taskID: item.task.id))
    }

    /// Lascia un task trascinato su un giorno: lo sposta a quel giorno.
    private func drop(_ payloads: [String], on day: Date) -> Bool {
        var moved = false
        for payload in payloads {
            guard let (examID, taskID) = TaskDragPayload.decode(payload) else { continue }
            withAnimation(.snappy) { store.moveTask(id: taskID, inExam: examID, to: day) }
            moved = true
        }
        return moved
    }

    // MARK: Sinistra: prossimo esame e agenda

    @ViewBuilder
    private func leftColumn(_ board: TodayBoard) -> some View {
        let agenda = board.agenda
        VStack(alignment: .leading, spacing: 20) {
            StudySessionCard()

            if let next = board.next {
                NavigationLink(value: next.id) {
                    ExamCard(exam: next, today: today)
                }
                .buttonStyle(.plain)
            } else {
                emptyCard("Nessun esame in programma: aggiungi la data a un esame nella scheda Esami.")
            }

            if !agenda.overdue.isEmpty {
                RescheduleBanner(count: agenda.overdue.count) {
                    // Ridistribuisce i ritardi di ogni esame da oggi fino al suo esame.
                    withAnimation {
                        for examID in Set(agenda.overdue.map(\.examID)) {
                            store.rescheduleOverdue(examID: examID, today: today)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Da fare oggi").sectionHeaderStyle()
                let todays = agenda.overdue + agenda.dueToday
                Group {
                    if todays.isEmpty {
                        emptyCard("Niente in scadenza oggi.")
                    } else {
                        card {
                            ForEach(Array(todays.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { divider }
                                row(item, isLarge: true)
                            }
                        }
                    }
                }
                .overlay { dropHighlight(dropTarget == todayKey) }
                .dropDestination(for: String.self) { payloads, _ in
                    drop(payloads, on: today)
                } isTargeted: { targeted in
                    updateDropTarget(todayKey, targeted)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Questa settimana").sectionHeaderStyle()
                ForEach(agenda.days) { day in
                    daySlot(day, exams: ([board.next].compactMap { $0 } + board.others))
                }
            }

            if !agenda.later.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Più avanti").sectionHeaderStyle()
                    card {
                        ForEach(Array(agenda.later.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { divider }
                            row(item, isLarge: false, showsDate: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Destra: gli altri esami

    private func rightColumn(_ board: TodayBoard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prossimi esami").sectionHeaderStyle()
            if board.others.isEmpty {
                emptyCard("Nessun altro esame da sostenere.")
            }
            ForEach(board.others) { exam in
                let color = Theme.color(for: exam)
                card {
                    NavigationLink(value: exam.id) {
                        HStack(spacing: 10) {
                            ColorBar(color: color)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exam.name)
                                    .font(.examName(.headline))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if !exam.tasks.isEmpty {
                                    ProgressView(value: exam.progress)
                                        .tint(color)
                                }
                            }
                            Spacer(minLength: 6)
                            if exam.isScheduled {
                                let days = exam.daysRemaining(today: today)
                                CountdownText(days: days, color: Theme.countdownColor(days: days, examColor: color),
                                              isLarge: false)
                                    .fixedSize()
                            } else {
                                Text("Da programmare")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize()
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Settimana e trascinamento

    private var todayKey: Date { Calendar.current.startOfDay(for: today) }

    private func updateDropTarget(_ key: Date, _ targeted: Bool) {
        if targeted {
            dropTarget = key
        } else if dropTarget == key {
            dropTarget = nil
        }
    }

    private func dropHighlight(_ isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.accent, lineWidth: isActive ? 2 : 0)
            .animation(.snappy, value: isActive)
    }

    /// Un giorno della settimana: gli esami e i task di quel giorno. Un giorno libero è una riga sottile
    /// (resta un punto di arrivo per trascinarci un task), così sette giorni vuoti non riempiono la colonna.
    private func daySlot(_ day: AgendaDay, exams: [Exam]) -> some View {
        let examsThatDay = exams.filter { $0.isScheduled && Calendar.current.isDate(day.date, inSameDayAs: $0.date) }
        let isFree = day.items.isEmpty && examsThatDay.isEmpty
        let isTarget = dropTarget == day.date
        let header = HStack(spacing: 8) {
            Text(day.date.agendaDayLabel(today: today))
                .font(.ui(.footnote, weight: .semibold))
                .foregroundStyle(isFree ? Theme.textSecondary : Theme.textPrimary)
            ForEach(examsThatDay) { exam in
                Label("Esame: \(exam.name)", systemImage: "graduationcap.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.color(for: exam))
                    .lineLimit(1)
            }
            Spacer()
            if isFree {
                Text(isTarget ? "Lascia qui" : "Libero")
                    .font(.caption)
                    .foregroundStyle(isTarget ? Theme.accent : Theme.textSecondary.opacity(0.7))
            }
        }

        return Group {
            if isFree {
                header
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
            } else {
                card {
                    header
                        .padding(.top, 8)
                        .padding(.bottom, day.items.isEmpty ? 8 : 2)
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { divider }
                        row(item, isLarge: false)
                    }
                }
            }
        }
        .overlay { dropHighlight(isTarget) }
        .dropDestination(for: String.self) { payloads, _ in
            drop(payloads, on: day.date)
        } isTargeted: { targeted in
            updateDropTarget(day.date, targeted)
        }
    }

    // MARK: Elementi comuni

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private func emptyCard(_ text: String) -> some View {
        card {
            Label(text, systemImage: "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 12)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
    }
}

/// Un task da spuntare, con l'esame a cui appartiene: grande per oggi, piccolo per gli altri giorni.
/// Il cerchio spunta il task, il resto della riga apre l'esame.
private struct BoardTaskRow: View {
    @Environment(ExamStore.self) private var store
    let item: AgendaItem
    let color: Color
    let isLarge: Bool
    let isOverdue: Bool
    var showsDate = false

    private var task: StudyTask { item.task }

    var body: some View {
        HStack(spacing: isLarge ? 14 : 10) {
            Button {
                store.toggleTask(id: task.id, inExam: item.examID)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(isLarge ? .title : .title3)
                    .foregroundStyle(isOverdue ? Theme.danger : color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: task.isDone) { _, isDone in isDone }
            .accessibilityLabel(task.isDone ? "Segna come da fare" : "Segna come fatto")

            NavigationLink(value: item.examID) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(isLarge ? .ui(.title3, weight: .semibold) : .subheadline)
                            .strikethrough(task.isDone, color: Theme.textSecondary)
                            .foregroundStyle(task.isDone ? Theme.textSecondary : Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(item.examName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color)
                            if let label = task.subtaskLabel {
                                Label(label, systemImage: "checklist")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if isOverdue {
                                Text("in ritardo, scadeva il \(task.dueDate.italianShort)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    if showsDate {
                        Text(task.dueDate.italianShort)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, isLarge ? 14 : 9)
    }
}
