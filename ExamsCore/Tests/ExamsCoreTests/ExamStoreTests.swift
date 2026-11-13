import Foundation
import Testing
@testable import ExamsCore

@MainActor
@Suite struct ExamStoreTests {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("exams.json") }
    var corruptURL: URL { directory.appendingPathComponent("exams.corrupt.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func sampleExam() -> Exam {
        Exam(name: "Analisi", date: date(2026, 11, 22), tasks: [
            StudyTask(title: "Limiti", dueDate: date(2026, 11, 1)),
            StudyTask(title: "Derivate", dueDate: date(2026, 11, 8), isDone: true),
        ])
    }

    // MARK: Caricamento e salvataggio

    @Test func missingFileStartsEmpty() {
        let store = ExamStore(fileURL: fileURL)
        #expect(store.exams.isEmpty)
        #expect(store.lastError == nil)
    }

    @Test func savesAndReloads() {
        let store = ExamStore(fileURL: fileURL)
        store.addExam(sampleExam())
        let reloaded = ExamStore(fileURL: fileURL)
        #expect(reloaded.exams == store.exams)
        #expect(reloaded.exams.first?.tasks.count == 2)
    }

    @Test func createsMissingParentDirectory() {
        let nested = directory.appendingPathComponent("a/b/exams.json")
        let store = ExamStore(fileURL: nested)
        store.addExam(sampleExam())
        #expect(store.lastError == nil)
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func corruptFileIsMovedAside() throws {
        try Data("non è json".utf8).write(to: fileURL)
        let store = ExamStore(fileURL: fileURL)
        #expect(store.exams.isEmpty)
        #expect(store.lastError == .corruptedData)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: corruptURL, encoding: .utf8) == "non è json")
    }

    @Test func secondCorruptFileReplacesFirst() throws {
        try Data("vecchio".utf8).write(to: corruptURL)
        try Data("nuovo".utf8).write(to: fileURL)
        let store = ExamStore(fileURL: fileURL)
        #expect(store.lastError == .corruptedData)
        #expect(try String(contentsOf: corruptURL, encoding: .utf8) == "nuovo")
    }

    @Test func saveFailureKeepsDataInMemory() throws {
        // Un file al posto della cartella rende impossibile la scrittura.
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let store = ExamStore(fileURL: blocker.appendingPathComponent("exams.json"))
        store.addExam(sampleExam())
        #expect(store.lastError == .saveFailed)
        #expect(store.exams.count == 1)
    }

    @Test func onSaveCalledAfterEachChange() {
        var calls = 0
        let store = ExamStore(fileURL: fileURL, onSave: { calls += 1 })
        let exam = sampleExam()
        store.addExam(exam)
        store.toggleTask(id: exam.tasks[0].id, inExam: exam.id)
        #expect(calls == 2)
    }

    @Test func readOnlyReadsSavedData() {
        let store = ExamStore(fileURL: fileURL)
        store.addExam(sampleExam())
        #expect(ExamStore.readOnly(from: fileURL) == store.exams)
    }

    @Test func readOnlyReportsCorruptFileWithoutMovingIt() throws {
        try Data("rotto".utf8).write(to: fileURL)
        #expect(ExamStore.readOnly(from: fileURL) == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func readOnlyMissingFileIsEmpty() {
        #expect(ExamStore.readOnly(from: fileURL) == [])
    }

    @Test func readOnlyReportsUnreadableFile() throws {
        // Come un file protetto prima del primo sblocco: esiste ma non si legge.
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        #expect(ExamStore.readOnly(from: fileURL) == nil)
    }

    // MARK: Modifiche

    @Test func updateAndDeleteExam() {
        let store = ExamStore(fileURL: fileURL)
        var exam = sampleExam()
        store.addExam(exam)
        exam.name = "Analisi 1"
        store.updateExam(exam)
        #expect(store.exam(id: exam.id)?.name == "Analisi 1")
        store.deleteExam(id: exam.id)
        #expect(store.exam(id: exam.id) == nil)
        #expect(ExamStore(fileURL: fileURL).exams.isEmpty)
    }

    @Test func taskOperations() {
        let store = ExamStore(fileURL: fileURL)
        let exam = sampleExam()
        store.addExam(exam)

        let newTask = StudyTask(title: "Integrali", dueDate: date(2026, 11, 15))
        store.addTask(newTask, toExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.count == 3)

        store.toggleTask(id: newTask.id, inExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.first { $0.id == newTask.id }?.isDone == true)

        var edited = newTask
        edited.title = "Integrali doppi"
        store.updateTask(edited, inExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.first { $0.id == newTask.id }?.title == "Integrali doppi")

        store.deleteTask(id: newTask.id, fromExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.count == 2)
    }

    @Test func unknownIDsAreIgnored() {
        let store = ExamStore(fileURL: fileURL)
        store.addTask(StudyTask(title: "X", dueDate: date(2026, 11, 1)), toExam: UUID())
        store.updateExam(sampleExam())
        #expect(store.exams.isEmpty)
        #expect(store.lastError == nil)
    }

    // MARK: Esito

    @Test func outcomeNormalization() {
        let store = ExamStore(fileURL: fileURL)
        let exam = sampleExam()
        store.addExam(exam)

        store.setOutcome(examID: exam.id, passed: true, grade: 28, honors: true)
        #expect(store.exam(id: exam.id)?.grade == 28)
        #expect(store.exam(id: exam.id)?.honors == false)

        store.setOutcome(examID: exam.id, passed: true, grade: 35, honors: true)
        #expect(store.exam(id: exam.id)?.grade == 30)
        #expect(store.exam(id: exam.id)?.honors == true)

        store.setOutcome(examID: exam.id, passed: true, grade: 10, honors: false)
        #expect(store.exam(id: exam.id)?.grade == 18)
    }

    @Test func notPassedClearsGradeThenPassedAgainUsesDefault() {
        let store = ExamStore(fileURL: fileURL)
        let exam = sampleExam()
        store.addExam(exam)
        store.setOutcome(examID: exam.id, passed: true, grade: 30, honors: true)

        store.setOutcome(examID: exam.id, passed: false, grade: 30, honors: true)
        #expect(store.exam(id: exam.id)?.passed == false)
        #expect(store.exam(id: exam.id)?.grade == nil)
        #expect(store.exam(id: exam.id)?.honors == false)

        store.setOutcome(examID: exam.id, passed: true, grade: nil, honors: false)
        #expect(store.exam(id: exam.id)?.grade == 18)
        #expect(store.exam(id: exam.id)?.honors == false)

        store.setOutcome(examID: exam.id, passed: nil, grade: 25, honors: false)
        #expect(store.exam(id: exam.id)?.passed == nil)
        #expect(store.exam(id: exam.id)?.grade == nil)
    }
}
