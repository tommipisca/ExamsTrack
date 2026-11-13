import Foundation
import Testing
@testable import ExamsCore

@Suite struct ScheduledListingTests {
    let today = date(2026, 11, 10)

    func unscheduled(_ name: String) -> Exam {
        // La data salvata di un esame non programmato va ignorata, anche se nel passato.
        Exam(name: name, date: date(2026, 1, 1), isScheduled: false)
    }

    @Test func unscheduledAreActiveAndNeverArchived() {
        let exam = unscheduled("Fisica")
        #expect(exam.isActive(today: today, calendar: rome))
        #expect([exam].archived(today: today, calendar: rome).isEmpty)
    }

    @Test func unscheduledComeLastInAlphabeticalOrder() {
        let exams = [
            unscheduled("fisica"),
            Exam(name: "Chimica", date: date(2026, 12, 1)),
            unscheduled("Algebra"),
            Exam(name: "Analisi", date: date(2026, 11, 20)),
            unscheduled("Basi di dati"),
        ]
        #expect(exams.active(today: today, calendar: rome).map(\.name)
            == ["Analisi", "Chimica", "Algebra", "Basi di dati", "fisica"])
    }

    @Test func nextExamIgnoresUnscheduled() {
        let exams = [unscheduled("Algebra"), Exam(name: "Chimica", date: date(2026, 12, 1))]
        #expect(exams.nextExam(today: today, calendar: rome)?.name == "Chimica")
        #expect([unscheduled("Algebra")].nextExam(today: today, calendar: rome) == nil)
    }

    @Test func todayMarkerShownForUnscheduled() {
        let exam = Exam(name: "A", date: date(2026, 1, 1), tasks: [
            StudyTask(title: "Fatto", dueDate: date(2026, 11, 1)),
            StudyTask(title: "Dopo", dueDate: date(2026, 12, 1)),
        ], isScheduled: false)
        #expect(exam.todayMarkerIndex(today: today, calendar: rome) == 1)
    }

    @Test func oldDataIsScheduled() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Analisi","date":"2026-11-10T11:00:00Z",
          "tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([Exam].self, from: Data(json.utf8)).first?.isScheduled == true)
    }
}

@MainActor
@Suite struct ScheduledStoreTests {
    func makeStore() -> ExamStore {
        ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
    }

    @Test func unscheduledTasksAreNotClampedToExamDate() {
        let store = makeStore()
        let exam = Exam(name: "A", date: date(2026, 1, 1), isScheduled: false)
        store.addExam(exam)
        store.addTask(StudyTask(title: "T", dueDate: date(2026, 12, 1)), toExam: exam.id)
        #expect(store.exam(id: exam.id)?.tasks.first?.dueDate == date(2026, 12, 1))
    }

    @Test func updateDetailsSetsScheduled() {
        let store = makeStore()
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        store.addExam(exam)
        store.updateExamDetails(id: exam.id, name: "A", date: date(2026, 12, 1), degree: .triennale,
                                cfu: 6, isFinalTest: false, isScheduled: false, startTime: nil)
        #expect(store.exam(id: exam.id)?.isScheduled == false)
    }
}
