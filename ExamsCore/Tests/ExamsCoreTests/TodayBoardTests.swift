import Foundation
import Testing
@testable import ExamsCore

@Suite struct TodayBoardTests {
    let today = date(2026, 11, 10, 15)

    var exams: [Exam] {
        [
            Exam(name: "Analisi", date: date(2026, 11, 20), tasks: [
                StudyTask(title: "Oggi A", dueDate: date(2026, 11, 10)),
                StudyTask(title: "Ritardo A", dueDate: date(2026, 11, 8)),
                StudyTask(title: "Fatto oggi A", dueDate: date(2026, 11, 10), isDone: true),
                StudyTask(title: "Domani A", dueDate: date(2026, 11, 11)),
                StudyTask(title: "Dopo A", dueDate: date(2026, 11, 15)),
            ]),
            Exam(name: "Fisica", date: date(2026, 12, 1), tasks: [
                StudyTask(title: "Oggi F", dueDate: date(2026, 11, 10)),
                StudyTask(title: "Futuro F", dueDate: date(2026, 11, 25)),
            ]),
            Exam(name: "Chimica", date: date(2026, 12, 20), tasks: [
                StudyTask(title: "Futuro C", dueDate: date(2026, 11, 30)),
            ]),
            Exam(name: "Senza data", date: date(2026, 1, 1), tasks: [
                StudyTask(title: "Ritardo S", dueDate: date(2026, 11, 1)),
            ], isScheduled: false),
        ]
    }

    @Test func agendaSpansAllExams() throws {
        let board = TodayBoard.make(exams: exams, today: today, calendar: rome)
        #expect(board.next?.name == "Analisi")
        #expect(board.agenda.overdue.map(\.task.title) == ["Ritardo S", "Ritardo A"])
        // Prima quelli da fare (per esame), poi quelli già fatti.
        #expect(board.agenda.dueToday.map(\.task.title) == ["Oggi A", "Oggi F", "Fatto oggi A"])
        #expect(board.agenda.days.first?.items.map(\.task.title) == ["Domani A"])
        #expect(board.agenda.days.flatMap(\.items).map(\.task.title) == ["Domani A", "Dopo A"])
        #expect(board.agenda.later.map(\.task.title) == ["Futuro F", "Futuro C"])
    }

    @Test func rightColumnListsOtherActiveExams() {
        let board = TodayBoard.make(exams: exams, today: today, calendar: rome)
        // Anche senza nulla da fare oggi; l'esame da programmare va in fondo.
        #expect(board.others.map(\.name) == ["Fisica", "Chimica", "Senza data"])
    }

    @Test func noScheduledExams() {
        let board = TodayBoard.make(exams: [exams[3]], today: today, calendar: rome)
        #expect(board.next == nil)
        #expect(board.others.map(\.name) == ["Senza data"])
        #expect(board.agenda.overdue.map(\.task.title) == ["Ritardo S"])
    }
}
