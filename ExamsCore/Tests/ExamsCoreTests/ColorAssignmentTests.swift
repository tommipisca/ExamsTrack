import Foundation
import Testing
@testable import ExamsCore

@MainActor
@Suite struct ColorAssignmentTests {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("exams.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func newExamsGetBalancedColors() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        for i in 0..<30 {
            store.addExam(Exam(name: "E\(i)", date: date(2026, 12, 1)))
        }
        let counts = Dictionary(grouping: store.exams.compactMap(\.colorIndex), by: { $0 }).mapValues(\.count)
        #expect(counts.count == Palette.examColors.count)
        #expect((counts.values.max() ?? 0) - (counts.values.min() ?? 0) <= 1)
    }

    @Test func nextColorPreviewMatchesAssignment() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        store.addExam(Exam(name: "A", date: date(2026, 12, 1)))
        let preview = store.nextColorIndex
        let exam = Exam(name: "B", date: date(2026, 12, 1))
        store.addExam(exam)
        #expect(store.exam(id: exam.id)?.colorIndex == preview)
    }

    @Test func explicitColorIsKept() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 12, 1), colorIndex: 5)
        store.addExam(exam)
        #expect(store.exam(id: exam.id)?.colorIndex == 5)
    }

    @Test func legacyExamsGetColorsOnLoadInOrder() throws {
        // Dati salvati prima dell'introduzione del colore: nessun colorIndex.
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"A","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false},
         {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"B","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false,"colorIndex":0},
         {"id":"8F9619FF-8B86-D011-B42D-00C04FC964FF","name":"C","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false}]
        """
        try Data(json.utf8).write(to: fileURL)
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        // B tiene lo 0; A e C ricevono i meno usati, nell'ordine del file.
        #expect(store.exams.map(\.colorIndex) == [1, 0, 2])
    }

    @Test func importedBackupWithoutColorsIsBalanced() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = (0..<14).map { Exam(name: "E\($0)", date: date(2026, 12, 1)) }
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        try store.importBackup(encoder.encode(legacy))
        #expect(Set(store.exams.compactMap(\.colorIndex)).count == 14)
    }
}
