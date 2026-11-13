import SwiftUI
import ExamsCore

/// Esito di un esame passato: da inserire / superato con voto e lode / non superato.
struct OutcomeSection: View {
    @Environment(ExamStore.self) private var store
    let exam: Exam

    var body: some View {
        Section {
            // Un unico riquadro arrotondato, come le note: nella lista "semplice" del dettaglio
            // le righe separate verrebbero disegnate squadrate.
            VStack(spacing: 0) {
                Picker("Esito", selection: passedBinding) {
                    Text("Da inserire").tag(Bool?.none)
                    Text("Superato").tag(Bool?.some(true))
                    Text("Non superato").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 12)

                if exam.passed == true, exam.isMasterThesis {
                    divider
                    // La tesi non ha voto: si inserisce il punteggio assegnato dalla commissione.
                    Stepper(value: thesisPointsBinding, in: -1...8, step: 0.5) {
                        HStack {
                            Text("Punteggio tesi")
                            Spacer()
                            Text(exam.thesisPointsLabel ?? "—")
                                .font(.ui(.body, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    .padding(.vertical, 10)
                } else if exam.passed == true {
                    divider
                    HStack {
                        Text("Voto")
                        Spacer()
                        Picker("Voto", selection: gradeBinding) {
                            ForEach(18...30, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 6)
                    if exam.grade == 30 {
                        divider
                        Toggle("Lode", isOn: honorsBinding)
                            .tint(Theme.gold)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .animation(.snappy, value: exam.passed)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Esito").sectionHeaderStyle()
        } footer: {
            if exam.isMasterThesis {
                Text("Da −1 a +7 punti con controrelatore (+8 con giudizio di eccellenza), fino a +4 senza.")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
    }

    private var thesisPointsBinding: Binding<Double> {
        Binding(
            get: { exam.thesisPoints ?? 0 },
            set: { store.setThesisPoints(examID: exam.id, points: $0) }
        )
    }

    private var passedBinding: Binding<Bool?> {
        Binding(
            get: { exam.passed },
            set: { store.setOutcome(examID: exam.id, passed: $0, grade: exam.grade, honors: exam.honors) }
        )
    }

    private var gradeBinding: Binding<Int> {
        Binding(
            get: { exam.grade ?? 18 },
            set: { store.setOutcome(examID: exam.id, passed: true, grade: $0, honors: exam.honors) }
        )
    }

    private var honorsBinding: Binding<Bool> {
        Binding(
            get: { exam.honors },
            set: { store.setOutcome(examID: exam.id, passed: true, grade: exam.grade, honors: $0) }
        )
    }
}
