import SwiftUI
import ExamsCore

/// Simulatore "e se": voti ipotetici per gli esami senza voto e il loro effetto su media e voto di laurea.
/// I voti ipotetici si salvano negli esami, quindi restano e si sincronizzano tra i dispositivi.
struct SimulationView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ThesisType.storageKey, store: AppGroup.sharedDefaults) private var thesis: ThesisType = .withReviewer
    let degree: Degree
    @ScaledMetric(relativeTo: .title) private var summarySize: CGFloat = 32

    /// Esami del corso ancora senza voto, dal più vicino; quelli da programmare in fondo.
    private var candidates: [Exam] {
        store.exams
            .filter { $0.degree == degree && $0.isSimulatable }
            .sorted { lhs, rhs in
                if lhs.isScheduled != rhs.isScheduled { return lhs.isScheduled }
                return (lhs.date, lhs.name) < (rhs.date, rhs.name)
            }
    }

    var body: some View {
        let simulatedExams = store.exams.applyingSimulation()
        let estimate = degree == .triennale
            ? simulatedExams.graduationEstimate()
            : simulatedExams.masterGraduationEstimate(thesis: thesis)
        let hasSimulation = store.exams.contains { $0.degree == degree && $0.isSimulatable && $0.simulatedGrade != nil }

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        summaryStat(
                            value: CareerStatsRow.averageText(store.exams.simulatedAverage(degree: degree)),
                            title: "Media simulata",
                            color: Theme.success
                        )
                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(width: 1, height: 44)
                        summaryStat(
                            value: estimate.map(CareerStatsRow.gradeText) ?? "—",
                            title: "Voto di laurea",
                            color: Theme.gold
                        )
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Theme.surface)
                } footer: {
                    Text("Calcolati come se i voti ipotetici fossero veri. La media reale e la carriera non cambiano.")
                }

                Section {
                    if candidates.isEmpty {
                        Text("Tutti gli esami della \(degree.label.lowercased()) hanno già un voto.")
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(candidates) { exam in
                        SimulationRow(exam: exam)
                            .listRowBackground(Theme.surface)
                    }
                } header: {
                    Text("Esami senza voto").sectionHeaderStyle()
                } footer: {
                    if !candidates.isEmpty {
                        Text("Scegli un voto ipotetico per gli esami che vuoi simulare. Restano salvati finché non li togli o registri il voto vero.")
                    }
                }

                if hasSimulation {
                    Section {
                        Button("Azzera simulazione", role: .destructive) {
                            store.clearSimulation(degree: degree)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            .themedListBackground()
            .navigationTitle("Simulazione \(degree.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.background)
        .storeErrorAlert()
    }

    private func summaryStat(value: String, title: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: summarySize, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Un esame da simulare: nome, CFU e voto ipotetico.
private struct SimulationRow: View {
    @Environment(ExamStore.self) private var store
    let exam: Exam

    var body: some View {
        HStack(spacing: 12) {
            ColorBar(color: Theme.color(for: exam))
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.name)
                    .font(.ui(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text("\(exam.cfu) CFU")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Picker("Voto ipotetico", selection: Binding(
                get: { exam.simulatedGrade },
                set: { store.setSimulatedGrade(examID: exam.id, grade: $0) }
            )) {
                Text("—").tag(Int?.none)
                ForEach(18...30, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(exam.simulatedGrade == nil ? Theme.textSecondary : Theme.success)
        }
        .padding(.vertical, 2)
    }
}
