import Foundation

/// Media, crediti e voto di laurea stimato di un corso, per il widget "Media e simulazione".
public struct CareerSummary: Equatable, Sendable {
    public var degree: Degree
    public var average: Double?
    public var earnedCFU: Int
    /// 180 per la triennale, 120 per la magistrale (tesi compresa).
    public var totalCFU: Int
    public var estimate: GraduationEstimate?
    /// Con i voti ipotetici del simulatore; nil se nel corso non c'è nessuna simulazione.
    public var simulatedAverage: Double?
    public var simulatedEstimate: GraduationEstimate?

    public init(degree: Degree, average: Double?, earnedCFU: Int, totalCFU: Int, estimate: GraduationEstimate?,
                simulatedAverage: Double? = nil, simulatedEstimate: GraduationEstimate? = nil) {
        self.degree = degree
        self.average = average
        self.earnedCFU = earnedCFU
        self.totalCFU = totalCFU
        self.estimate = estimate
        self.simulatedAverage = simulatedAverage
        self.simulatedEstimate = simulatedEstimate
    }

    public var cfuProgress: Double { totalCFU == 0 ? 0 : min(1, Double(earnedCFU) / Double(totalCFU)) }

    public static func make(from exams: [Exam], degree: Degree, thesis: ThesisType) -> CareerSummary {
        func estimate(_ exams: [Exam]) -> GraduationEstimate? {
            degree == .triennale ? exams.graduationEstimate() : exams.masterGraduationEstimate(thesis: thesis)
        }
        let simulatedAverage = exams.simulatedAverage(degree: degree)
        return CareerSummary(
            degree: degree,
            average: exams.weightedAverage(degree: degree),
            earnedCFU: exams.earnedCFU(degree: degree),
            totalCFU: degree == .triennale ? Exam.triennaleCFU : Exam.magistraleCourseCFU + Exam.thesisCFU,
            estimate: estimate(exams),
            simulatedAverage: simulatedAverage,
            simulatedEstimate: simulatedAverage == nil ? nil : estimate(exams.applyingSimulation())
        )
    }

    /// Corso da mostrare quando non è scelto: quello fisso delle preferenze, altrimenti la magistrale
    /// se ha già esami, altrimenti la triennale.
    public static func automaticDegree(exams: [Exam], visibility: DegreeVisibility) -> Degree {
        if let fixed = visibility.fixedDegree { return fixed }
        return exams.contains { $0.degree == .magistrale } ? .magistrale : .triennale
    }

    private static let italian = Locale(identifier: "it_IT")

    /// "27,45", oppure "—" senza voti.
    public static func averageText(_ average: Double?) -> String {
        average.map { $0.formatted(.number.precision(.fractionLength(2)).locale(italian)) } ?? "—"
    }

    /// Voto in centodecimi arrotondato ("98", "98–103", "110+").
    public static func gradeText(_ estimate: GraduationEstimate) -> String {
        func grade(_ value: Double) -> String {
            value >= 110.5 ? "110+" : String(Int(value.rounded()))
        }
        let low = grade(estimate.minimum)
        let high = grade(estimate.maximum)
        return low == high ? low : "\(low)–\(high)"
    }
}

public extension ThesisType {
    /// Chiave nelle preferenze condivise: la legge anche il widget.
    static let storageKey = "thesisType"
}
