import Foundation

public enum Countdown {
    /// "Oggi", "Domani", "tra 12 giorni".
    public static func label(days: Int) -> String {
        switch days {
        case ..<0: "Passato"
        case 0: "Oggi"
        case 1: "Domani"
        default: "tra \(days) giorni"
        }
    }

    /// Per la lista: "Oggi", "Domani", "12 giorni".
    public static func shortLabel(days: Int) -> String {
        switch days {
        case ..<0: "Passato"
        case 0: "Oggi"
        case 1: "Domani"
        default: "\(days) giorni"
        }
    }

    /// Per il widget circolare: "Oggi", "12g".
    public static func compactLabel(days: Int) -> String {
        days == 0 ? "Oggi" : "\(days)g"
    }
}
