import Foundation

/// Profilo di installazione (`embedded.mobileprovision`): con l'account gratuito scade dopo 7 giorni.
public enum ProvisioningProfile {
    /// Data di scadenza dell'app installata; nil se il profilo manca (es. sul Simulatore).
    public static func embeddedExpirationDate(bundle: Bundle = .main) -> Date? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(from: data)
    }

    /// Il profilo è un plist XML racchiuso in una firma binaria: estrae il plist e legge `ExpirationDate`.
    public static func expirationDate(from data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil
              ) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }
}

/// Link che apre un esame nell'app (usato dai widget).
public enum ExamLink {
    public static func url(for examID: UUID) -> URL {
        URL(string: "examstrack://exam/\(examID.uuidString)")!
    }

    /// Apre la scheda "Oggi": il tocco generico sul widget.
    public static let todayURL = URL(string: "examstrack://today")!
    /// Apre la scheda Carriera (widget "Media e simulazione").
    public static let careerURL = URL(string: "examstrack://career")!
    /// Avvia una sessione di studio sul prossimo task di oggi (controllo del Centro di Controllo).
    public static let studyURL = URL(string: "examstrack://study")!

    public static func isToday(_ url: URL) -> Bool {
        url.scheme == "examstrack" && url.host == "today"
    }

    public static func isCareer(_ url: URL) -> Bool {
        url.scheme == "examstrack" && url.host == "career"
    }

    public static func isStudy(_ url: URL) -> Bool {
        url.scheme == "examstrack" && url.host == "study"
    }

    /// Apre l'esame sulla timeline, all'altezza di quel task.
    public static func url(for examID: UUID, taskID: UUID) -> URL {
        URL(string: "examstrack://exam/\(examID.uuidString)?task=\(taskID.uuidString)")!
    }

    public static func taskID(from url: URL) -> UUID? {
        guard examID(from: url) != nil,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "task" })?.value else { return nil }
        return UUID(uuidString: value)
    }

    public static func examID(from url: URL) -> UUID? {
        guard url.scheme == "examstrack", url.host == "exam" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
