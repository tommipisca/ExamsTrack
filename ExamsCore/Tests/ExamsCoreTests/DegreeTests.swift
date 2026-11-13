import Foundation
import Testing
@testable import ExamsCore

@Suite struct DegreeCodingTests {
    @Test func examWithoutDegreeDecodesAsTriennale() throws {
        // Formato salvato prima dell'introduzione del tag.
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Analisi","date":"2026-11-10T11:00:00Z",
          "tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exams = try decoder.decode([Exam].self, from: Data(json.utf8))
        #expect(exams.first?.degree == .triennale)
        #expect(exams.first?.name == "Analisi")
    }

    @Test func degreeRoundTrips() throws {
        let exam = Exam(name: "A", date: date(2026, 11, 10), degree: .magistrale)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Exam.self, from: encoder.encode(exam))
        #expect(decoded == exam)
    }

    @Test func labels() {
        #expect(Degree.triennale.label == "Triennale")
        #expect(Degree.magistrale.label == "Magistrale")
    }
}

@Suite struct CareerTests {
    let today = date(2026, 11, 10)

    @Test func filtersPastExamsByDegree() {
        let exams = [
            Exam(name: "T passato", date: date(2026, 9, 1), degree: .triennale),
            Exam(name: "M passato", date: date(2026, 10, 1), degree: .magistrale),
            Exam(name: "M futuro", date: date(2026, 12, 1), degree: .magistrale),
        ]
        #expect(exams.career(degree: .magistrale, today: today, calendar: rome).map(\.name) == ["M passato"])
        #expect(exams.career(degree: .triennale, today: today, calendar: rome).map(\.name) == ["T passato"])
    }
}

@MainActor
@Suite struct DefaultDegreeTests {
    func makeStore() -> ExamStore {
        ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
    }

    @Test func triennaleWhenNoExams() {
        #expect(makeStore().defaultDegree == .triennale)
    }

    @Test func usesLastInsertedExam() {
        let store = makeStore()
        store.addExam(Exam(name: "Dopo", date: date(2026, 12, 20), degree: .triennale))
        store.addExam(Exam(name: "Prima", date: date(2026, 11, 20), degree: .magistrale))
        // L'ultimo inserito è "Prima", anche se ha la data più vicina.
        #expect(store.defaultDegree == .magistrale)
    }
}
