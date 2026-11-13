import SwiftUI
import ExamsCore

/// Crea un nuovo esame (`exam == nil`) o modifica i dati di uno esistente.
struct ExamFormView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let exam: Exam?
    @State private var name: String
    @State private var date: Date
    /// Id del nuovo esame.
    @State private var newExamID = UUID()
    /// nil finché l'utente non sceglie: vale il corso dell'esame o quello dell'ultimo inserito.
    @State private var chosenDegree: Degree?

    @State private var cfu: Int
    @State private var showingDeletedAlert = false
    /// I dati com'erano all'apertura: `exam` invece si aggiorna con la sincronizzazione mentre il form è aperto.
    @State private var original: ExamDetails?
    @State private var isScheduled: Bool
    @State private var hasStartTime: Bool
    /// Solo ore e minuti contano.
    @State private var startTime: Date
    /// nil finché l'utente non tocca l'interruttore: si deduce dal nome ("prova finale").
    @State private var chosenFinalTest: Bool?

    @Environment(\.degreeVisibility) private var visibility

    private var degree: Degree {
        chosenDegree ?? exam?.degree ?? visibility.fixedDegree ?? store.defaultDegree
    }

    private var isFinalTest: Bool {
        chosenFinalTest ?? exam?.isFinalTest ?? Exam.looksLikeFinalTest(name: name, degree: degree)
    }

    init(exam: Exam?) {
        self.exam = exam
        _name = State(initialValue: exam?.name ?? "")
        _date = State(initialValue: exam?.date ?? Calendar.current.date(byAdding: .day, value: 30, to: .now)!)
        _cfu = State(initialValue: exam?.cfu ?? Exam.defaultCFU)
        _isScheduled = State(initialValue: exam?.isScheduled ?? true)
        _original = State(initialValue: exam.map(ExamDetails.init))
        _hasStartTime = State(initialValue: exam?.startTime != nil)
        let minutes = exam?.startTime ?? 9 * 60
        _startTime = State(initialValue: Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
        ) ?? .now)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ColorBar(color: Theme.color(index: exam?.colorIndex ?? store.nextColorIndex))
                        TextField("Nome esame, es. Analisi 1", text: $name)
                            .font(.ui(.body, weight: .semibold))
                    }
                    Toggle("Programmato", isOn: $isScheduled.animation())
                    if isScheduled {
                        DatePicker("Data dell'esame", selection: $date, displayedComponents: .date)
                        Toggle("Orario", isOn: $hasStartTime.animation())
                        if hasStartTime {
                            DatePicker("Inizio", selection: $startTime, displayedComponents: .hourAndMinute)
                        }
                    }
                    if visibility.fixedDegree == nil {
                        Picker("Corso", selection: Binding(get: { degree }, set: { chosenDegree = $0 })) {
                            ForEach(Degree.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Text("Ogni esame ha un suo colore, usato in lista e nella timeline.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Stepper(value: $cfu, in: 1...30) {
                        HStack {
                            Text("CFU")
                            Spacer()
                            Text("\(cfu)")
                                .font(.ui(.body, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    Toggle(degree == .magistrale ? "Tesi" : "Prova finale",
                           isOn: Binding(get: { isFinalTest }, set: { chosenFinalTest = $0 }))
                } footer: {
                    Text(degree == .magistrale
                         ? "I CFU pesano il voto nella media. La tesi non ha un voto: riceve un punteggio da −1 a +8 che si somma alla media."
                         : "I CFU pesano il voto nella media. Le prove finali danno i punti bonus del voto di laurea.")
                }
                .listRowBackground(Theme.surface)
            }
            .themedListBackground()
            .navigationTitle(exam == nil ? "Nuovo esame" : "Modifica esame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationBackground(Theme.background)
        // Tesi magistrale: propone 20 CFU se sono ancora quelli di default.
        .onChange(of: isFinalTest) { proposeThesisCFU() }
        .onChange(of: degree) { proposeThesisCFU() }
        .alert("Esame eliminato", isPresented: $showingDeletedAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Questo esame è stato eliminato su un altro dispositivo: le modifiche non sono state salvate.")
        }
        .storeErrorAlert()
    }

    /// Orario in minuti dalla mezzanotte, solo per esami programmati con orario.
    private var startMinutes: Int? {
        guard isScheduled, hasStartTime else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func proposeThesisCFU() {
        if degree == .magistrale, isFinalTest, cfu == Exam.defaultCFU {
            cfu = Exam.thesisCFU
        }
    }

    private func save() {
        if let exam {
            // L'esame potrebbe essere stato eliminato su un altro dispositivo mentre il form era aperto.
            guard let latest = store.exam(id: exam.id) else {
                showingDeletedAlert = true
                return
            }
            let edited = ExamDetails(name: trimmedName, date: date, degree: degree, cfu: cfu,
                                     isFinalTest: isFinalTest, isScheduled: isScheduled, startTime: startMinutes)
            // Solo i campi cambiati qui: le modifiche arrivate intanto dall'altro dispositivo restano.
            let merged = ExamDetails.merging(original: original ?? ExamDetails(exam), edited: edited, latest: ExamDetails(latest))
            store.updateExamDetails(id: exam.id, name: merged.name, date: merged.date, degree: merged.degree,
                                    cfu: merged.cfu, isFinalTest: merged.isFinalTest, isScheduled: merged.isScheduled,
                                    startTime: merged.startTime)
        } else {
            store.addExam(Exam(id: newExamID, name: trimmedName, date: date, degree: degree, cfu: cfu, isFinalTest: isFinalTest, isScheduled: isScheduled,
                startTime: startMinutes))
        }
        // Se il salvataggio fallisce resta aperto, così l'avviso compare qui.
        if store.lastError == nil {
            dismiss()
        }
    }
}
