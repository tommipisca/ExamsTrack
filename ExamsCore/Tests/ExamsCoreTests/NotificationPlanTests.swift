import Foundation
import Testing
@testable import ExamsCore

@Suite struct NotificationPlanTests {
    let now = date(2026, 11, 1, 8, 0)

    func settings(_ offsets: Set<ReminderOffset>, daily: Bool = false) -> NotificationSettings {
        NotificationSettings(examReminders: offsets, dailyTaskSummary: daily, hour: 9, minute: 30)
    }

    @Test func examRemindersAtChosenTime() {
        let exam = Exam(name: "Analisi", date: date(2026, 11, 20))
        let plan = NotificationPlanner.plan(exams: [exam], settings: settings([.oneWeek, .oneDay, .sameDay]), now: now, calendar: rome)
        #expect(plan.map(\.fireDate) == [date(2026, 11, 13, 9, 30), date(2026, 11, 19, 9, 30), date(2026, 11, 20, 9, 30)])
        #expect(plan.allSatisfy { $0.title == "Analisi" })
        #expect(plan.map(\.body) == ["Esame tra 7 giorni", "Esame domani", "Esame oggi: in bocca al lupo!"])
    }

    @Test func oneMonthUsesCalendarMonth() {
        let exam = Exam(name: "A", date: date(2026, 12, 15))
        let plan = NotificationPlanner.plan(exams: [exam], settings: settings([.oneMonth]), now: now, calendar: rome)
        #expect(plan.map(\.fireDate) == [date(2026, 11, 15, 9, 30)])
    }

    @Test func skipsPastReminders() {
        // Il promemoria di una settimana prima cadrebbe il 27/10, già passato.
        let exam = Exam(name: "A", date: date(2026, 11, 3))
        let plan = NotificationPlanner.plan(exams: [exam], settings: settings([.oneWeek, .oneDay]), now: now, calendar: rome)
        #expect(plan.map(\.fireDate) == [date(2026, 11, 2, 9, 30)])
    }

    @Test func ignoresUnscheduledAndPastExams() {
        let exams = [
            Exam(name: "Senza data", date: date(2026, 11, 20), isScheduled: false),
            Exam(name: "Passato", date: date(2026, 10, 20)),
        ]
        #expect(NotificationPlanner.plan(exams: exams, settings: settings([.sameDay]), now: now, calendar: rome).isEmpty)
    }

    @Test func dailySummaryOnlyOnDaysWithOpenTasks() {
        let exams = [
            Exam(name: "Analisi", date: date(2026, 11, 30), tasks: [
                StudyTask(title: "Limiti", dueDate: date(2026, 11, 3)),
                StudyTask(title: "Fatto", dueDate: date(2026, 11, 4), isDone: true),
                StudyTask(title: "Vecchio", dueDate: date(2026, 10, 20)),
            ]),
            Exam(name: "Fisica", date: date(2026, 1, 1), tasks: [
                StudyTask(title: "Cinematica", dueDate: date(2026, 11, 3)),
            ], isScheduled: false),
        ]
        let plan = NotificationPlanner.plan(exams: exams, settings: settings([], daily: true), now: now, calendar: rome)
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == date(2026, 11, 3, 9, 30))
        #expect(plan.first?.title == "2 task in scadenza oggi")
        #expect(plan.first?.body == "Cinematica (Fisica), Limiti (Analisi)")
    }

    @Test func singleTaskTitle() {
        let exam = Exam(name: "A", date: date(2026, 11, 30), tasks: [StudyTask(title: "T", dueDate: date(2026, 11, 5))])
        let plan = NotificationPlanner.plan(exams: [exam], settings: settings([], daily: true), now: now, calendar: rome)
        #expect(plan.first?.title == "1 task in scadenza oggi")
    }

    @Test func dailySummaryDisabled() {
        let exam = Exam(name: "A", date: date(2026, 11, 30), tasks: [StudyTask(title: "T", dueDate: date(2026, 11, 5))])
        #expect(NotificationPlanner.plan(exams: [exam], settings: settings([]), now: now, calendar: rome).isEmpty)
    }

    @Test func capsAtSystemLimitKeepingEarliest() {
        let exams = (1...30).map { i in Exam(name: "E\(i)", date: date(2026, 12, i)) }
        let plan = NotificationPlanner.plan(exams: exams, settings: settings([.oneDay, .sameDay, .oneWeek]), now: now, calendar: rome)
        #expect(plan.count == NotificationPlanner.maximumPending)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
    }

    @Test func stableIdentifiers() {
        let exam = Exam(name: "A", date: date(2026, 11, 20))
        let first = NotificationPlanner.plan(exams: [exam], settings: settings([.oneDay]), now: now, calendar: rome)
        let second = NotificationPlanner.plan(exams: [exam], settings: settings([.oneDay]), now: now, calendar: rome)
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test func settingsRoundTrip() throws {
        let original = settings([.oneMonth, .sameDay], daily: true)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(NotificationSettings.default.examReminders == [.oneWeek, .oneDay, .sameDay])
    }
}

@MainActor
@Suite struct BackupTests {
    func makeStore() -> ExamStore {
        ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
    }

    @Test func exportThenImportRestoresExams() throws {
        let source = makeStore()
        source.addExam(Exam(name: "Analisi", date: date(2026, 11, 20), tasks: [StudyTask(title: "T", dueDate: date(2026, 11, 10))]))
        source.addExam(Exam(name: "Fisica", date: date(2026, 12, 1), passed: true, grade: 28, degree: .magistrale, cfu: 9))
        let data = try source.exportBackup(now: date(2026, 11, 1))

        let target = makeStore()
        target.addExam(Exam(name: "Da sostituire", date: date(2026, 11, 5)))
        try target.importBackup(data)
        #expect(target.exams == source.exams)
    }

    @Test func importsPlainExamsFile() throws {
        let source = makeStore()
        source.addExam(Exam(name: "Analisi", date: date(2026, 11, 20)))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let target = makeStore()
        try target.importBackup(encoder.encode(source.exams))
        #expect(target.exams == source.exams)
    }

    @Test func invalidBackupLeavesDataUntouched() {
        let store = makeStore()
        store.addExam(Exam(name: "Analisi", date: date(2026, 11, 20)))
        let before = store.exams
        #expect(throws: BackupError.unreadable) { try store.importBackup(Data("non è un backup".utf8)) }
        #expect(store.exams == before)
    }

    @Test func importSavesAndNotifies() throws {
        let source = makeStore()
        source.addExam(Exam(name: "A", date: date(2026, 11, 20)))
        let data = try source.exportBackup(now: date(2026, 11, 1))
        var saves = 0
        let target = makeStore()
        target.onSave = { saves += 1 }
        try target.importBackup(data)
        #expect(saves == 1)
    }

    @Test func backupFileName() {
        #expect(ExamStore.backupFileName(now: date(2026, 11, 1), calendar: rome) == "ExamsTrack-backup-2026-11-01")
    }
}
