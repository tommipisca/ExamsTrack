import Foundation
import Testing
@testable import ExamsCore

@Suite struct NextExamSummaryTests {
    @Test func summarizesNearestActiveExam() {
        let exams = [
            Exam(name: "Fisica", date: date(2026, 12, 1)),
            Exam(name: "Analisi", date: date(2026, 11, 22), tasks: [
                StudyTask(title: "1", dueDate: date(2026, 11, 1), isDone: true),
                StudyTask(title: "2", dueDate: date(2026, 11, 2)),
            ]),
            Exam(name: "Vecchio", date: date(2026, 11, 1)),
        ]
        let summary = NextExamSummary.make(from: exams, today: date(2026, 11, 10), calendar: rome)
        #expect(summary?.name == "Analisi")
        #expect(summary?.daysRemaining == 12)
        #expect(summary?.progress == 0.5)
        #expect(summary?.progressPercent == 50)
    }

    @Test func examTodayAllDoneStaysUntilMidnight() {
        let exams = [
            Exam(name: "Oggi", date: date(2026, 11, 10, 9), tasks: [
                StudyTask(title: "1", dueDate: date(2026, 11, 9), isDone: true),
            ]),
            Exam(name: "Domani", date: date(2026, 11, 11)),
        ]
        let evening = NextExamSummary.make(from: exams, today: date(2026, 11, 10, 23, 59), calendar: rome)
        #expect(evening?.name == "Oggi")
        #expect(evening?.daysRemaining == 0)
        #expect(evening?.progressPercent == 100)

        let afterMidnight = NextExamSummary.make(from: exams, today: date(2026, 11, 11, 0, 0), calendar: rome)
        #expect(afterMidnight?.name == "Domani")
    }

    @Test func nilWhenNoActiveExams() {
        #expect(NextExamSummary.make(from: [], today: date(2026, 11, 10), calendar: rome) == nil)
        #expect(NextExamSummary.make(from: [Exam(name: "A", date: date(2026, 1, 1))], today: date(2026, 11, 10), calendar: rome) == nil)
    }
}

@Suite struct NextMidnightTests {
    @Test func isStartOfFollowingDay() {
        #expect(nextMidnight(after: date(2026, 11, 10, 15, 30), calendar: rome) == date(2026, 11, 11, 0, 0))
    }

    @Test func atExactMidnightReturnsNextOne() {
        #expect(nextMidnight(after: date(2026, 11, 10, 0, 0), calendar: rome) == date(2026, 11, 11, 0, 0))
    }

    @Test func acrossDaylightSavingChange() {
        #expect(nextMidnight(after: date(2026, 10, 25, 12), calendar: rome) == date(2026, 10, 26, 0, 0))
    }
}

@Suite struct SummaryTaskPresenceTests {
    @Test func reportsWhetherExamHasTasks() {
        let today = date(2026, 11, 10)
        let without = NextExamSummary.make(from: [Exam(name: "A", date: date(2026, 11, 20))], today: today, calendar: rome)
        #expect(without?.hasTasks == false)

        let with = NextExamSummary.make(from: [Exam(name: "A", date: date(2026, 11, 20), tasks: [
            StudyTask(title: "T", dueDate: date(2026, 11, 15)),
        ])], today: today, calendar: rome)
        #expect(with?.hasTasks == true)
    }
}

@Suite struct SummaryDetailsTests {
    @Test func includesDetailsAndNextOpenTask() throws {
        let today = date(2026, 11, 10)
        let exam = Exam(name: "Analisi 1", date: date(2026, 11, 24), tasks: [
            StudyTask(title: "Ripasso cap. 4", dueDate: date(2026, 11, 15)),
            StudyTask(title: "Limiti", dueDate: date(2026, 11, 1), isDone: true),
            StudyTask(title: "Esercizi", dueDate: date(2026, 11, 20)),
            StudyTask(title: "Arretrato", dueDate: date(2026, 11, 5)),
        ], degree: .magistrale)
        let summary = try #require(NextExamSummary.make(from: [exam], today: today, calendar: rome))
        #expect(summary.examDate == exam.date)
        #expect(summary.degree == .magistrale)
        #expect(summary.completedTasks == 1)
        #expect(summary.totalTasks == 4)
        #expect(summary.colorIndex == 0)
        // Il primo task non fatto in ordine di scadenza, anche se in ritardo.
        #expect(summary.nextTaskTitle == "Arretrato")
        #expect(summary.nextTaskDueDate == date(2026, 11, 5))
    }

    @Test func noNextTaskWhenAllDone() throws {
        let exam = Exam(name: "A", date: date(2026, 11, 24), tasks: [
            StudyTask(title: "T", dueDate: date(2026, 11, 1), isDone: true),
        ])
        let summary = try #require(NextExamSummary.make(from: [exam], today: date(2026, 11, 10), calendar: rome))
        #expect(summary.nextTaskTitle == nil)
        #expect(summary.nextTaskDueDate == nil)
    }
}

