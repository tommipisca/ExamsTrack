import Foundation
import Testing
@testable import ExamsCore

@Suite struct DegreeVisibilityTests {
    let exams = [
        Exam(name: "T", date: date(2026, 12, 1)),
        Exam(name: "M", date: date(2026, 12, 1), degree: .magistrale),
    ]

    @Test func bothShowsEverything() {
        #expect(exams.visible(.both).map(\.name) == ["T", "M"])
        #expect(DegreeVisibility.both.fixedDegree == nil)
    }

    @Test func singleDegreeFiltersAndFixes() {
        #expect(exams.visible(.triennale).map(\.name) == ["T"])
        #expect(exams.visible(.magistrale).map(\.name) == ["M"])
        #expect(DegreeVisibility.magistrale.fixedDegree == .magistrale)
        #expect(DegreeVisibility.triennale.includes(.triennale))
        #expect(!DegreeVisibility.triennale.includes(.magistrale))
    }

    @Test func labelsAndStorage() {
        #expect(DegreeVisibility.both.label == "Triennale e magistrale")
        #expect(DegreeVisibility.magistrale.label == "Solo magistrale")
        #expect(DegreeVisibility(rawValue: "triennale") == .triennale)
    }
}
