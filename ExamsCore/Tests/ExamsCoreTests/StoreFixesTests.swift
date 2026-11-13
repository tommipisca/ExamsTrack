import Foundation
import Testing
@testable import ExamsCore

@MainActor
@Suite struct StoreFixesTests {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("exams.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Date salvate a mezzogiorno

    @Test func examDateStoredAtNoon() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 11, 10, 23, 30))
        store.addExam(exam)
        #expect(store.exam(id: exam.id)?.date == date(2026, 11, 10, 12, 0))
    }

    @Test func taskDueDateStoredAtNoon() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 11, 20))
        store.addExam(exam)
        let task = StudyTask(title: "T", dueDate: date(2026, 11, 5, 0, 15))
        store.addTask(task, toExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.first?.dueDate == date(2026, 11, 5, 12, 0))
    }

    @Test func existingDatesNormalizedOnLoad() throws {
        let raw = [Exam(name: "A", date: date(2026, 11, 10, 23, 30), tasks: [
            StudyTask(title: "T", dueDate: date(2026, 11, 1, 8, 0)),
        ])]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(raw).write(to: fileURL)

        let store = ExamStore(fileURL: fileURL, calendar: rome)
        #expect(store.exams.first?.date == date(2026, 11, 10, 12, 0))
        #expect(store.exams.first?.tasks.first?.dueDate == date(2026, 11, 1, 12, 0))
    }

    // MARK: Task non oltre la data dell'esame

    @Test func movingExamEarlierClampsLaterTasks() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        var exam = Exam(name: "A", date: date(2026, 11, 30), tasks: [
            StudyTask(title: "Presto", dueDate: date(2026, 11, 5)),
            StudyTask(title: "Tardi", dueDate: date(2026, 11, 25)),
        ])
        store.addExam(exam)
        exam.date = date(2026, 11, 20)
        store.updateExam(exam)

        let tasks = store.exam(id: exam.id)!.tasks
        #expect(tasks.first { $0.title == "Presto" }?.dueDate == date(2026, 11, 5))
        #expect(tasks.first { $0.title == "Tardi" }?.dueDate == date(2026, 11, 20))
    }

    @Test func taskAddedAfterExamIsClamped() {
        let store = ExamStore(fileURL: fileURL, calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 11, 20))
        store.addExam(exam)
        store.addTask(StudyTask(title: "T", dueDate: date(2026, 12, 1)), toExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.first?.dueDate == date(2026, 11, 20))
    }

    // MARK: Errore di lettura non scambiato per corruzione

    @Test func readErrorKeepsFileAndBlocksSaving() throws {
        // Una cartella al posto del file: esiste, ma leggerla fallisce senza essere JSON corrotto.
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        let store = ExamStore(fileURL: fileURL, calendar: rome)
        #expect(store.lastError == .readFailed)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("exams.corrupt.json").path))

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        store.lastError = nil
        var saves = 0
        store.onSave = { saves += 1 }
        store.addExam(Exam(name: "A", date: date(2026, 11, 20)))
        #expect(saves == 0)
        #expect(store.lastError == .readFailed)
    }
}

@MainActor
@Suite struct UpdateExamDetailsTests {
    @Test func updatesOnlyNameAndDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ExamStore(fileURL: directory.appendingPathComponent("exams.json"), calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 11, 30), tasks: [
            StudyTask(title: "T", dueDate: date(2026, 11, 5)),
        ])
        store.addExam(exam)
        // Modifica avvenuta dopo l'apertura del form: non deve andare persa.
        store.toggleTask(id: exam.tasks[0].id, inExam: exam.id)

        store.updateExamDetails(id: exam.id, name: "Analisi 1", date: date(2026, 12, 1), degree: .magistrale, cfu: 9, isFinalTest: true, isScheduled: true, startTime: nil)

        let saved = try #require(store.exam(id: exam.id))
        #expect(saved.name == "Analisi 1")
        #expect(saved.date == date(2026, 12, 1))
        #expect(saved.degree == .magistrale)
        #expect(saved.cfu == 9)
        #expect(saved.isFinalTest)
        #expect(saved.tasks.first?.isDone == true)
    }
}

@MainActor
@Suite struct WidgetTaskTests {
    @Test func setTaskDoneIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json")
        let task = StudyTask(title: "T", dueDate: date(2026, 11, 12))
        let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [task])
        let store = ExamStore(fileURL: url, calendar: rome)
        store.addExam(exam)
        store.setTaskDone(id: task.id, inExam: exam.id)
        store.setTaskDone(id: task.id, inExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.first?.isDone == true)
    }

    @Test func reloadFromDiskPicksUpOtherWriters() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json")
        let task = StudyTask(title: "T", dueDate: date(2026, 11, 12))
        let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [task])
        let app = ExamStore(fileURL: url, calendar: rome)
        app.addExam(exam)
        // Il widget apre lo stesso file e spunta il task.
        let widget = ExamStore(fileURL: url, calendar: rome)
        widget.setTaskDone(id: task.id, inExam: exam.id)
        #expect(app.exam(id: exam.id)?.tasks.first?.isDone == false)
        app.reloadFromDisk()
        #expect(app.exam(id: exam.id)?.tasks.first?.isDone == true)
    }

    @Test func summaryTasksCarryIDs() throws {
        let task = StudyTask(title: "T", dueDate: date(2026, 11, 12))
        let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [task])
        let summary = try #require(NextExamSummary.make(from: [exam], today: date(2026, 11, 10), calendar: rome))
        #expect(summary.upcomingTasks.first?.examID == exam.id)
        #expect(summary.upcomingTasks.first?.taskID == task.id)
    }
}

extension DefaultsBackedTests {
    @Suite struct RecentlyCompletedTests {
        func makeDefaults() -> UserDefaults {
            let name = "test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        @Test func expiresAfterWindow() {
            let recents = RecentlyCompleted(defaults: makeDefaults())
            let id = UUID()
            let now = Date(timeIntervalSince1970: 1_000)
            recents.set(taskID: id, isDone: true, at: now)
            #expect(recents.active(at: now.addingTimeInterval(1)) == [id: now.addingTimeInterval(RecentlyCompleted.window)])
            #expect(recents.active(at: now.addingTimeInterval(RecentlyCompleted.window)).isEmpty)
        }

        @Test func reopeningRemovesIt() {
            let recents = RecentlyCompleted(defaults: makeDefaults())
            let id = UUID()
            let now = Date(timeIntervalSince1970: 1_000)
            recents.set(taskID: id, isDone: true, at: now)
            recents.set(taskID: id, isDone: false, at: now)
            #expect(recents.active(at: now).isEmpty)
        }

        @Test func summaryKeepsRecentlyDoneTaskInPlace() throws {
            let done = StudyTask(title: "Fatto ora", dueDate: date(2026, 11, 11), isDone: true)
            let exam = Exam(name: "A", date: date(2026, 11, 20), tasks: [
                done,
                StudyTask(title: "Dopo", dueDate: date(2026, 11, 12)),
                StudyTask(title: "Fatto prima", dueDate: date(2026, 11, 10), isDone: true),
            ])
            let today = date(2026, 11, 10)
            let shown = try #require(NextExamSummary.make(from: [exam], today: today, recentlyCompleted: [done.id], calendar: rome))
            #expect(shown.upcomingTasks.map(\.title) == ["Fatto ora", "Dopo"])
            #expect(shown.upcomingTasks.map(\.isDone) == [true, false])
            let later = try #require(NextExamSummary.make(from: [exam], today: today, calendar: rome))
            #expect(later.upcomingTasks.map(\.title) == ["Dopo"])
        }
    }
}
