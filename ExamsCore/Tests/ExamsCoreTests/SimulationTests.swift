import Foundation
import Testing
@testable import ExamsCore

@Suite struct SimulationTests {
    func passed(_ grade: Int, cfu: Int, degree: Degree = .triennale) -> Exam {
        Exam(name: "Fatto", date: date(2026, 1, 10), passed: true, grade: grade, degree: degree, cfu: cfu)
    }

    func pending(_ simulated: Int?, cfu: Int, degree: Degree = .triennale) -> Exam {
        Exam(name: "Da fare", date: date(2026, 12, 10), degree: degree, cfu: cfu, simulatedGrade: simulated)
    }

    @Test func simulatableOnlyWithoutRealGrade() {
        #expect(pending(nil, cfu: 6).isSimulatable)
        #expect(!passed(28, cfu: 6).isSimulatable)
        #expect(Exam(name: "Bocciato", date: date(2026, 1, 10), passed: false, cfu: 6).isSimulatable)
        #expect(!Exam(name: "Tesi", date: date(2026, 1, 10), degree: .magistrale, isFinalTest: true).isSimulatable)
    }

    @Test func simulatedAverageCombinesRealAndHypothetical() throws {
        let exams = [passed(24, cfu: 6), pending(30, cfu: 6), pending(nil, cfu: 12)]
        let average = try #require(exams.simulatedAverage(degree: .triennale))
        #expect(abs(average - 27) < 0.0001)
    }

    @Test func realGradeWinsOverStaleSimulation() throws {
        var graded = passed(20, cfu: 6)
        graded.simulatedGrade = 30
        // Solo la simulazione rimasta su un esame con voto vero: nulla da simulare.
        #expect([graded].simulatedAverage(degree: .triennale) == nil)
        // Con un'altra simulazione valida, quella rimasta viene ignorata: (20 + 26) / 2.
        let average = try #require([graded, pending(26, cfu: 6)].simulatedAverage(degree: .triennale))
        #expect(abs(average - 23) < 0.0001)
    }

    @Test func nilWhenNoSimulatedGrades() {
        #expect([passed(24, cfu: 6), pending(nil, cfu: 6)].simulatedAverage(degree: .triennale) == nil)
    }

    @Test func otherDegreeIgnored() {
        let exams = [pending(30, cfu: 6, degree: .magistrale), passed(24, cfu: 6)]
        #expect(exams.simulatedAverage(degree: .triennale) == nil)
    }

    @Test func simulationFeedsGraduationEstimate() throws {
        // 171 CFU a 24 veri + 9 CFU di prova finale simulati a 30: nessun CFU mancante.
        let exams = [
            passed(24, cfu: 171),
            Exam(name: "PF", date: date(2026, 12, 10), cfu: 9, isFinalTest: true, simulatedGrade: 30),
        ]
        let simulated = try #require(exams.applyingSimulation().graduationEstimate())
        let average: Double = (24.0 * 171.0 + 30.0 * 9.0) / 180.0
        let expected: Double = average * 110.0 / 30.0 + 1.0 + 5.0
        #expect(abs(simulated.minimum - expected) < 0.0001)
        #expect(!simulated.isRange)
        // I dati veri restano senza voto.
        #expect(exams.graduationEstimate()?.isRange == true)
    }

    @Test func oldDataHasNoSimulation() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"A","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([Exam].self, from: Data(json.utf8)).first?.simulatedGrade == nil)
    }
}

@MainActor
@Suite struct SimulationStoreTests {
    func makeStore() -> ExamStore {
        ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
    }

    @Test func setClampsAndClears() {
        let store = makeStore()
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        store.addExam(exam)
        store.setSimulatedGrade(examID: exam.id, grade: 35)
        #expect(store.exam(id: exam.id)?.simulatedGrade == 30)
        store.setSimulatedGrade(examID: exam.id, grade: 10)
        #expect(store.exam(id: exam.id)?.simulatedGrade == 18)
        store.setSimulatedGrade(examID: exam.id, grade: nil)
        #expect(store.exam(id: exam.id)?.simulatedGrade == nil)
    }

    @Test func clearSimulationOnlyForDegree() {
        let store = makeStore()
        let triennale = Exam(name: "T", date: date(2026, 12, 1), simulatedGrade: 28)
        let magistrale = Exam(name: "M", date: date(2026, 12, 1), degree: .magistrale, simulatedGrade: 27)
        store.addExam(triennale)
        store.addExam(magistrale)
        store.clearSimulation(degree: .triennale)
        #expect(store.exam(id: triennale.id)?.simulatedGrade == nil)
        #expect(store.exam(id: magistrale.id)?.simulatedGrade == 27)
    }
}
