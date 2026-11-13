import Foundation

/// Quali corsi di laurea mostrare: con un solo corso, gli esami dell'altro restano salvati ma nascosti.
public enum DegreeVisibility: String, CaseIterable, Identifiable, Sendable {
    case both
    case triennale
    case magistrale

    public var id: Self { self }

    /// Chiave della preferenza, salvata nello spazio condiviso dell'App Group per farla leggere anche al widget.
    public static let storageKey = "degreeVisibility"

    public var label: String {
        switch self {
        case .both: "Triennale e magistrale"
        case .triennale: "Solo triennale"
        case .magistrale: "Solo magistrale"
        }
    }

    /// Il corso attivo quando ne è mostrato uno solo.
    public var fixedDegree: Degree? {
        switch self {
        case .both: nil
        case .triennale: .triennale
        case .magistrale: .magistrale
        }
    }

    public func includes(_ degree: Degree) -> Bool {
        fixedDegree.map { $0 == degree } ?? true
    }

    /// Preferenza salvata nello spazio condiviso (app e widget).
    public static var saved: DegreeVisibility {
        DegreeVisibility(rawValue: AppGroup.sharedDefaults.string(forKey: storageKey) ?? "") ?? .both
    }
}

public extension Array where Element == Exam {
    func visible(_ visibility: DegreeVisibility) -> [Exam] {
        filter { visibility.includes($0.degree) }
    }
}
