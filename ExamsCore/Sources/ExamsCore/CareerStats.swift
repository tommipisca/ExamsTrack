import Foundation

/// Stima del voto di laurea in centodecimi, prima dell'arrotondamento.
/// Minimo e massimo coprono i CFU ancora senza voto e i punti finali non ancora noti.
public struct GraduationEstimate: Equatable, Sendable {
    public var minimum: Double
    public var maximum: Double
    /// Punteggio minimo, prima dell'arrotondamento, per poter ricevere la lode: max(113 − 0,5 × lodi, 111).
    public var honorsThreshold: Double
    /// Vero se il massimo raggiunge la soglia e il regolamento ammette la lode.
    public var canGetHonors: Bool

    public var isRange: Bool { maximum - minimum > 0.0001 }

    public init(minimum: Double, maximum: Double, honorsThreshold: Double, canGetHonors: Bool) {
        self.minimum = minimum
        self.maximum = maximum
        self.honorsThreshold = honorsThreshold
        self.canGetHonors = canGetHonors
    }
}

/// Tipo di tesi magistrale: decide il massimo dei punti assegnati dalla commissione.
public enum ThesisType: String, CaseIterable, Identifiable, Sendable {
    case withReviewer
    case withoutReviewer

    public var id: Self { self }

    public var label: String {
        switch self {
        case .withReviewer: "Con controrelatore"
        case .withoutReviewer: "Senza controrelatore"
        }
    }

    /// Punti massimi della tesi (8 solo con giudizio di eccellenza unanime, non stimabile).
    public var maximumPoints: Double {
        switch self {
        case .withReviewer: 7
        case .withoutReviewer: 4
        }
    }

    /// Punti minimi della tesi.
    public static let minimumPoints: Double = -1
}

public extension Exam {
    /// Voto valido per la media: 30 e lode conta 30; la tesi magistrale non ha voto.
    var countedGrade: Int? {
        passed == true && !isMasterThesis ? grade : nil
    }

    /// La tesi magistrale: si valuta con un punteggio bonus, non con un voto.
    var isMasterThesis: Bool {
        degree == .magistrale && isFinalTest
    }

    /// "+5", "+5,5", "−1"; nil senza punteggio.
    var thesisPointsLabel: String? {
        guard let thesisPoints else { return nil }
        let magnitude = abs(thesisPoints)
        let number = magnitude == magnitude.rounded()
            ? String(Int(magnitude))
            : String(format: "%.1f", magnitude).replacingOccurrences(of: ".", with: ",")
        return (thesisPoints < 0 ? "−" : "+") + number
    }

    /// CFU totali della laurea triennale.
    static let triennaleCFU = 180
    /// CFU degli insegnamenti della magistrale: 120 meno i 20 della tesi, che non ha un voto.
    static let magistraleCourseCFU = 100

    /// Riconosce dal nome una prova finale (triennale) o la tesi (magistrale).
    static func looksLikeFinalTest(name: String, degree: Degree = .triennale) -> Bool {
        let name = name.lowercased()
        switch degree {
        case .triennale: return name.contains("prova finale")
        case .magistrale: return name.contains("tesi") || name.contains("thesis")
        }
    }
}

public extension Array where Element == Exam {
    /// Media dei voti pesata sui CFU, per un corso di laurea; nil se non ci sono voti.
    func weightedAverage(degree: Degree) -> Double? {
        weightedAverage(of: filter { $0.degree == degree })
    }

    /// CFU degli esami superati in un corso di laurea.
    func earnedCFU(degree: Degree) -> Int {
        filter { $0.degree == degree && $0.passed == true }.reduce(0) { $0 + $1.cfu }
    }

    /// CFU della triennale ancora senza voto, rispetto ai 180 totali.
    func missingGraduationCFU() -> Int {
        missingCFU(degree: .triennale, total: Exam.triennaleCFU)
    }

