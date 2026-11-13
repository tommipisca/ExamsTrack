import Foundation
import Testing
@testable import ExamsCore

@Suite struct ExamSearchTests {
    var exams: [Exam] {
        var analisi = Exam(name: "Analisi Matematica 1", date: date(2026, 12, 1), tasks: [
            StudyTask(title: "Esercizi sugli integrali", dueDate: date(2026, 11, 20)),
        ])
        analisi.notes = "Orale facoltativo"
        let probabilita = Exam(name: "Probabilità e Statistica", date: date(2026, 1, 10), passed: true, grade: 25)
        return [analisi, probabilita]
    }

    @Test func emptyQueryMatchesNothingSpecial() {
        #expect(exams.matching("").count == 2)
        #expect(exams.matching("   ").count == 2)
    }

    @Test func matchesNameIgnoringCaseAndAccents() {
        #expect(exams.matching("probabilita").map(\.name) == ["Probabilità e Statistica"])
        #expect(exams.matching("ANALISI").map(\.name) == ["Analisi Matematica 1"])
    }

    @Test func matchesNotesAndTaskTitles() {
        #expect(exams.matching("orale").map(\.name) == ["Analisi Matematica 1"])
        #expect(exams.matching("integrali").map(\.name) == ["Analisi Matematica 1"])
    }

    @Test func allWordsMustMatch() {
        #expect(exams.matching("analisi orale").count == 1)
        #expect(exams.matching("analisi statistica").isEmpty)
    }
}

@Suite struct BackupRotationTests {
    @Test func keepsNewestAndIgnoresOtherFiles() {
        let names = [
            "ExamsTrack-backup-2026-10-01.json",
            "ExamsTrack-backup-2026-10-03.json",
            "ExamsTrack-backup-2026-10-02.json",
            "appunti.txt",
            "ExamsTrack-backup-2026-10-04.json",
        ]
        #expect(BackupRotation.filesToDelete(names, keep: 2) == [
            "ExamsTrack-backup-2026-10-02.json", "ExamsTrack-backup-2026-10-01.json",
        ])
    }

    @Test func nothingToDeleteUnderLimit() {
        #expect(BackupRotation.filesToDelete(["ExamsTrack-backup-2026-10-01.json"], keep: 14).isEmpty)
    }

    @Test func dailyFileName() {
        #expect(BackupRotation.fileName(for: date(2026, 10, 13), calendar: rome) == "ExamsTrack-backup-2026-10-13.json")
    }
}

@Suite struct ConflictMergeTests {
    @Test func mergesSeveralVersions() {
        let a = Exam(name: "A", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))
        let b = Exam(name: "B", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))
        let c = Exam(name: "C", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))
        let merged = SyncMerger.mergeAll(local: SyncSnapshot(exams: [a]),
                                         remotes: [SyncSnapshot(exams: [b]), SyncSnapshot(exams: [c])])
        #expect(merged.exams.map(\.name) == ["A", "B", "C"])
    }
}

@Suite struct BackupNameCalendarTests {
    // Revisione M3: con un calendario non gregoriano l'anno cambierebbe e l'ordine dei file si romperebbe.
    @Test func alwaysGregorianYear() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Europe/Rome")!
        #expect(BackupRotation.fileName(for: date(2026, 10, 13), calendar: buddhist) == "ExamsTrack-backup-2026-10-13.json")
    }
}
