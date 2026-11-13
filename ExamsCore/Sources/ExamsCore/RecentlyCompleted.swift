import Foundation

/// Task spuntati da poco dal widget: restano visibili, barrati, per `window` secondi prima di sparire.
/// Salvati nelle preferenze condivise, perché l'azione del widget e la timeline sono processi distinti.
public struct RecentlyCompleted {
    public static let window: TimeInterval = 3
    static let storageKey = "widgetRecentlyCompleted"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Task ancora da mostrare barrati a `date`, con l'istante in cui spariscono.
    public func active(at date: Date) -> [UUID: Date] {
        let saved = defaults.dictionary(forKey: Self.storageKey) as? [String: Double] ?? [:]
        var result: [UUID: Date] = [:]
        for (key, completedAt) in saved {
            let expiry = Date(timeIntervalSince1970: completedAt + Self.window)
            if let id = UUID(uuidString: key), expiry > date {
                result[id] = expiry
            }
        }
        return result
    }

    /// Annota un task appena spuntato, o lo toglie se è stato riaperto; elimina le voci scadute.
    public func set(taskID: UUID, isDone: Bool, at date: Date) {
        var saved = (defaults.dictionary(forKey: Self.storageKey) as? [String: Double] ?? [:])
            .filter { $0.value + Self.window > date.timeIntervalSince1970 }
        saved[taskID.uuidString] = isDone ? date.timeIntervalSince1970 : nil
        defaults.set(saved, forKey: Self.storageKey)
    }
}
