import Foundation
import Testing
@testable import ExamsCore

@Suite struct PreciseCountdownTests {
    /// Esame il 24/11 alle 14:30.
    let exam = Exam(name: "A", date: date(2026, 11, 24), startTime: 14 * 60 + 30)

    func countdown(at now: Date) -> PreciseCountdown? {
        exam.preciseCountdown(now: now, calendar: rome)
    }

    @Test func nilWithoutTime() {
        #expect(Exam(name: "A", date: date(2026, 11, 24)).preciseCountdown(now: date(2026, 11, 10), calendar: rome) == nil)
    }

    @Test func nilForUnscheduled() {
        let unscheduled = Exam(name: "A", date: date(2026, 11, 24), isScheduled: false, startTime: 600)
        #expect(unscheduled.preciseCountdown(now: date(2026, 11, 10), calendar: rome) == nil)
    }

    @Test func startDate() {
        #expect(exam.startDate(calendar: rome) == date(2026, 11, 24, 14, 30))
    }

    @Test func daysAndHours() {
        // 18:00 del 12/11 → 11 giorni e 20 ore e mezza.
        #expect(countdown(at: date(2026, 11, 12, 18, 0)) == .remaining(value: 11, unit: "giorni", detail: "e 20 ore"))
    }

    @Test func singularUnits() {
        #expect(countdown(at: date(2026, 11, 23, 13, 30)) == .remaining(value: 1, unit: "giorno", detail: "e 1 ora"))
        #expect(countdown(at: date(2026, 11, 24, 13, 29)) == .remaining(value: 1, unit: "ora", detail: "e 1 minuto"))
    }

    @Test func exactDaysHaveNoDetail() {
        #expect(countdown(at: date(2026, 11, 22, 14, 30)) == .remaining(value: 2, unit: "giorni", detail: nil))
    }

    @Test func hoursAndMinutesOnExamDay() {
        #expect(countdown(at: date(2026, 11, 24, 11, 10)) == .remaining(value: 3, unit: "ore", detail: "e 20 minuti"))
    }

    @Test func minutesOnly() {
        #expect(countdown(at: date(2026, 11, 24, 14, 10)) == .remaining(value: 20, unit: "minuti", detail: nil))
    }

    @Test func lessThanAMinute() {
        let now = date(2026, 11, 24, 14, 29).addingTimeInterval(30)
        #expect(countdown(at: now) == .lessThanAMinute)
    }

    @Test func startedOnExamDay() {
        #expect(countdown(at: date(2026, 11, 24, 14, 30)) == .started)
        #expect(countdown(at: date(2026, 11, 24, 18, 0)) == .started)
    }

    @Test func acrossDaylightSavingChange() {
        // L'ora legale termina il 25/10/2026: il giorno ha 25 ore.
        let exam = Exam(name: "A", date: date(2026, 10, 26), startTime: 9 * 60)
        #expect(exam.preciseCountdown(now: date(2026, 10, 24, 9, 0), calendar: rome) == .remaining(value: 2, unit: "giorni", detail: nil))
    }

    @Test func startTimeLabel() {
        #expect(exam.startTimeLabel == "14:30")
        #expect(Exam(name: "A", date: date(2026, 11, 24), startTime: 9 * 60 + 5).startTimeLabel == "9:05")
        #expect(Exam(name: "A", date: date(2026, 11, 24)).startTimeLabel == nil)
    }
}

@Suite struct StartTimeCodingTests {
    @Test func oldDataHasNoTime() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Analisi","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([Exam].self, from: Data(json.utf8)).first?.startTime == nil)
    }
}

@MainActor
@Suite struct StartTimeStoreTests {
    @Test func updateDetailsSetsStartTimeAndKeepsDateAtNoon() {
        let store = ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        store.addExam(exam)
        store.updateExamDetails(id: exam.id, name: "A", date: date(2026, 12, 1, 8, 0), degree: .triennale,
                                cfu: 6, isFinalTest: false, isScheduled: true, startTime: 9 * 60)
        #expect(store.exam(id: exam.id)?.startTime == 540)
        #expect(store.exam(id: exam.id)?.date == date(2026, 12, 1, 12, 0))
    }

    @Test func invalidStartTimeIsDropped() {
        let store = ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"), calendar: rome)
        let exam = Exam(name: "A", date: date(2026, 12, 1), startTime: 2000)
        store.addExam(exam)
        #expect(store.exam(id: exam.id)?.startTime == nil)
    }
}
