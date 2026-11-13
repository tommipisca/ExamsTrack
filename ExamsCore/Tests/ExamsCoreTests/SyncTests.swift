import Foundation
import Testing
@testable import ExamsCore

@Suite struct SyncMergeTests {
    let t0 = date(2026, 11, 1, 10, 0)
    let t1 = date(2026, 11, 1, 11, 0)
    let t2 = date(2026, 11, 1, 12, 0)

    func exam(_ id: UUID, _ name: String, modified: Date?) -> Exam {
        Exam(id: id, name: name, date: date(2026, 12, 1), modifiedAt: modified)
    }

    let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let c = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    @Test func newerEditWinsOnEitherSide() {
        let local = SyncSnapshot(exams: [exam(a, "Locale", modified: t2)])
        let remote = SyncSnapshot(exams: [exam(a, "Remoto", modified: t1)])
        #expect(SyncMerger.merge(local: local, remote: remote).exams.map(\.name) == ["Locale"])
        #expect(SyncMerger.merge(local: remote, remote: local).exams.map(\.name) == ["Locale"])
    }

    @Test func examsFromBothSidesAreKeptInLocalThenRemoteOrder() {
        let local = SyncSnapshot(exams: [exam(a, "A", modified: t0), exam(b, "B", modified: t0)])
        let remote = SyncSnapshot(exams: [exam(c, "C", modified: t1), exam(a, "A", modified: t0)])
        #expect(SyncMerger.merge(local: local, remote: remote).exams.map(\.name) == ["A", "B", "C"])
    }

    @Test func remoteDeletionRemovesOlderLocalExam() {
        let local = SyncSnapshot(exams: [exam(a, "A", modified: t0), exam(b, "B", modified: t0)])
        let remote = SyncSnapshot(exams: [exam(b, "B", modified: t0)], deletions: [a.uuidString: t1])
        let merged = SyncMerger.merge(local: local, remote: remote)
        #expect(merged.exams.map(\.name) == ["B"])
        #expect(merged.deletions[a.uuidString] == t1)
    }

    @Test func editAfterDeletionKeepsExam() {
        let local = SyncSnapshot(exams: [exam(a, "Modificato dopo", modified: t2)])
        let remote = SyncSnapshot(exams: [], deletions: [a.uuidString: t1])
        #expect(SyncMerger.merge(local: local, remote: remote).exams.map(\.name) == ["Modificato dopo"])
    }

    @Test func deletionsAreUnitedKeepingLatest() {
        let local = SyncSnapshot(exams: [], deletions: [a.uuidString: t0, b.uuidString: t2])
        let remote = SyncSnapshot(exams: [], deletions: [a.uuidString: t1])
        let merged = SyncMerger.merge(local: local, remote: remote)
        #expect(merged.deletions == [a.uuidString: t1, b.uuidString: t2])
    }

    @Test func legacyExamsWithoutDateLoseToDatedEdits() {
        let local = SyncSnapshot(exams: [exam(a, "Vecchio", modified: nil)])
        let remote = SyncSnapshot(exams: [exam(a, "Nuovo", modified: t0)])
        #expect(SyncMerger.merge(local: local, remote: remote).exams.map(\.name) == ["Nuovo"])
    }

    @Test func sameSecondConflictConvergesOnBothDevices() {
        let one = SyncSnapshot(exams: [exam(a, "iPhone", modified: t1)])
        let two = SyncSnapshot(exams: [exam(a, "iPad", modified: t1)])
        let onIPhone = SyncMerger.merge(local: one, remote: two)
        let onIPad = SyncMerger.merge(local: two, remote: one)
        #expect(onIPhone.exams == onIPad.exams)
    }

    @Test func mergeIsIdempotent() {
        let local = SyncSnapshot(exams: [exam(a, "A", modified: t2), exam(b, "B", modified: t0)], deletions: [c.uuidString: t1])
        let remote = SyncSnapshot(exams: [exam(a, "A vecchio", modified: t1), exam(c, "C", modified: t0)])
        let merged = SyncMerger.merge(local: local, remote: remote)
        #expect(SyncMerger.merge(local: merged, remote: remote) == merged)
        #expect(SyncMerger.merge(local: merged, remote: merged) == merged)
    }

    @Test func snapshotRoundTrip() throws {
        let snapshot = SyncSnapshot(exams: [exam(a, "A", modified: t1)], deletions: [b.uuidString: t2])
        #expect(try SyncSnapshot.decode(snapshot.encoded()) == snapshot)
        #expect(throws: (any Error).self) { try SyncSnapshot.decode(Data("rotto".utf8)) }
    }
}

@MainActor
@Suite struct SyncStoreTests {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("exams.json") }
    let clock = TestClock()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeStore() -> ExamStore {
        let clock = self.clock
        return ExamStore(fileURL: fileURL, calendar: rome, now: { clock.now })
    }

    @Test func changesStampModificationDate() {
        let store = makeStore()
        clock.now = date(2026, 11, 1, 10, 0)
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        store.addExam(exam)
        #expect(store.exam(id: exam.id)?.modifiedAt == date(2026, 11, 1, 10, 0))

        clock.now = date(2026, 11, 2, 9, 0)
        store.addTask(StudyTask(title: "T", dueDate: date(2026, 11, 20)), toExam: exam.id)
        #expect(store.exam(id: exam.id)?.modifiedAt == date(2026, 11, 2, 9, 0))
    }

    @Test func deletionIsRememberedAcrossLaunches() {
        let store = makeStore()
        let exam = Exam(name: "A", date: date(2026, 12, 1))
        store.addExam(exam)
        clock.now = date(2026, 11, 3, 8, 0)
        store.deleteExam(id: exam.id)
        #expect(makeStore().syncSnapshot.deletions[exam.id.uuidString] == date(2026, 11, 3, 8, 0))
    }

    @Test func applyingSameSnapshotDoesNotSave() {
        let store = makeStore()
        store.addExam(Exam(name: "A", date: date(2026, 12, 1)))
        var saves = 0
        store.onSave = { saves += 1 }
        store.applySynced(store.syncSnapshot)
        #expect(saves == 0)
    }

    @Test func applyingRemoteChangesSavesThem() {
        let store = makeStore()
        let remote = SyncSnapshot(exams: [Exam(name: "Dall'iPad", date: date(2026, 12, 1), modifiedAt: date(2026, 11, 1))])
        store.applySynced(remote)
        #expect(makeStore().exams.map(\.name) == ["Dall'iPad"])
    }

    @Test func importReplacesAndTombstonesMissingExams() throws {
        let store = makeStore()
        let old = Exam(name: "Vecchio", date: date(2026, 12, 1))
        store.addExam(old)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        clock.now = date(2026, 11, 5, 9, 0)
        try store.importBackup(encoder.encode([Exam(name: "Nuovo", date: date(2026, 12, 1))]))
        #expect(store.syncSnapshot.deletions[old.id.uuidString] == date(2026, 11, 5, 9, 0))
        #expect(store.exams.first?.modifiedAt == date(2026, 11, 5, 9, 0))
    }
}

/// Orologio controllabile dai test.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
}
