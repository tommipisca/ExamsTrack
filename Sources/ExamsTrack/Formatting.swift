import Foundation

extension Date {
    private static let italian = Locale(identifier: "it_IT")

    /// "lunedì 10 novembre 2026"
    var italianLong: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Self.italian))
    }

    /// "10 nov"
    var italianShort: String {
        formatted(.dateTime.day().month(.abbreviated).locale(Self.italian))
    }

    /// "Domani", altrimenti "Sabato 15 nov", per i giorni dell'agenda.
    func agendaDayLabel(today: Date, calendar: Calendar = .current) -> String {
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(self, inSameDayAs: tomorrow) {
            return "Domani"
        }
        let label = formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Self.italian))
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}
