import Foundation
import Testing
@testable import ExamsCore

@Suite struct DaysRemainingTests {
    @Test func sameDayIsZero() {
        let exam = Exam(name: "A", date: date(2026, 11, 10, 9))
        #expect(exam.daysRemaining(today: date(2026, 11, 10, 23, 59), calendar: rome) == 0)
    }

    @Test func tomorrowJustAfterMidnightIsOne() {
        let exam = Exam(name: "A", date: date(2026, 11, 11, 0, 10))
        #expect(exam.daysRemaining(today: date(2026, 11, 10, 23, 30), calendar: rome) == 1)
    }

    @Test func pastIsNegative() {
        let exam = Exam(name: "A", date: date(2026, 11, 8))
        #expect(exam.daysRemaining(today: date(2026, 11, 10), calendar: rome) == -2)
    }

    @Test func acrossDaylightSavingChange() {
        // L'ora legale termina il 25/10/2026 a Roma.
        let exam = Exam(name: "A", date: date(2026, 10, 26, 9))
        #expect(exam.daysRemaining(today: date(2026, 10, 24, 12), calendar: rome) == 2)
    }

    @Test func activeIncludesToday() {
        let exam = Exam(name: "A", date: date(2026, 11, 10, 8))
        #expect(exam.isActive(today: date(2026, 11, 10, 20), calendar: rome))
        #expect(!exam.isActive(today: date(2026, 11, 11, 0, 1), calendar: rome))
    }
}

@Suite struct CountdownTests {
    @Test func labels() {
        #expect(Countdown.label(days: 0) == "Oggi")
        #expect(Countdown.label(days: 1) == "Domani")
        #expect(Countdown.label(days: 12) == "tra 12 giorni")
        #expect(Countdown.label(days: -3) == "Passato")
    }

    @Test func shortLabels() {
        #expect(Countdown.shortLabel(days: 0) == "Oggi")
        #expect(Countdown.shortLabel(days: 1) == "Domani")
        #expect(Countdown.shortLabel(days: 12) == "12 giorni")
    }

    @Test func compactLabels() {
        #expect(Countdown.compactLabel(days: 0) == "Oggi")
        #expect(Countdown.compactLabel(days: 1) == "1g")
        #expect(Countdown.compactLabel(days: 12) == "12g")
    }
}

@Suite struct ProgressTests {
    func exam(done: Int, total: Int) -> Exam {
        let tasks = (0..<total).map { i in
            StudyTask(title: "T\(i)", dueDate: date(2026, 11, 1), isDone: i < done)
        }
        return Exam(name: "A", date: date(2026, 11, 10), tasks: tasks)
    }

    @Test func noTasksIsZero() {
        #expect(exam(done: 0, total: 0).progress == 0)
        #expect(exam(done: 0, total: 0).progressPercent == 0)
    }

    @Test func roundsToNearestPercent() {
        #expect(exam(done: 1, total: 3).progressPercent == 33)
        #expect(exam(done: 2, total: 3).progressPercent == 67)
        #expect(exam(done: 2, total: 3).completedTaskCount == 2)
    }

    @Test func allDoneIsHundred() {
        #expect(exam(done: 4, total: 4).progress == 1)
        #expect(exam(done: 4, total: 4).progressPercent == 100)
    }
}

@Suite struct OverdueTests {
    let today = date(2026, 11, 10, 15)

    @Test func notDoneYesterdayIsOverdue() {
        #expect(StudyTask(title: "A", dueDate: date(2026, 11, 9)).isOverdue(today: today, calendar: rome))
    }

    @Test func doneYesterdayIsNotOverdue() {
        #expect(!StudyTask(title: "A", dueDate: date(2026, 11, 9), isDone: true).isOverdue(today: today, calendar: rome))
    }

    @Test func dueTodayIsNotOverdue() {
        #expect(!StudyTask(title: "A", dueDate: date(2026, 11, 10, 8)).isOverdue(today: today, calendar: rome))
    }
}

@Suite struct SortedTasksTests {
    @Test func sortsByDateThenTitle() {
        let exam = Exam(name: "A", date: date(2026, 11, 10), tasks: [
            StudyTask(title: "B", dueDate: date(2026, 11, 5)),
            StudyTask(title: "Dopo l'esame", dueDate: date(2026, 11, 20)),
            StudyTask(title: "A", dueDate: date(2026, 11, 5)),
            StudyTask(title: "C", dueDate: date(2026, 11, 1)),
        ])
        #expect(exam.sortedTasks.map(\.title) == ["C", "A", "B", "Dopo l'esame"])
    }
}

@Suite struct ListingTests {
    let today = date(2026, 11, 10)
    let past = Exam(name: "Passato", date: date(2026, 11, 1))
    let older = Exam(name: "Vecchio", date: date(2026, 10, 1))
    let todayExam = Exam(name: "Oggi", date: date(2026, 11, 10, 9))
    let laterB = Exam(name: "B", date: date(2026, 12, 1))
    let laterA = Exam(name: "A", date: date(2026, 12, 1))

    @Test func activeSortedByDateThenName() {
        let exams = [laterB, past, laterA, todayExam]
        #expect(exams.active(today: today, calendar: rome).map(\.name) == ["Oggi", "A", "B"])
    }

    @Test func archivedSortedByDateDescending() {
        let exams = [older, laterA, past]
        #expect(exams.archived(today: today, calendar: rome).map(\.name) == ["Passato", "Vecchio"])
    }

    @Test func nextExamIsNearestActive() {
        #expect([laterB, past, todayExam].nextExam(today: today, calendar: rome)?.name == "Oggi")
        #expect([laterB, laterA].nextExam(today: today, calendar: rome)?.name == "A")
    }

    @Test func noNextExamWhenAllPast() {
        #expect([past, older].nextExam(today: today, calendar: rome) == nil)
    }
}

@Suite struct OutcomeLabelTests {
    @Test func labels() {
        let d = date(2026, 11, 1)
        #expect(Exam(name: "A", date: d).outcomeLabel == "Esito da inserire")
        #expect(Exam(name: "A", date: d, passed: false).outcomeLabel == "Non superato")
        #expect(Exam(name: "A", date: d, passed: true).outcomeLabel == "Superato")
        #expect(Exam(name: "A", date: d, passed: true, grade: 28).outcomeLabel == "Superato 28")
        #expect(Exam(name: "A", date: d, passed: true, grade: 30, honors: true).outcomeLabel == "Superato 30L")
    }
}
