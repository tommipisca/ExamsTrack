import SwiftUI
import ExamsCore

/// Scheda "Esami": esami da sostenere (prima i programmati, poi quelli da programmare), con ricerca.
/// Su iPad con spazio in larghezza diventa a due colonne: elenco a sinistra, dettaglio a destra.
struct ExamListView: View {
    /// Esami aperti, controllabile dall'esterno (link dai widget). Nelle due colonne è l'esame selezionato.
    @Binding var path: [UUID]
    /// Campo di ricerca attivo (⌘F lo attiva dalla tastiera).
    @Binding var isSearchPresented: Bool
    @Environment(ExamStore.self) private var store
    @Environment(\.today) private var today
    @Environment(\.degreeVisibility) private var visibility
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingNewExam = false
    @State private var examPendingDeletion: Exam?
    @State private var query = ""

    private var isSplit: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isSplit {
                NavigationSplitView {
                    list
                        // Gruppi arrotondati come nel resto dell'app, non le righe squadrate della barra laterale.
                        .listStyle(.insetGrouped)
                        .themedListBackground()
                        .floatingTabBarClearance()
                        .syncRefreshable()
                } detail: {
                    NavigationStack {
                        if let examID = path.last {
                            ExamDetailView(examID: examID)
                                .id(examID)
                        } else {
                            ContentUnavailableView("Seleziona un esame", systemImage: "sidebar.left",
                                                   description: Text("Il dettaglio compare qui."))
                                .background(Theme.background)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $path) {
                    list.tabScreenStyle()
                }
            }
        }
        .storeErrorAlert()
        .onChange(of: store.exams) {
            // Esame aperto eliminato (qui o sull'altro dispositivo): torna all'elenco.
            if let id = path.last, store.exam(id: id) == nil {
                path = []
            }
        }
    }

    /// Esame selezionato nelle due colonne, collegato al percorso usato dai link dei widget.
    private var selection: Binding<UUID?> {
        Binding(get: { path.last }, set: { path = $0.map { [$0] } ?? [] })
    }

    private var list: some View {
        let visible = store.exams.visible(visibility)
        let active = visible.active(today: today)

        return List(selection: isSplit ? selection : nil) {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                section("In programma", exams: active.filter(\.isScheduled), isPast: false)
                section("Da programmare", exams: active.filter { !$0.isScheduled }, isPast: false)
            } else {
                // Ricerca su tutti gli esami del corso visibile, anche quelli passati.
                let matches = visible.matching(query)
                section("Da sostenere", exams: matches.filter { $0.isActive(today: today) }
                    .sorted { ($0.date, $0.name) < ($1.date, $1.name) }, isPast: false)
                section("Esami passati", exams: matches.filter { !$0.isActive(today: today) }
                    .sorted { $0.date > $1.date }, isPast: true)
            }
        }
        .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Cerca esami, note e task")
        .overlay {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty, visible.matching(query).isEmpty {
                ContentUnavailableView.search(text: query)
            } else if query.isEmpty, active.isEmpty {
                ContentUnavailableView {
                    Label("Nessun esame da sostenere", systemImage: "graduationcap")
                } description: {
                    Text("Aggiungi un esame per iniziare il conto alla rovescia.")
                } actions: {
                    Button("Aggiungi esame") { showingNewExam = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Esami")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewExam = true
                } label: {
                    Label("Nuovo esame", systemImage: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showingNewExam) {
            ExamFormView(exam: nil)
        }
        .examDeletionDialog($examPendingDeletion)
    }

    @ViewBuilder
    private func section(_ title: String, exams: [Exam], isPast: Bool) -> some View {
        if !exams.isEmpty {
            Section {
                ForEach(exams) { exam in
                    row(exam, isPast: isPast)
                        .listRowBackground(isSplit && path.last == exam.id ? Theme.accent.opacity(0.22) : Theme.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Niente ruolo distruttivo: la riga deve sparire solo dopo la conferma,
                            // altrimenti la lista la rimuove due volte e UICollectionView va in crash.
                            Button("Elimina") { examPendingDeletion = exam }
                                .tint(Theme.danger)
                        }
                }
            } header: {
                Text(title).sectionHeaderStyle()
            }
        }
    }

    @ViewBuilder
    private func row(_ exam: Exam, isPast: Bool) -> some View {
        let content = Group {
            if isPast {
                PastExamRow(exam: exam)
            } else {
                UpcomingExamRow(exam: exam, today: today)
            }
        }
        if isSplit {
            // Nelle due colonne la riga seleziona l'esame; il dettaglio si apre a destra.
            content.tag(exam.id)
        } else {
            NavigationLink(value: exam.id) { content }
        }
    }
}
