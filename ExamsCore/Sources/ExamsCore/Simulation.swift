import Foundation

public extension Exam {
    /// Si può simulare un voto solo per esami senza voto vero; la tesi magistrale ha un punteggio, non un voto.
    var isSimulatable: Bool {
        countedGrade == nil && !isMasterThesis
    }
}

public extension Array where Element == Exam {
    /// Gli esami come se i voti ipotetici fossero veri, per riusare i calcoli di media e voto di laurea.
    func applyingSimulation() -> [Exam] {
        map { exam in
            guard exam.isSimulatable, let grade = exam.simulatedGrade else { return exam }
            var simulated = exam
            simulated.passed = true
            simulated.grade = grade
            simulated.honors = false
            return simulated
        }
    }

    /// Media pesata con i voti veri più quelli ipotetici; nil se nel corso non c'è nessuna simulazione.
    func simulatedAverage(degree: Degree) -> Double? {
        guard contains(where: { $0.degree == degree && $0.isSimulatable && $0.simulatedGrade != nil }) else {
            return nil
        }
        return applyingSimulation().weightedAverage(degree: degree)
    }
}