@Suite struct LargeWidgetSummaryTests {
    let today = date(2026, 11, 10)

    @Test func upcomingTasksAreOpenSortedAndCappedAtSix() throws {
        let exam = Exam(name: "Analisi", date: date(2026, 11, 24), tasks: [
            StudyTask(title: "G", dueDate: date(2026, 11, 23)),
            StudyTask(title: "F", dueDate: date(2026, 11, 22, 13)),
            StudyTask(title: "E", dueDate: date(2026, 11, 22)),
            StudyTask(title: "Fatto", dueDate: date(2026, 11, 1), isDone: true),
            StudyTask(title: "A", dueDate: date(2026, 11, 5)),
            StudyTask(title: "C", dueDate: date(2026, 11, 15)),
            StudyTask(title: "B", dueDate: date(2026, 11, 12)),
            StudyTask(title: "D", dueDate: date(2026, 11, 18)),
        ])
        let summary = try #require(NextExamSummary.make(from: [exam], today: today, calendar: rome))
        #expect(summary.upcomingTasks.map(\.title) == ["A", "B", "C", "D", "E", "F"])
        #expect(summary.upcomingTasks.map(\.isOverdue) == [true, false, false, false, false, false])
    }

    @Test func followingExamsAreNextScheduled() throws {
        let exams = [
            Exam(name: "Prossimo", date: date(2026, 11, 20)),
            Exam(name: "Terzo", date: date(2026, 12, 20), colorIndex: 4),
            Exam(name: "Senza data", date: date(2026, 1, 1), isScheduled: false),
            Exam(name: "Secondo", date: date(2026, 12, 1), colorIndex: 3),
            Exam(name: "Quarto", date: date(2027, 1, 10), tasks: [
                StudyTask(title: "T", dueDate: date(2026, 12, 1), isDone: true),
                StudyTask(title: "U", dueDate: date(2026, 12, 2)),
            ]),
            Exam(name: "Quinto", date: date(2027, 2, 1)),
            Exam(name: "Sesto", date: date(2027, 3, 1)),
        ]
        let summary = try #require(NextExamSummary.make(from: exams, today: today, calendar: rome))
        #expect(summary.followingExams.map(\.name) == ["Secondo", "Terzo", "Quarto", "Quinto", "Sesto"])
        #expect(summary.followingExams.prefix(2).map(\.daysRemaining) == [21, 40])
        #expect(summary.followingExams.prefix(2).map(\.colorIndex) == [3, 4])
        #expect(summary.followingExams[2].examDate == date(2027, 1, 10))
        #expect(summary.followingExams[2].progress == 0.5)
        #expect(summary.followingExams[2].hasTasks)
        #expect(!summary.followingExams[0].hasTasks)
    }

    @Test func upcomingTasksSpanAllActiveExams() throws {
        let exams = [
            Exam(name: "Prossimo", date: date(2026, 11, 20), tasks: [
                StudyTask(title: "P", dueDate: date(2026, 11, 14)),
            ]),
            Exam(name: "Dopo", date: date(2026, 12, 20), tasks: [
                StudyTask(title: "D", dueDate: date(2026, 11, 11)),
            ], colorIndex: 3),
            Exam(name: "Senza data", date: date(2026, 1, 1), tasks: [
                StudyTask(title: "S", dueDate: date(2026, 11, 9)),
            ], isScheduled: false),
            Exam(name: "Passato", date: date(2026, 11, 1), tasks: [
                StudyTask(title: "Vecchio", dueDate: date(2026, 10, 30)),
            ]),
        ]
        let summary = try #require(NextExamSummary.make(from: exams, today: today, calendar: rome))
        #expect(summary.name == "Prossimo")
        #expect(summary.upcomingTasks.map(\.title) == ["S", "D", "P"])
        #expect(summary.upcomingTasks.map(\.examName) == ["Senza data", "Dopo", "Prossimo"])
        #expect(summary.upcomingTasks[1].colorIndex == 3)
        #expect(summary.nextTaskTitle == "S")
        #expect(summary.nextTaskExamName == "Senza data")
    }

    @Test func followingExamsAreCapped() throws {
        let exams = (0...20).map { Exam(name: "E\($0)", date: date(2026, 11, 20 + $0)) }
        let summary = try #require(NextExamSummary.make(from: exams, today: today, calendar: rome))
        #expect(summary.followingExams.count == NextExamSummary.followingExamLimit)
    }

    @Test func emptyListsWhenNothingElse() throws {
        let summary = try #require(NextExamSummary.make(from: [Exam(name: "A", date: date(2026, 11, 20))], today: today, calendar: rome))
        #expect(summary.upcomingTasks.isEmpty)
        #expect(summary.followingExams.isEmpty)
    }
}
