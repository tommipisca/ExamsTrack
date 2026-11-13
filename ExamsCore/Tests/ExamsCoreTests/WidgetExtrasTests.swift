import Foundation
import Testing
@testable import ExamsCore

@Suite struct TodaySummaryTests {
    let today = date(2026, 11, 10, 15)

    let exams: [Exam] = [
            Exam(name: "Analisi", date: date(2026, 11, 20), tasks: [
                StudyTask(title: "Oggi A", dueDate: date(2026, 11, 10)),
                StudyTask(title: "Fatto oggi A", dueDate: date(2026, 11, 10), isDone: true),
                StudyTask(title: "Ritardo A", dueDate: date(2026, 11, 8)),
                StudyTask(title: "Ritardo fatto", dueDate: date(2026, 11, 7), isDone: true),
                StudyTask(title: "Domani A", dueDate: date(2026, 11, 11)),
            ]),
            Exam(name: "Fisica", date: date(2026, 12, 1), tasks: [
                StudyTask(title: "Oggi F", dueDate: date(2026, 11, 10)),
            ]),
    ]

    @Test func ordersOverdueThenOpenThenDone() {
        let summary = TodaySummary.make(from: exams, today: today, calendar: rome)
        #expect(summary.tasks.map(\.title) == ["Ritardo A", "Oggi A", "Oggi F", "Fatto oggi A"])
        #expect(summary.doneToday == 1)
        #expect(summary.totalToday == 3)
        #expect(summary.overdueCount == 1)
        #expect(summary.nextTask?.title == "Ritardo A")
    }

    @Test func keepsRecentlyCompletedOverdue() {
        let recent = exams[0].tasks[3].id
        let summary = TodaySummary.make(from: exams, today: today, recentlyCompleted: [recent], calendar: rome)
        #expect(summary.tasks.map(\.title).prefix(2) == ["Ritardo fatto", "Ritardo A"])
        #expect(summary.overdueCount == 1)
    }

    @Test func focusesOnOneExam() {
        let summary = TodaySummary.make(from: exams, today: today, focusedExamID: exams[1].id, calendar: rome)
        #expect(summary.tasks.map(\.title) == ["Oggi F"])
    }
}

@Suite struct FocusedSummaryTests {
    let today = date(2026, 11, 10)

    @Test func focusedExamReplacesNext() throws {
        let next = Exam(name: "Prossimo", date: date(2026, 11, 20), tasks: [StudyTask(title: "P", dueDate: date(2026, 11, 12))])
        let chosen = Exam(name: "Scelto", date: date(2026, 12, 20), tasks: [StudyTask(title: "S", dueDate: date(2026, 11, 13))])
        let summary = try #require(NextExamSummary.make(from: [next, chosen], today: today, focusedExamID: chosen.id,
                                                        tasksFromAllExams: false, calendar: rome))
        #expect(summary.name == "Scelto")
        #expect(summary.upcomingTasks.map(\.title) == ["S"])
        #expect(summary.followingExams.map(\.name) == ["Prossimo"])
    }

    @Test func focusedExamCanKeepAllTasks() throws {
        let next = Exam(name: "Prossimo", date: date(2026, 11, 20), tasks: [StudyTask(title: "P", dueDate: date(2026, 11, 12))])
        let chosen = Exam(name: "Scelto", date: date(2026, 12, 20), tasks: [StudyTask(title: "S", dueDate: date(2026, 11, 13))])
        let summary = try #require(NextExamSummary.make(from: [next, chosen], today: today, focusedExamID: chosen.id,
                                                        tasksFromAllExams: true, calendar: rome))
        #expect(summary.name == "Scelto")
        #expect(summary.upcomingTasks.map(\.title) == ["P", "S"])
    }

    @Test func automaticCanShowOnlyNextExamTasks() throws {
        let next = Exam(name: "Prossimo", date: date(2026, 11, 20), tasks: [StudyTask(title: "P", dueDate: date(2026, 11, 14))])
        let other = Exam(name: "Altro", date: date(2026, 12, 20), tasks: [StudyTask(title: "A", dueDate: date(2026, 11, 13))])
        let only = try #require(NextExamSummary.make(from: [next, other], today: today, tasksFromAllExams: false, calendar: rome))
        #expect(only.upcomingTasks.map(\.title) == ["P"])
        #expect(only.nextTaskTitle == "P")
        let all = try #require(NextExamSummary.make(from: [next, other], today: today, calendar: rome))
        #expect(all.upcomingTasks.map(\.title) == ["A", "P"])
    }

    @Test func fallsBackWhenFocusedExamIsGone() throws {
        let next = Exam(name: "Prossimo", date: date(2026, 11, 20))
        let past = Exam(name: "Passato", date: date(2026, 11, 1))
        let summary = try #require(NextExamSummary.make(from: [next, past], today: today, focusedExamID: past.id, calendar: rome))
        #expect(summary.name == "Prossimo")
        #expect(try #require(NextExamSummary.make(from: [next], today: today, focusedExamID: UUID(), calendar: rome)).name == "Prossimo")
    }
}

