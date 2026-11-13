import Foundation

public extension Array where Element == Exam {
    /// Esami che contengono tutte le parole cercate nel nome, nelle note o nei titoli dei task.
    /// Ignora maiuscole e accenti; una ricerca vuota restituisce tutto.
    func matching(_ query: String) -> [Exam] {
        let words = query.split(whereSeparator: \.isWhitespace).map { String($0).searchKey }
        guard !words.isEmpty else { return self }
        return filter { exam in
            let haystack = ([exam.name, exam.notes] + exam.tasks.map(\.title)).joined(separator: "\n").searchKey
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

private extension String {
    /// Testo normalizzato per la ricerca: minuscolo e senza accenti.
    var searchKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }
}

/// Backup automatici giornalieri nella cartella di sincronizzazione.
public enum BackupRotation {
    public static let folderName = "Backup"
    public static let keep = 14
    private static let prefix = "ExamsTrack-backup-"

    /// "ExamsTrack-backup-AAAA-MM-GG.json": il nome ordina i file per data.
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        // Sempre gregoriano (con il fuso del calendario dato): con altri calendari l'anno cambierebbe
        // e l'ordine alfabetico dei file, usato per cancellare i più vecchi, non sarebbe più cronologico.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "\(prefix)%04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// I backup più vecchi oltre i `keep` più recenti; altri file nella cartella non vengono toccati.
    public static func filesToDelete(_ names: [String], keep: Int = keep) -> [String] {
        let backups = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.sorted(by: >)
        return Array(backups.dropFirst(keep))
    }
}

public extension SyncMerger {
    /// Unisce più versioni remote, per esempio le copie in conflitto create da iCloud.
    static func mergeAll(local: SyncSnapshot, remotes: [SyncSnapshot]) -> SyncSnapshot {
        remotes.reduce(local) { merge(local: $0, remote: $1) }
    }
}
