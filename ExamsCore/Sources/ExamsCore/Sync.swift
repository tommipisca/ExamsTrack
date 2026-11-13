import Foundation

/// Contenuto del file di sincronizzazione condiviso tra dispositivi.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var exams: [Exam]
    /// Esami eliminati (id → data dell'eliminazione), perché non ricompaiano da un altro dispositivo.
    public var deletions: [String: Date]

    public init(exams: [Exam] = [], deletions: [String: Date] = [:]) {
        self.exams = exams
        self.deletions = deletions
    }

    /// Stesso contenuto, a prescindere dall'ordine degli esami (che può differire tra dispositivi).
    public func hasSameContent(as other: SyncSnapshot) -> Bool {
        deletions == other.deletions && Set(exams) == Set(other.exams) && exams.count == other.exams.count
    }

    public func encoded() throws -> Data {
        try SyncMerger.makeEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> SyncSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncSnapshot.self, from: data)
    }
}

/// Unisce i dati di due dispositivi esame per esame.
public enum SyncMerger {
    /// Per ogni esame vince la versione modificata più di recente; un'eliminazione vince sulle
    /// modifiche precedenti. L'ordine è quello locale, poi gli esami arrivati dall'altro dispositivo.
    public static func merge(local: SyncSnapshot, remote: SyncSnapshot) -> SyncSnapshot {
        var deletions = local.deletions
        for (id, deletedAt) in remote.deletions {
            deletions[id] = max(deletions[id] ?? deletedAt, deletedAt)
        }

        func survives(_ exam: Exam) -> Bool {
            guard let deletedAt = deletions[exam.id.uuidString] else { return true }
            return (exam.modifiedAt ?? .distantPast) > deletedAt
        }

        let localExams = unique(local.exams)
        let remoteExams = unique(remote.exams)
        let remoteByID = Dictionary(remoteExams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localIDs = Set(localExams.map(\.id))
        var merged: [Exam] = []
        for exam in localExams {
            let winner = remoteByID[exam.id].map { combine(exam, $0) } ?? exam
            if survives(winner) { merged.append(winner) }
        }
        for exam in remoteExams where !localIDs.contains(exam.id) && survives(exam) {
            merged.append(exam)
        }
        return SyncSnapshot(exams: merged, deletions: deletions)
    }

    /// Il resto dell'esame dalla versione più recente; la simulazione dalla simulazione più recente.
    static func combine(_ local: Exam, _ remote: Exam) -> Exam {
        var winner = newer(remote, local)
        let localSimulation = local.simulationModifiedAt ?? .distantPast
        let remoteSimulation = remote.simulationModifiedAt ?? .distantPast
        if localSimulation != remoteSimulation {
            let source = localSimulation > remoteSimulation ? local : remote
            winner.simulatedGrade = source.simulatedGrade
            winner.simulationModifiedAt = source.simulationModifiedAt
        }
        return winner
    }

    /// Un solo esame per id (il primo), per non mandare in crash le liste con id duplicati.
    static func unique(_ exams: [Exam]) -> [Exam] {
        var seen = Set<UUID>()
        return exams.filter { seen.insert($0.id).inserted }
    }

    /// La versione più recente; a parità di data sceglie in base al contenuto,
    /// così entrambi i dispositivi arrivano allo stesso risultato.
    static func newer(_ a: Exam, _ b: Exam) -> Exam {
        let dateA = a.modifiedAt ?? .distantPast
        let dateB = b.modifiedAt ?? .distantPast
        if dateA != dateB { return dateA > dateB ? a : b }
        if a == b { return a }
        let encoder = makeEncoder()
        let dataA = (try? encoder.encode(a)) ?? Data()
        let dataB = (try? encoder.encode(b)) ?? Data()
        return dataA.lexicographicallyPrecedes(dataB) ? b : a
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
