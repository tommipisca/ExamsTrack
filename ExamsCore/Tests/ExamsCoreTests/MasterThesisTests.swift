import Foundation
import Testing
@testable import ExamsCore

@Suite struct MasterThesisTests {
    func course(_ grade: Int, cfu: Int) -> Exam {
        Exam(name: "C", date: date(2026, 1, 10), passed: true, grade: grade, degree: .magistrale, cfu: cfu)
    }

    func thesis(points: Double?) -> Exam {
        Exam(name: "Tesi", date: date(2026, 1, 10), passed: points != nil, degree: .magistrale, cfu: 20,
             isFinalTest: true, thesisPoints: points)
    }

    @Test func onlyMagistraleFinalTestIsThesis() {
        #expect(thesis(points: nil).isMasterThesis)
        #expect(!Exam(name: "PF", date: date(2026, 1, 10), isFinalTest: true).isMasterThesis)
    }

    @Test func thesisNeverCountsInAverage() {
        var withGrade = thesis(points: 5)
        withGrade.grade = 30
        #expect(withGrade.countedGrade == nil)
        #expect([course(24, cfu: 10), withGrade].weightedAverage(degree: .magistrale) == 24)
    }

    @Test func thesisCreditsCountAsEarned() {
        #expect([course(24, cfu: 10), thesis(points: 5)].earnedCFU(degree: .magistrale) == 30)
    }

    @Test func knownThesisPointsReplaceRange() throws {
        // 100 CFU a 27 → 99, tesi +5 → 104.
        let estimate = try #require([course(27, cfu: 100), thesis(points: 5)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(abs(estimate.minimum - 104) < 0.0001)
        #expect(abs(estimate.maximum - 104) < 0.0001)
    }

    @Test func pendingThesisKeepsRange() throws {
        let estimate = try #require([course(27, cfu: 100), thesis(points: nil)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(abs(estimate.minimum - 98) < 0.0001)
        #expect(abs(estimate.maximum - 106) < 0.0001)
    }

    @Test func outcomeLabels() {
        #expect(thesis(points: 5).outcomeLabel == "Superato, +5 punti")
        #expect(thesis(points: 5.5).outcomeLabel == "Superato, +5,5 punti")
        #expect(thesis(points: -1).outcomeLabel == "Superato, −1 punto")
        #expect(thesis(points: 1).outcomeLabel == "Superato, +1 punto")
        #expect(thesis(points: 5).thesisPointsLabel == "+5")
    }

    @Test func detectsThesisByName() {
        #expect(Exam.looksLikeFinalTest(name: "Tesi di laurea", degree: .magistrale))
        #expect(Exam.looksLikeFinalTest(name: "Master Thesis", degree: .magistrale))
        #expect(!Exam.looksLikeFinalTest(name: "Tesi di laurea", degree: .triennale))
        #expect(Exam.looksLikeFinalTest(name: "Prova finale", degree: .triennale))
        #expect(!Exam.looksLikeFinalTest(name: "Analisi", degree: .magistrale))
    }

    @Test func oldDataHasNoThesisPoints() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"A","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([Exam].self, from: Data(json.utf8)).first?.thesisPoints == nil)
    }
}

@MainActor
@Suite struct ThesisStoreTests {
    func makeStore() -> ExamStore {
        ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
    }

    @Test func setThesisPointsClampsAndRoundsToHalf() {
        let store = makeStore()
        let exam = Exam(name: "Tesi", date: date(2026, 1, 10), degree: .magistrale, cfu: 20, isFinalTest: true)
        store.addExam(exam)
        store.setOutcome(examID: exam.id, passed: true, grade: nil, honors: false)
        store.setThesisPoints(examID: exam.id, points: 12)
        #expect(store.exam(id: exam.id)?.thesisPoints == 8)
        store.setThesisPoints(examID: exam.id, points: -3)
        #expect(store.exam(id: exam.id)?.thesisPoints == -1)
        store.setThesisPoints(examID: exam.id, points: 5.3)
        #expect(store.exam(id: exam.id)?.thesisPoints == 5.5)
    }

    @Test func thesisOutcomeHasNoGrade() {
        let store = makeStore()
        let exam = Exam(name: "Tesi", date: date(2026, 1, 10), degree: .magistrale, cfu: 20, isFinalTest: true)
        store.addExam(exam)
        store.setOutcome(examID: exam.id, passed: true, grade: 28, honors: true)
        #expect(store.exam(id: exam.id)?.grade == nil)
        #expect(store.exam(id: exam.id)?.honors == false)
        #expect(store.exam(id: exam.id)?.passed == true)
    }

    @Test func notPassedClearsThesisPoints() {
        let store = makeStore()
        let exam = Exam(name: "Tesi", date: date(2026, 1, 10), degree: .magistrale, cfu: 20, isFinalTest: true)
        store.addExam(exam)
        store.setOutcome(examID: exam.id, passed: true, grade: nil, honors: false)
        store.setThesisPoints(examID: exam.id, points: 4)
        store.setOutcome(examID: exam.id, passed: false, grade: nil, honors: false)
        #expect(store.exam(id: exam.id)?.thesisPoints == nil)
    }
}
