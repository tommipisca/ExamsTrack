import SwiftUI
import ExamsCore

/// Stima del voto di laurea, media pesata e CFU conseguiti di un corso.
struct CareerStatsRow: View {
    let exams: [Exam]
    let degree: Degree
    @AppStorage(ThesisType.storageKey, store: AppGroup.sharedDefaults) private var thesis: ThesisType = .withReviewer
    @State private var showingSimulation = false
    @ScaledMetric(relativeTo: .largeTitle) private var gradeSize: CGFloat = 44

    static let italian = Locale(identifier: "it_IT")

    static func averageText(_ average: Double?) -> String {
        average.map { $0.formatted(.number.precision(.fractionLength(2)).locale(italian)) } ?? "—"
    }

    var body: some View {
        let average = exams.weightedAverage(degree: degree)
        let estimate = degree == .triennale
            ? exams.graduationEstimate()
            : exams.masterGraduationEstimate(thesis: thesis)

        VStack(alignment: .leading, spacing: 14) {
            Group {
                // In evidenza: il voto di laurea ottenibile.
                VStack(spacing: 2) {
                    Text(estimate.map(format) ?? "—")
                        .font(.system(size: gradeSize, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(Theme.gold)
                    Text("Voto di laurea")
                        .font(.ui(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)
            }

            HStack(alignment: .top, spacing: 0) {
                stat(title: "Media", value: Self.averageText(average), color: Theme.accent)
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1, height: 40)
                stat(
                    title: "CFU",
                    value: "\(exams.earnedCFU(degree: degree))/\(totalCFU)",
                    color: Theme.textPrimary
                )
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1, height: 40)
                // Tocca per aprire il simulatore "e se".
                Button {
                    showingSimulation = true
                } label: {
                    simulatedStat
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Apre il simulatore dei voti")
            }
            .sheet(isPresented: $showingSimulation) {
                SimulationView(degree: degree)
            }

            if let note = note(estimate: estimate) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var totalCFU: Int {
        degree == .triennale ? Exam.triennaleCFU : 120
    }

    /// Media simulata, oppure un invito a simulare se non c'è ancora nessun voto ipotetico.
    private var simulatedStat: some View {
        let simulated = exams.simulatedAverage(degree: degree)
        return VStack(spacing: 2) {
            if let simulated {
                Text(Self.averageText(simulated))
                    .font(.ui(.title2, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(Theme.success)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(Theme.success)
                    .frame(height: 28)
            }
            HStack(spacing: 3) {
                Text("Media simulata")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func stat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ui(.title2, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Voto in centodecimi arrotondato; oltre 110 diventa "110+".
    private func format(_ estimate: GraduationEstimate) -> String {
        Self.gradeText(estimate)
    }

    /// Voto in centodecimi arrotondato ("98", "98–103", "110+").
    static func gradeText(_ estimate: GraduationEstimate) -> String {
        func grade(_ value: Double) -> String {
            value >= 110.5 ? "110+" : String(Int(value.rounded()))
        }
        let low = grade(estimate.minimum)
        let high = grade(estimate.maximum)
        return low == high ? low : "\(low)–\(high)"
    }

    private func note(estimate: GraduationEstimate?) -> String? {
        guard let estimate else { return nil }
        var parts: [String] = []
        let missingCFU = degree == .triennale ? exams.missingGraduationCFU() : exams.missingMasterCFU()
        if missingCFU > 0 {
            parts.append("Minimo e massimo supponendo 18 o 30 nei \(missingCFU) CFU ancora senza voto.")
        }
        switch degree {
        case .triennale:
            if !exams.contains(where: { $0.degree == .triennale && $0.isFinalTest && $0.countedGrade != nil }) {
                parts.append("Anche le prove finali sono stimate tra 18 e 30.")
            }
        case .magistrale:
            if let assigned = exams.first(where: { $0.isMasterThesis && $0.passed == true && $0.thesisPoints != nil }),
               let points = assigned.thesisPointsLabel {
                parts.append("Punteggio della tesi: \(points).")
            } else {
                parts.append("Tesi \(thesis.label.lowercased()): da −1 a +\(Int(thesis.maximumPoints)) punti.")
            }
        }
        if estimate.canGetHonors {
            let threshold = estimate.honorsThreshold.formatted(.number.precision(.fractionLength(0...1)).locale(Self.italian))
            parts.append("Lode possibile da \(threshold) punti prima dell'arrotondamento, con voto unanime della commissione.")
        }
        return parts.joined(separator: " ")
    }
}