    /// CFU di insegnamenti della magistrale ancora senza voto, rispetto ai 100 totali.
    func missingMasterCFU() -> Int {
        missingCFU(degree: .magistrale, total: Exam.magistraleCourseCFU)
    }

    /// Voto di laurea triennale: media × 110/30 + 1 + media delle prove finali / 6.
    /// I CFU mancanti valgono 18 per il minimo e 30 per il massimo; lo stesso le prove finali senza voto.
    func graduationEstimate() -> GraduationEstimate? {
        let triennale = filter { $0.degree == .triennale }
        guard let (low, high) = averageRange(of: triennale, missing: missingGraduationCFU()) else { return nil }
        let finalTests = weightedAverage(of: triennale.filter(\.isFinalTest))
        return estimate(
            minimum: low * 110 / 30 + 1 + (finalTests ?? 18) / 6,
            maximum: high * 110 / 30 + 1 + (finalTests ?? 30) / 6,
            exams: triennale,
            honorsAllowed: true
        )
    }

    /// Voto di laurea magistrale: media degli insegnamenti × 110/30 + punti della tesi (da −1 al massimo del tipo).
    /// I CFU mancanti valgono 18 per il minimo e 30 per il massimo.
    func masterGraduationEstimate(thesis: ThesisType) -> GraduationEstimate? {
        let magistrale = filter { $0.degree == .magistrale }
        guard let (low, high) = averageRange(of: magistrale, missing: missingMasterCFU()) else { return nil }
        // Con il punteggio della tesi già assegnato, si usa quello al posto dell'intervallo.
        let assigned = magistrale.first { $0.isMasterThesis && $0.passed == true && $0.thesisPoints != nil }?.thesisPoints
        return estimate(
            minimum: low * 110 / 30 + (assigned ?? ThesisType.minimumPoints),
            maximum: high * 110 / 30 + (assigned ?? thesis.maximumPoints),
            exams: magistrale,
            // La lode alla magistrale richiede la tesi con controrelatore.
            honorsAllowed: thesis == .withReviewer
        )
    }

    private func estimate(minimum: Double, maximum: Double, exams: [Exam], honorsAllowed: Bool) -> GraduationEstimate {
        let honorsCount = exams.filter { $0.passed == true && $0.honors && !$0.isMasterThesis }.count
        let threshold = Swift.max(113 - 0.5 * Double(honorsCount), 111)
        return GraduationEstimate(
            // Il voto minimo di laurea è comunque 66.
            minimum: Swift.max(minimum, 66),
            maximum: Swift.max(maximum, 66),
            honorsThreshold: threshold,
            canGetHonors: honorsAllowed && maximum >= threshold
        )
    }

    private func missingCFU(degree: Degree, total: Int) -> Int {
        let graded = filter { $0.degree == degree && $0.countedGrade != nil }.reduce(0) { $0 + $1.cfu }
        return Swift.max(0, total - graded)
    }

    /// Media pesata supponendo 18 (minimo) o 30 (massimo) nei CFU mancanti; nil senza voti.
    private func averageRange(of exams: [Exam], missing: Int) -> (low: Double, high: Double)? {
        let graded = exams.compactMap { exam in exam.countedGrade.map { (grade: $0, cfu: exam.cfu) } }
        guard !graded.isEmpty else { return nil }
        let points = graded.reduce(0) { $0 + $1.grade * $1.cfu }
        let totalCFU = Double(graded.reduce(0) { $0 + $1.cfu } + missing)
        return (Double(points + 18 * missing) / totalCFU, Double(points + 30 * missing) / totalCFU)
    }

    private func weightedAverage(of exams: [Exam]) -> Double? {
        let graded = exams.compactMap { exam in exam.countedGrade.map { (grade: $0, cfu: exam.cfu) } }
        let totalCFU = graded.reduce(0) { $0 + $1.cfu }
        guard totalCFU > 0 else { return nil }
        return Double(graded.reduce(0) { $0 + $1.grade * $1.cfu }) / Double(totalCFU)
    }
}
