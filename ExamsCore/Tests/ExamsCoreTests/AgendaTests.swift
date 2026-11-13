import Foundation
import Testing
@testable import ExamsCore

@Suite struct AgendaTests {
    let today = date(2026, 11, 10, 15)

    @Test func splitsOverdueAndDueToday() {
        let analisi = Exam(name: "Analisi", date: date(2026, 11, 30), tasks: [
            StudyTask(title: "Vecchio", dueDate: date(2026, 11, 8)),
            StudyTask(title: "Vecchio fatto", dueDate: date(2026, 11, 7), isDone: true),
            StudyTask(title: "Oggi", dueDate: date(2026, 11, 10)),
            StudyTask(title: "Oggi fatto", dueDate: date(2026, 11, 10, 9), isDone: true),
            StudyTask(title: "Domani", dueDate: date(2026, 11, 11)),
        ])
        let agenda = [analisi].agenda(today: today, calendar: rome)
        #expect(agenda.overdue.map(\.task.title) == ["Vecchio"])
        #expect(agenda.dueToday.map(\.task.title).sorted() == ["Oggi", "Oggi fatto"])
        #expect(agenda.overdue.first?.examID == analisi.id)
    }

    @Test func ignoresPastExams() {
        let past = Exam(name: "Passato", date: date(2026, 11, 1), tasks: [
            StudyTask(title: "Mai fatto", dueDate: date(2026, 10, 20)),
        ])
        #expect([past].agenda(today: today, calendar: rome).overdue.isEmpty)
    }

    @Test func includesUnscheduledExams() {
        let unscheduled = Exam(name: "Fisica", date: date(2026, 1, 1), tasks: [
            StudyTask(title: "Oggi", dueDate: date(2026, 11, 10)),
        ], isScheduled: false)
        #expect([unscheduled].agenda(today: today, calendar: rome).dueToday.count == 1)
    }

    @Test func overdueSortedByDueDateThenExamName() {
        let b = Exam(name: "B", date: date(2026, 12, 1), tasks: [StudyTask(title: "b", dueDate: date(2026, 11, 5))])
        let a = Exam(name: "A", date: date(2026, 12, 1), tasks: [
            StudyTask(title: "a2", dueDate: date(2026, 11, 5)),
            StudyTask(title: "a1", dueDate: date(2026, 11, 2)),
        ])
        #expect([b, a].agenda(today: today, calendar: rome).overdue.map(\.task.title) == ["a1", "a2", "b"])
    }

    @Test func emptyWhenNothingDue() {
        let agenda = [Exam(name: "A", date: date(2026, 12, 1))].agenda(today: today, calendar: rome)
        #expect(agenda.isEmpty)
    }
}
