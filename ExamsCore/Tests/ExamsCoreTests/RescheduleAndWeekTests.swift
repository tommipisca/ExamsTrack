import Foundation
import Testing
@testable import ExamsCore

@Suite struct RescheduleOverdueTests {
    let today = date(2026, 11, 10, 15)

    @Test func spreadsOverdueFromTodayToDayBeforeExam() {
        let exam = Exam(name: "A", date: date(2026, 11, 14), tasks: [
            StudyTask(title: "R1", dueDate: date(2026, 11, 2)),
            StudyTask(title: "R2", dueDate: date(2026, 11, 5)),
            StudyTask(title: "Fatto", dueDate: date(2026, 11, 3), isDone: true),
            StudyTask(title: "R3", dueDate: date(2026, 11, 8)),
            StudyTask(title: "Futuro", dueDate: date(2026, 11, 12)),
        ])
        let tasks = StudyPlanner.rescheduleOverdue(exam, today: today, calendar: rome)
        let byTitle = Dictionary(uniqueKeysWithValues: tasks.map { ($0.title, $0.dueDate) })
        // Giorni disponibili: 10, 11, 12, 13.
        #expect(byTitle["R1"] == date(2026, 11, 10))
        #expect(byTitle["R2"] == date(2026, 11, 11))
        #expect(byTitle["R3"] == date(2026, 11, 12))
        // Quelli fatti o non in ritardo restano dove sono.
        #expect(byTitle["Fatto"] == date(2026, 11, 3))
        #expect(byTitle["Futuro"] == date(2026, 11, 12))
        #expect(tasks.map(\.id) == exam.tasks.map(\.id))
    }

    @Test func examTomorrowPutsEverythingToday() {
        let exam = Exam(name: "A", date: date(2026, 11, 11), tasks: [
            StudyTask(title: "R1", dueDate: date(2026, 11, 2)),
            StudyTask(title: "R2", dueDate: date(2026, 11, 5)),
        ])
        let tasks = StudyPlanner.rescheduleOverdue(exam, today: today, calendar: rome)
        #expect(tasks.allSatisfy { $0.dueDate == date(2026, 11, 10) })
    }

    @Test func unscheduledUsesNextSevenDays() {
        let exam = Exam(name: "A", date: date(2026, 1, 1), tasks: (1...7).map {
            StudyTask(title: "R\($0)", dueDate: date(2026, 11, $0))
        }, isScheduled: false)
        let tasks = StudyPlanner.rescheduleOverdue(exam, today: today, calendar: rome)
        #expect(tasks.map(\.dueDate) == (10...16).map { date(2026, 11, $0) })
    }

    @Test func overdueCount() {
        let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [
            StudyTask(title: "R", dueDate: date(2026, 11, 2)),
            StudyTask(title: "F", dueDate: date(2026, 11, 2), isDone: true),
        ])
        #expect(exam.overdueCount(today: today, calendar: rome) == 1)
    }
}

@MainActor
@Suite struct TaskMoveStoreTests {
    func makeStore() -> ExamStore {
        ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
    }

    @Test func moveTaskClampsToExamDay() {
        let store = makeStore()
        let task = StudyTask(title: "T", dueDate: date(2026, 11, 12))
        let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [task])
        store.addExam(exam)
        store.moveTask(id: task.id, inExam: exam.id, to: date(2026, 11, 15, 9))
        #expect(store.exam(id: exam.id)?.tasks.first?.dueDate == date(2026, 11, 15))
        store.moveTask(id: task.id, inExam: exam.id, to: date(2026, 12, 5))
        #expect(store.exam(id: exam.id)?.tasks.first?.dueDate == date(2026, 11, 20))
    }

    @Test func rescheduleOverdueInStore() {
        let store = makeStore()
        let exam = Exam(name: "A", date: date(2026, 12, 20), tasks: [StudyTask(title: "R", dueDate: date(2020, 1, 1))])
        store.addExam(exam)
        store.rescheduleOverdue(examID: exam.id, today: date(2026, 11, 10))
        #expect(store.exam(id: exam.id)?.tasks.first?.dueDate == date(2026, 11, 10))
    }
}

@Suite struct TodayWeekTests {
    let today = date(2026, 11, 10, 15)

    @Test func sevenDaysFromTomorrowAcrossExams() {
        let a = Exam(name: "A", date: date(2026, 11, 14), tasks: [
            StudyTask(title: "Domani", dueDate: date(2026, 11, 11)),
            StudyTask(title: "Fatto", dueDate: date(2026, 11, 12), isDone: true),
        ])
        let b = Exam(name: "B", date: date(2026, 12, 20), tasks: [
            StudyTask(title: "Dopo l'esame di A", dueDate: date(2026, 11, 16)),
            StudyTask(title: "Domani B", dueDate: date(2026, 11, 11)),
        ])
        let agenda = [a, b].agenda(today: today, calendar: rome)
        // Sette giorni anche oltre l'esame di A, anche quelli vuoti.
        #expect(agenda.days.map(\.date) == (11...17).map { date(2026, 11, $0) })
        #expect(agenda.days.map { $0.items.map(\.task.title) } ==
                [["Domani", "Domani B"], ["Fatto"], [], [], [], ["Dopo l'esame di A"], []])
        #expect(agenda.later.isEmpty)
    }

    @Test func tasksBeyondTheWeekGoToLater() {
        let exam = Exam(name: "A", date: date(2026, 12, 20), tasks: [
            StudyTask(title: "Tra due settimane", dueDate: date(2026, 11, 24)),
            StudyTask(title: "Fatto più avanti", dueDate: date(2026, 11, 25), isDone: true),
        ])
        let agenda = [exam].agenda(today: today, calendar: rome)
        #expect(agenda.days.count == 7)
        #expect(agenda.later.map(\.task.title) == ["Tra due settimane"])
    }
}
