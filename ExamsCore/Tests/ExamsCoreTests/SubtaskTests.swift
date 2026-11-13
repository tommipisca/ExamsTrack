import Foundation
import Testing
@testable import ExamsCore

@MainActor
@Suite struct SubtaskTests {
    func makeStore() -> ExamStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("exams.json")
        return ExamStore(fileURL: url, calendar: rome)
    }

    func sample() -> (Exam, StudyTask) {
        let task = StudyTask(title: "Capitolo 4", dueDate: date(2026, 11, 12), subtasks: [
            Subtask(title: "Teoria"), Subtask(title: "Esercizi"), Subtask(title: "Formulario"),
        ])
        return (Exam(name: "A", date: date(2026, 11, 20), tasks: [task, StudyTask(title: "Altro", dueDate: date(2026, 11, 13))]), task)
    }

    @Test func partialSubtasksCountInProgress() {
        let store = makeStore()
        let (exam, task) = sample()
        store.addExam(exam)
        store.toggleSubtask(id: task.subtasks[0].id, inTask: task.id, inExam: exam.id)
        let saved = store.exam(id: exam.id)!
        #expect(saved.tasks[0].subtaskLabel == "1/3")
        #expect(!saved.tasks[0].isDone)
        // (1/3 + 0) / 2 task
        #expect(abs(saved.progress - 1.0 / 6.0) < 0.0001)
    }

    @Test func lastSubtaskCompletesTaskAndUncheckingReopensIt() {
        let store = makeStore()
        let (exam, task) = sample()
        store.addExam(exam)
        for sub in task.subtasks { store.toggleSubtask(id: sub.id, inTask: task.id, inExam: exam.id) }
        #expect(store.exam(id: exam.id)!.tasks[0].isDone)
        store.toggleSubtask(id: task.subtasks[1].id, inTask: task.id, inExam: exam.id)
        #expect(!store.exam(id: exam.id)!.tasks[0].isDone)
    }

    @Test func togglingTaskTogglesAllSubtasks() {
        let store = makeStore()
        let (exam, task) = sample()
        store.addExam(exam)
        store.toggleTask(id: task.id, inExam: exam.id)
        let allDone = store.exam(id: exam.id)!.tasks[0].subtasks.allSatisfy(\.isDone)
        #expect(allDone)
        store.toggleTask(id: task.id, inExam: exam.id)
        let noneDone = store.exam(id: exam.id)!.tasks[0].subtasks.allSatisfy { !$0.isDone }
        #expect(noneDone)
    }

    @Test func oldDataWithoutSubtasksDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"T","dueDate":"2026-11-12T11:00:00Z","isDone":true}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(StudyTask.self, from: Data(json.utf8))
        #expect(task.subtasks.isEmpty)
        #expect(task.completion == 1)
    }
}
