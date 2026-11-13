import Foundation
import Testing
@testable import ExamsCore

// MARK: 1. Note

@Suite struct NotesTests {
    @Test func oldDataHasEmptyNotes() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"A","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([Exam].self, from: Data(json.utf8)).first?.notes == "")
    }
}

@MainActor
@Suite struct NotesStoreTests {
    @Test func setNotesTrimsAndSaves() {
        let store = ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        store.addExam(exam)
        store.setNotes(examID: exam.id, notes: "  Orale + scritto\n")
        #expect(store.exam(id: exam.id)?.notes == "Orale + scritto")
    }
}

// MARK: 2. Ordinamento della carriera

@Suite struct CareerSortTests {
    let a = Exam(name: "Analisi", date: date(2026, 1, 10), passed: true, grade: 24, cfu: 10)
    let b = Exam(name: "Basi", date: date(2026, 3, 10), passed: true, grade: 30, honors: true, cfu: 5)
    let c = Exam(name: "Chimica", date: date(2026, 2, 10), passed: true, grade: 30, cfu: 12)
    let d = Exam(name: "Da inserire", date: date(2026, 4, 10), cfu: 6)

    @Test func byDateNewestFirst() {
        #expect([a, b, c, d].sortedForCareer(by: .date).map(\.name) == ["Da inserire", "Basi", "Chimica", "Analisi"])
    }

    @Test func byGradeWithHonorsAboveThirtyAndUngradedLast() {
        #expect([a, b, c, d].sortedForCareer(by: .grade).map(\.name) == ["Basi", "Chimica", "Analisi", "Da inserire"])
    }

    @Test func byCFUThenName() {
        #expect([a, b, c, d].sortedForCareer(by: .cfu).map(\.name) == ["Chimica", "Analisi", "Da inserire", "Basi"])
    }
}

// MARK: 3. Form: solo i campi modificati

@Suite struct ExamDetailsMergeTests {
    let original = ExamDetails(name: "Analisi", date: date(2026, 12, 1), degree: .triennale, cfu: 6,
                               isFinalTest: false, isScheduled: true, startTime: nil)

    @Test func keepsRemoteChangesToUntouchedFields() {
        var edited = original
        edited.name = "Analisi 1"
        var latest = original
        latest.date = date(2026, 12, 15)   // cambiata sull'altro dispositivo mentre il form era aperto
        let result = ExamDetails.merging(original: original, edited: edited, latest: latest)
        #expect(result.name == "Analisi 1")
        #expect(result.date == date(2026, 12, 15))
    }

    @Test func formWinsOnFieldsItChanged() {
        var edited = original
        edited.cfu = 9
        var latest = original
        latest.cfu = 12
        #expect(ExamDetails.merging(original: original, edited: edited, latest: latest).cfu == 9)
    }

    @Test func thesisDefaultCFU() {
        #expect(Exam.thesisCFU == 20)
    }
}

// MARK: 4. Piano di studio

@Suite struct StudyPlannerTests {
    @Test func spreadsTopicsEvenlyAndAddsReview() {
        // Dal 1 al 10 novembre, esame il 13: 2 giorni di ripasso → studio dal 1 al 10 (10 giorni).
        let tasks = StudyPlanner.plan(
            topics: ["Limiti", "Derivate", "Integrali", "Serie", "Equazioni"],
            start: date(2026, 11, 1), end: date(2026, 11, 13), reviewDays: 2, calendar: rome
        )
        #expect(tasks.map(\.title) == ["Limiti", "Derivate", "Integrali", "Serie", "Equazioni", "Ripasso generale"])
        #expect(tasks.map(\.dueDate) == [
            date(2026, 11, 2), date(2026, 11, 4), date(2026, 11, 6), date(2026, 11, 8), date(2026, 11, 10),
            date(2026, 11, 12),
        ])
    }

    @Test func ignoresBlankLinesAndTrims() {
        let tasks = StudyPlanner.plan(topics: ["  Limiti ", "", "   "], start: date(2026, 11, 1),
                                      end: date(2026, 11, 5), reviewDays: 0, calendar: rome)
        #expect(tasks.map(\.title) == ["Limiti"])
    }

    @Test func tooLittleTimeStacksOnStart() {
        let tasks = StudyPlanner.plan(topics: ["A", "B"], start: date(2026, 11, 10),
                                      end: date(2026, 11, 11), reviewDays: 3, calendar: rome)
        #expect(tasks.filter { $0.title != "Ripasso generale" }.allSatisfy { $0.dueDate == date(2026, 11, 10) })
        #expect(tasks.allSatisfy { $0.dueDate < date(2026, 11, 11) || $0.dueDate == date(2026, 11, 10) })
    }

    @Test func moreTopicsThanDays() {
        let tasks = StudyPlanner.plan(topics: ["A", "B", "C", "D"], start: date(2026, 11, 1),
                                      end: date(2026, 11, 3), reviewDays: 0, calendar: rome)
        #expect(tasks.map(\.dueDate) == [date(2026, 11, 1), date(2026, 11, 1), date(2026, 11, 2), date(2026, 11, 2)])
    }
}

// MARK: 5. Andamento della media

@Suite struct AverageTrendTests {
    @Test func cumulativeWeightedAverageInDateOrder() {
        let exams = [
            Exam(name: "B", date: date(2026, 2, 1), passed: true, grade: 30, cfu: 10),
            Exam(name: "A", date: date(2026, 1, 1), passed: true, grade: 24, cfu: 10),
            Exam(name: "Non superato", date: date(2026, 1, 15), passed: false, cfu: 10),
            Exam(name: "M", date: date(2026, 1, 20), passed: true, grade: 18, degree: .magistrale, cfu: 10),
            Exam(name: "C", date: date(2026, 3, 1), passed: true, grade: 18, cfu: 20),
        ]
        let trend = exams.averageTrend(degree: .triennale)
        #expect(trend.map(\.examName) == ["A", "B", "C"])
        #expect(trend.map(\.average) == [24, 27, 22.5])
        #expect(trend.map(\.grade) == [24, 30, 18])
    }
}
