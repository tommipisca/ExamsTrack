import Foundation
import Testing
@testable import ExamsCore

@Suite struct MasterGraduationTests {
    func passed(_ grade: Int, cfu: Int, honors: Bool = false) -> Exam {
        Exam(name: "M", date: date(2026, 1, 10), passed: true, grade: grade, honors: honors, degree: .magistrale, cfu: cfu)
    }

    @Test func fullCoursesWithReviewer() throws {
        // 100 CFU a 27 → 99; tesi da -1 a +7.
        let estimate = try #require([passed(27, cfu: 100)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(abs(estimate.minimum - 98) < 0.0001)
        #expect(abs(estimate.maximum - 106) < 0.0001)
    }

    @Test func withoutReviewerMaxFourPoints() throws {
        let estimate = try #require([passed(27, cfu: 100)].masterGraduationEstimate(thesis: .withoutReviewer))
        #expect(abs(estimate.maximum - 103) < 0.0001)
    }

    @Test func missingCFUAtEighteenAndThirty() throws {
        // 50 CFU a 30, ne mancano 50: media 24..30 → 88..110, poi tesi -1..+7.
        let estimate = try #require([passed(30, cfu: 50)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(abs(estimate.minimum - 87) < 0.0001)
        #expect(abs(estimate.maximum - 117) < 0.0001)
        #expect([passed(30, cfu: 50)].missingMasterCFU() == 50)
    }

    @Test func minimumNeverBelowSixtySix() throws {
        let estimate = try #require([passed(18, cfu: 100)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(estimate.minimum == 66)
    }

    @Test func ignoresTriennaleAndNilWithoutGrades() {
        let triennale = Exam(name: "T", date: date(2026, 1, 10), passed: true, grade: 30, cfu: 10)
        #expect([triennale].masterGraduationEstimate(thesis: .withReviewer) == nil)
    }

    @Test func honorsThreshold() throws {
        // Nessuna lode negli esami: serve almeno 113.
        let noHonors = try #require([passed(30, cfu: 100)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(noHonors.honorsThreshold == 113)
        #expect(noHonors.canGetHonors)   // 110 + 7 = 117

        // 6 lodi: 113 - 3 = 110 → la soglia minima resta 111.
        let manyHonors = (0..<6).map { _ in passed(30, cfu: 10, honors: true) } + [passed(30, cfu: 40)]
        let estimate = try #require(manyHonors.masterGraduationEstimate(thesis: .withReviewer))
        #expect(estimate.honorsThreshold == 111)
    }

    @Test func noHonorsWithoutReviewer() throws {
        let estimate = try #require([passed(30, cfu: 100)].masterGraduationEstimate(thesis: .withoutReviewer))
        #expect(!estimate.canGetHonors)
    }

    @Test func honorsOutOfReach() throws {
        let estimate = try #require([passed(25, cfu: 100)].masterGraduationEstimate(thesis: .withReviewer))
        #expect(!estimate.canGetHonors)   // 91.67 + 7 < 113
    }

    @Test func thesisLabels() {
        #expect(ThesisType.withReviewer.label == "Con controrelatore")
        #expect(ThesisType.withoutReviewer.maximumPoints == 4)
    }
}

@Suite struct TriennaleHonorsTests {
    @Test func usesHonorsCountOfTriennaleOnly() throws {
        let exams = [
            Exam(name: "A", date: date(2026, 1, 10), passed: true, grade: 30, honors: true, cfu: 90),
            Exam(name: "B", date: date(2026, 1, 10), passed: true, grade: 30, honors: true, cfu: 81),
            Exam(name: "PF", date: date(2026, 1, 10), passed: true, grade: 30, cfu: 9, isFinalTest: true),
            Exam(name: "M", date: date(2026, 1, 10), passed: true, grade: 30, honors: true, degree: .magistrale, cfu: 6),
        ]
        let estimate = try #require(exams.graduationEstimate())
        #expect(estimate.honorsThreshold == 112)   // 113 - 0.5 × 2
        #expect(estimate.canGetHonors)             // 116 ≥ 112
    }
}
