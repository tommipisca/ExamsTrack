import Foundation
import Testing

/// Calendario fisso (Europa/Roma) per test deterministici, compreso il cambio dell'ora legale.
let rome: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
    return calendar
}()

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    rome.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Test che usano `UserDefaults`: su Linux le suite non sono isolate tra test in parallelo,
/// quindi questi girano uno alla volta.
@Suite(.serialized) struct DefaultsBackedTests {}
