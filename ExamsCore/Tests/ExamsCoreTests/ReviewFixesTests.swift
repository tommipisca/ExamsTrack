import Foundation
import Testing
@testable import ExamsCore

/// Problemi trovati dalla revisione del 2026-10-13.
@Suite struct ReviewSyncFixesTests {
    let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    // Importante 1: una simulazione recente non deve cancellare un voto vero arrivato da un altro dispositivo.
    @Test func simulationDoesNotOverrideRealGrade() {
        let fromIPhone = Exam(id: id, name: "X", date: date(2026, 12, 1), passed: true, grade: 28,
                              modifiedAt: date(2026, 11, 1, 10, 0))
        var onIPad = Exam(id: id, name: "X", date: date(2026, 12, 1), modifiedAt: date(2026, 10, 30, 9, 0),
                          simulatedGrade: 30)
        onIPad.simulationModifiedAt = date(2026, 11, 1, 10, 5)
        let merged = SyncMerger.merge(local: SyncSnapshot(exams: [onIPad]), remote: SyncSnapshot(exams: [fromIPhone]))
        #expect(merged.exams.first?.grade == 28)
        #expect(merged.exams.first?.passed == true)
        // La simulazione più recente sopravvive comunque, separata dal resto.
        #expect(merged.exams.first?.simulatedGrade == 30)
    }

    @Test func newerSimulationClearWins() {
        var cleared = Exam(id: id, name: "X", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))
        cleared.simulationModifiedAt = date(2026, 11, 2)
        var simulated = Exam(id: id, name: "X", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1), simulatedGrade: 27)
        simulated.simulationModifiedAt = date(2026, 11, 1, 18)
        let merged = SyncMerger.merge(local: SyncSnapshot(exams: [simulated]), remote: SyncSnapshot(exams: [cleared]))
        #expect(merged.exams.first?.simulatedGrade == nil)
    }

    // Minore 8: id duplicati vengono rimossi.
    @Test func duplicateIDsAreRemoved() {
        let a = Exam(id: id, name: "Primo", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))
        let b = Exam(id: id, name: "Doppione", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))
        #expect(SyncMerger.merge(local: SyncSnapshot(exams: [a, b]), remote: SyncSnapshot()).exams.count == 1)
    }

    // Minore 1: l'ordine diverso tra dispositivi non conta come differenza.
    @Test func sameContentInDifferentOrderIsEquivalent() {
        let a = Exam(name: "A", date: date(2026, 12, 1))
        let b = Exam(name: "B", date: date(2026, 12, 1))
        #expect(SyncSnapshot(exams: [a, b]).hasSameContent(as: SyncSnapshot(exams: [b, a])))
        #expect(!SyncSnapshot(exams: [a]).hasSameContent(as: SyncSnapshot(exams: [b])))
    }
}

@MainActor
@Suite struct ReviewStoreFixesTests {
    let clock = TestClock()

    func makeStore() -> ExamStore {
        let clock = self.clock
        return ExamStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("exams.json"),
            calendar: rome, now: { clock.now })
    }

    // Importante 1: la simulazione non cambia la data di modifica dell'esame.
    @Test func simulationDoesNotTouchModifiedAt() {
        let store = makeStore()
        clock.now = date(2026, 11, 1, 10, 0)
        let exam = Exam(name: "X", date: date(2026, 12, 1))
        store.addExam(exam)
        clock.now = date(2026, 11, 2, 10, 0)
        store.setSimulatedGrade(examID: exam.id, grade: 27)
        #expect(store.exam(id: exam.id)?.modifiedAt == date(2026, 11, 1, 10, 0))
        #expect(store.exam(id: exam.id)?.simulationModifiedAt == date(2026, 11, 2, 10, 0))
        store.clearSimulation(degree: .triennale)
        #expect(store.exam(id: exam.id)?.modifiedAt == date(2026, 11, 1, 10, 0))
    }

    // Importante 2: con l'orologio indietro rispetto a una modifica arrivata da un altro dispositivo,
    // le modifiche e le eliminazioni locali devono comunque risultare più recenti.
    @Test func editsAndDeletionsStayNewerThanSkewedTimestamps() {
        let store = makeStore()
        let future = date(2026, 11, 1, 10, 5)
        let exam = Exam(name: "X", date: date(2026, 12, 1), modifiedAt: future)
        store.applySynced(SyncSnapshot(exams: [exam]))

        clock.now = date(2026, 11, 1, 10, 1)
        store.addTask(StudyTask(title: "T", dueDate: date(2026, 11, 20)), toExam: exam.id)
        let edited = store.exam(id: exam.id)?.modifiedAt ?? .distantPast
        #expect(edited > future)

        store.deleteExam(id: exam.id)
        #expect((store.syncSnapshot.deletions[exam.id.uuidString] ?? .distantPast) > edited)
    }

    // Minore 8: un backup con id duplicati non crea doppioni.
    @Test func importRemovesDuplicateIDs() throws {
        let store = makeStore()
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try store.importBackup(encoder.encode([exam, exam]))
        #expect(store.exams.count == 1)
    }
}

@Suite struct ReviewNotificationFixesTests {
    let settings = NotificationSettings(examReminders: [.sameDay], dailyTaskSummary: false, hour: 9, minute: 0)

    // Importante 4: l'avviso immediato di scadenza arriva una volta sola per profilo.
    @Test func immediateExpirationWarningOnlyOnce() {
        let now = date(2026, 10, 19, 18, 0)
        let expiration = date(2026, 10, 20, 8, 15)
        let first = NotificationPlanner.plan(exams: [], settings: settings, now: now, calendar: rome,
                                             appExpiration: expiration, warnedExpiration: nil)
        #expect(first.count == 1)
        let again = NotificationPlanner.plan(exams: [], settings: settings, now: now, calendar: rome,
                                             appExpiration: expiration, warnedExpiration: expiration)
        #expect(again.isEmpty)
    }

    @Test func scheduledExpirationWarningIsNotSuppressed() {
        // Se la notifica del giorno prima è ancora nel futuro, resta pianificata.
        let expiration = date(2026, 10, 20, 8, 15)
        let plan = NotificationPlanner.plan(exams: [], settings: settings, now: date(2026, 10, 14), calendar: rome,
                                            appExpiration: expiration, warnedExpiration: expiration)
        #expect(plan.map(\.id) == ["app-expiration"])
    }

    // Minore 9: il promemoria del giorno stesso arriva prima dell'inizio dell'esame.
    @Test func sameDayReminderBeforeEarlyExam() {
        let exam = Exam(name: "A", date: date(2026, 11, 20), startTime: 8 * 60 + 30)
        let plan = NotificationPlanner.plan(exams: [exam], settings: settings, now: date(2026, 11, 1), calendar: rome)
        #expect(plan.first?.fireDate == date(2026, 11, 20, 7, 30))
    }
}

@Suite struct ReviewCareerFixesTests {
    // Minore 15: la lode rimasta su un esame diventato tesi non conta.
    @Test func thesisHonorsDoNotCount() throws {
        let thesis = Exam(name: "Tesi", date: date(2026, 1, 10), passed: true, honors: true,
                          degree: .magistrale, cfu: 20, isFinalTest: true)
        let course = Exam(name: "C", date: date(2026, 1, 10), passed: true, grade: 30, degree: .magistrale, cfu: 100)
        let estimate = try #require([thesis, course].masterGraduationEstimate(thesis: .withReviewer))
        #expect(estimate.honorsThreshold == 113)
    }
}
