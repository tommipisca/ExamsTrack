import Foundation
import Testing
@testable import ExamsCore

@Suite struct WeightedAverageTests {
    func passed(_ grade: Int, cfu: Int, honors: Bool = false, degree: Degree = .triennale, finalTest: Bool = false) -> Exam {
        Exam(name: "E", date: date(2026, 1, 10), passed: true, grade: grade, honors: honors,
             degree: degree, cfu: cfu, isFinalTest: finalTest)
    }

    @Test func weightsByCFU() throws {
        let average = try #require([passed(28, cfu: 6), passed(30, cfu: 12)].weightedAverage(degree: .triennale))
        #expect(abs(average - 528.0 / 18.0) < 0.0001)
    }

    @Test func honorsCountAsThirty() {
        #expect([passed(30, cfu: 6, honors: true)].weightedAverage(degree: .triennale) == 30)
    }

    @Test func ignoresNotPassedUngradedAndOtherDegree() {
        let exams = [
            passed(24, cfu: 6),
            Exam(name: "Non superato", date: date(2026, 1, 10), passed: false, cfu: 12),
            Exam(name: "Da inserire", date: date(2026, 1, 10), cfu: 12),
            passed(30, cfu: 12, degree: .magistrale),
        ]
        #expect(exams.weightedAverage(degree: .triennale) == 24)
        #expect(exams.weightedAverage(degree: .magistrale) == 30)
    }

    @Test func nilWithoutGrades() {
        #expect([Exam]().weightedAverage(degree: .triennale) == nil)
    }

    @Test func earnedCFUCountsOnlyPassed() {
        let exams = [passed(24, cfu: 6), passed(30, cfu: 9), Exam(name: "X", date: date(2026, 1, 10), passed: false, cfu: 12)]
        #expect(exams.earnedCFU(degree: .triennale) == 15)
    }
}

@Suite struct GraduationEstimateTests {
    func passed(_ grade: Int, cfu: Int, finalTest: Bool = false) -> Exam {
        Exam(name: "E", date: date(2026, 1, 10), passed: true, grade: grade, cfu: cfu, isFinalTest: finalTest)
    }

    @Test func allEighteensGiveSeventy() throws {
        // Controprova: con tutti 18 non si può scendere sotto 70.
        let estimate = try #require([passed(18, cfu: 171), passed(18, cfu: 9, finalTest: true)].graduationEstimate())
        #expect(abs(estimate.minimum - 70) < 0.0001)
        #expect(estimate.minimum == estimate.maximum)
    }

    @Test func allThirtiesGiveOneHundredSixteen() throws {
        let estimate = try #require([passed(30, cfu: 171), passed(30, cfu: 9, finalTest: true)].graduationEstimate())
        #expect(abs(estimate.maximum - 116) < 0.0001)
    }

    @Test func formulaWithAllCFU() throws {
        // media (27*120 + 24*60)/180 = 26 → 26*110/30 = 95.333; prova finale 24 → 1 + 24/6 = 5
        let estimate = try #require([passed(27, cfu: 120), passed(24, cfu: 60, finalTest: true)].graduationEstimate())
        #expect(abs(estimate.minimum - (26.0 * 110.0 / 30.0 + 5)) < 0.0001)
        #expect(!estimate.isRange)
    }

    @Test func missingCFUAtEighteenAndThirty() throws {
        // 120 CFU a 27 (prova finale 30 su 6 di questi), mancano 60 CFU.
        let exams = [passed(27, cfu: 114), passed(30, cfu: 6, finalTest: true)]
        let estimate = try #require(exams.graduationEstimate())
        let graded: Double = 27.0 * 114.0 + 30.0 * 6.0
        let lowAverage: Double = (graded + 18.0 * 60.0) / 180.0
        let highAverage: Double = (graded + 30.0 * 60.0) / 180.0
        let low: Double = lowAverage * 110.0 / 30.0 + 6.0
        let high: Double = highAverage * 110.0 / 30.0 + 6.0
        #expect(abs(estimate.minimum - low) < 0.0001)
        #expect(abs(estimate.maximum - high) < 0.0001)
    }

    @Test func rangeWhenFinalTestNotGraded() throws {
        // 12 CFU a 30, ne mancano 168; prova finale ancora senza voto.
        let estimate = try #require([passed(30, cfu: 12)].graduationEstimate())
        let lowAverage: Double = (30.0 * 12 + 18.0 * 168) / 180.0
        let low: Double = lowAverage * 110.0 / 30.0 + 1.0 + 3.0
        #expect(abs(estimate.minimum - low) < 0.0001)
        #expect(abs(estimate.maximum - 116) < 0.0001)
    }

    @Test func missingCFUCount() {
        #expect([passed(30, cfu: 12), passed(24, cfu: 6)].missingGraduationCFU() == 162)
        #expect([passed(30, cfu: 200)].missingGraduationCFU() == 0)
    }

    @Test func nilWithoutGrades() {
        #expect([Exam]().graduationEstimate() == nil)
    }

    @Test func onlyTriennaleCounts() {
        let magistrale = Exam(name: "M", date: date(2026, 1, 10), passed: true, grade: 30, degree: .magistrale, cfu: 6)
        #expect([magistrale].graduationEstimate() == nil)
    }
}

@Suite struct FinalTestDetectionTests {
    @Test func detectsFromName() {
        #expect(Exam.looksLikeFinalTest(name: "Prova finale - Tesi"))
        #expect(Exam.looksLikeFinalTest(name: "PROVA FINALE"))
        #expect(!Exam.looksLikeFinalTest(name: "Analisi 1"))
    }
}

@Suite struct CFUCodingTests {
    @Test func oldDataGetsDefaults() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Analisi","date":"2026-11-10T11:00:00Z",
          "tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exam = try #require(try decoder.decode([Exam].self, from: Data(json.utf8)).first)
        #expect(exam.cfu == 6)
        #expect(exam.isFinalTest == false)
    }
}