@Suite struct ExamActivityPlanTests {
    @Test func startsWithinLeadTimeAndLingersAfterStart() {
        let exam = Exam(name: "A", date: date(2026, 11, 10), startTime: 14 * 60)
        #expect(ExamActivityPlan.exam(in: [exam], now: date(2026, 11, 10, 5), calendar: rome) == nil)
        #expect(ExamActivityPlan.exam(in: [exam], now: date(2026, 11, 10, 6), calendar: rome)?.start == date(2026, 11, 10, 14))
        #expect(ExamActivityPlan.exam(in: [exam], now: date(2026, 11, 10, 14, 20), calendar: rome) != nil)
        #expect(ExamActivityPlan.exam(in: [exam], now: date(2026, 11, 10, 14, 30), calendar: rome) == nil)
    }

    @Test func needsStartTime() {
        let exam = Exam(name: "A", date: date(2026, 11, 10))
        #expect(ExamActivityPlan.exam(in: [exam], now: date(2026, 11, 10, 9), calendar: rome) == nil)
    }
}

@Suite struct CareerSummaryTests {
    @Test func averagesAndSimulation() {
        var simulated = Exam(name: "C", date: date(2026, 12, 1), cfu: 6)
        simulated.simulatedGrade = 30
        let exams = [
            Exam(name: "A", date: date(2026, 1, 10), passed: true, grade: 24, cfu: 6),
            Exam(name: "B", date: date(2026, 2, 10), passed: true, grade: 28, cfu: 12),
            simulated,
        ]
        let summary = CareerSummary.make(from: exams, degree: .triennale, thesis: .withReviewer)
        #expect(CareerSummary.averageText(summary.average) == "26,67")
        #expect(summary.earnedCFU == 18)
        #expect(summary.totalCFU == 180)
        #expect(CareerSummary.averageText(summary.simulatedAverage) == "27,50")
        #expect(summary.simulatedEstimate != nil)
        #expect(CareerSummary.make(from: Array(exams.prefix(2)), degree: .triennale, thesis: .withReviewer).simulatedAverage == nil)
    }

    @Test func automaticDegree() {
        let tri = [Exam(name: "A", date: date(2026, 1, 1))]
        #expect(CareerSummary.automaticDegree(exams: tri, visibility: .both) == .triennale)
        #expect(CareerSummary.automaticDegree(exams: tri + [Exam(name: "M", date: date(2026, 1, 1), degree: .magistrale)],
                                              visibility: .both) == .magistrale)
        #expect(CareerSummary.automaticDegree(exams: tri, visibility: .magistrale) == .magistrale)
    }

    @Test func gradeText() {
        #expect(CareerSummary.gradeText(GraduationEstimate(minimum: 98.2, maximum: 103.6, honorsThreshold: 113, canGetHonors: false)) == "98–104")
        #expect(CareerSummary.gradeText(GraduationEstimate(minimum: 111, maximum: 112, honorsThreshold: 113, canGetHonors: false)) == "110+")
    }
}

extension DefaultsBackedTests {
    @Suite struct StudySessionTests {
        @Test func pendingRequestIsConsumedAndExpires() {
            let name = "test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            let now = Date(timeIntervalSince1970: 10_000)
            #expect(!StudySession.takePendingRequest(from: defaults, now: now))
            StudySession.requestStart(in: defaults, at: now)
            #expect(StudySession.takePendingRequest(from: defaults, now: now.addingTimeInterval(5)))
            #expect(!StudySession.takePendingRequest(from: defaults, now: now.addingTimeInterval(6)))
            StudySession.requestStart(in: defaults, at: now)
            #expect(!StudySession.takePendingRequest(from: defaults, now: now.addingTimeInterval(600)))
        }

        @Test func lastDurationIsClampedAndOffered() {
            let name = "test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            #expect(StudySession.lastDuration(in: defaults) == 25)
            defaults.set(40, forKey: StudySession.lastDurationKey)
            #expect(StudySession.lastDuration(in: defaults) == 40)
            defaults.set(999, forKey: StudySession.lastDurationKey)
            #expect(StudySession.lastDuration(in: defaults) == 180)
            #expect(StudySession.menuDurations(last: 40) == [25, 40, 50])
            #expect(StudySession.menuDurations(last: 25) == [25, 50])
        }

        @Test func suggestsFirstTaskOfTodayThenNextExam() {
            let today = date(2026, 11, 10)
            let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [StudyTask(title: "Oggi", dueDate: today)])
            #expect(StudySession.suggestion(exams: [exam], today: today, calendar: rome)?.taskTitle == "Oggi")
        #expect(StudySession.suggestion(exams: [exam], today: today, calendar: rome)?.taskID == exam.tasks[0].id)
            let empty = Exam(name: "B", date: date(2026, 11, 20))
            let suggestion = StudySession.suggestion(exams: [empty], today: today, calendar: rome)
            #expect(suggestion?.examName == "B")
            #expect(suggestion?.taskTitle == nil)
        }
    }
}
