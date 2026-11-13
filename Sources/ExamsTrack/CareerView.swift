import SwiftUI
import ExamsCore

/// Scheda "Carriera": media, CFU, voto di laurea ed esami sostenuti di un corso.
/// Su iPad con spazio in larghezza: a sinistra "Riepilogo" ed esami sostenuti, a destra il riepilogo
/// (stessa pagina di iPhone, con più spazio) oppure il dettaglio dell'esame scelto.
struct CareerView: View {
    @Environment(ExamStore.self) private var store
    @Environment(\.today) private var today
    @Environment(\.degreeVisibility) private var visibility
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(DisplayPreferences.careerSort) private var sort: CareerSort = .date
    @AppStorage(DisplayPreferences.careerFilter) private var preference: Degree = .triennale
    @AppStorage(ThesisType.storageKey, store: AppGroup.sharedDefaults) private var thesis: ThesisType = .withReviewer
    @State private var examPendingDeletion: Exam?
    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }
    /// Elemento scelto nella colonna sinistra (solo nelle due colonne).
    @State private var selection: CareerItem? = .overview
    /// Corso mostrato, conservato dalla `RootView` per tutta la vita dell'app:
    /// la preferenza decide solo la prima apertura dopo l'avvio, poi si riapre l'ultimo visto.
    @Binding var shownDegree: Degree?

    private enum CareerItem: Hashable {
        case overview
        case exam(UUID)
    }

    private var degree: Degree {
        // Con un solo corso mostrato, la scelta non c'è.
        visibility.fixedDegree ?? shownDegree ?? preference
    }

    private var isSplit: Bool { sizeClass == .regular }

    /// Esami sostenuti del corso, filtrati dalla ricerca (nome, note, task).
    private var career: [Exam] {
        store.exams.career(degree: degree, today: today).matching(query).sortedForCareer(by: sort)
    }

    private var trend: [TrendPoint] {
        store.exams.visible(visibility).averageTrend(degree: degree)
    }

    var body: some View {
        Group {
            if isSplit {
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationStack {
                        switch selection {
                        case .exam(let examID):
                            ExamDetailView(examID: examID).id(examID)
                        default:
                            overview(chartHeight: 280)
                                .readableContentWidth()
                                .navigationTitle("Riepilogo")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(Theme.background, for: .navigationBar)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    compactPage
                }
            }
        }
        // Cambiando corso (anche a schermo stretto) si torna al riepilogo.
        .onChange(of: degree) { selection = .overview }
        .onChange(of: store.exams) {
            if case .exam(let id) = selection, store.exam(id: id) == nil {
                selection = .overview
            }
        }
        .onAppear {
            // Prima apertura dopo l'avvio: fissa il corso indicato dalla preferenza.
            if shownDegree == nil {
                shownDegree = degree
            }
        }
        .storeErrorAlert()
    }

    // MARK: iPhone e iPad stretto: una sola pagina

    private var compactPage: some View {
        List {
            // Durante la ricerca restano solo i risultati.
            if !isSearching {
                statsSection
                chartSection(height: 180)
            }
            examsSection(selectable: false)
        }
        .searchable(text: $query, prompt: "Cerca negli esami sostenuti")
        .tabScreenStyle()
        .navigationTitle("Carriera")
        .examDeletionDialog($examPendingDeletion)
    }

    // MARK: Due colonne

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                // Più grande delle righe d'esame: è il contenitore di tutta la carriera.
                CareerSummaryCard(
                    degree: degree,
                    estimate: graduationEstimate,
                    average: store.exams.weightedAverage(degree: degree),
                    earnedCFU: store.exams.earnedCFU(degree: degree),
                    trend: trend
                )
                .tag(CareerItem.overview)
                .listRowBackground(rowBackground(.overview))
            } header: {
                degreeSwitcherHeader
            }
            examsSection(selectable: true)
        }
        .searchable(text: $query, prompt: "Cerca negli esami sostenuti")
        // Gruppi arrotondati come nel resto dell'app, non le righe squadrate della barra laterale.
        .listStyle(.insetGrouped)
        .themedListBackground()
        .floatingTabBarClearance()
        .syncRefreshable()
        .navigationTitle("Carriera")
        .examDeletionDialog($examPendingDeletion)
    }

    /// Il riepilogo: la stessa pagina di iPhone senza l'elenco degli esami, che sta nella colonna sinistra.
    private func overview(chartHeight: CGFloat) -> some View {
        List {
            statsSection
            chartSection(height: chartHeight)
        }
        .themedListBackground()
        .floatingTabBarClearance()
        .syncRefreshable()
    }

    // MARK: Sezioni condivise

    private var graduationEstimate: GraduationEstimate? {
        degree == .triennale ? store.exams.graduationEstimate() : store.exams.masterGraduationEstimate(thesis: thesis)
    }

    @ViewBuilder
    private var degreeSwitcherHeader: some View {
        if visibility.fixedDegree == nil {
            HStack {
                Spacer()
                DegreeSwitcher(selection: Binding(get: { degree }, set: { shownDegree = $0 }))
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    private var statsSection: some View {
        Section {
            CareerStatsRow(exams: store.exams, degree: degree)
                .listRowBackground(Theme.surface)
        } header: {
            // Nelle due colonne il selettore del corso sta a sinistra.
            if !isSplit { degreeSwitcherHeader }
        }
    }

    @ViewBuilder
    private func chartSection(height: CGFloat) -> some View {
        // Il grafico ha senso da due esami in su.
        if trend.count >= 2 {
            Section {
                AverageTrendChart(points: trend, height: height)
                    .listRowBackground(Theme.surface)
            } header: {
                Text("Andamento della media").sectionHeaderStyle()
            }
        }
    }

    private func examsSection(selectable: Bool) -> some View {
        Section {
            if career.isEmpty, isSearching {
                Text("Nessun esame sostenuto corrisponde a \u{201C}\(query)\u{201D}.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            } else if career.isEmpty {
                Text("Gli esami della \(degree.label.lowercased()) compaiono qui dopo la loro data, con il voto che inserisci.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            }
            ForEach(career) { exam in
                Group {
                    if selectable {
                        PastExamRow(exam: exam)
                            .tag(CareerItem.exam(exam.id))
                            .listRowBackground(rowBackground(.exam(exam.id)))
                    } else {
                        NavigationLink(value: exam.id) {
                            PastExamRow(exam: exam)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Niente ruolo distruttivo: la riga deve sparire solo dopo la conferma,
                    // altrimenti la lista la rimuove due volte e UICollectionView va in crash.
                    Button("Elimina") { examPendingDeletion = exam }
                        .tint(Theme.danger)
                }
            }
        } header: {
            HStack {
                Text("Esami sostenuti").sectionHeaderStyle()
                Spacer()
                Menu {
                    Picker("Ordina per", selection: $sort) {
                        ForEach(CareerSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(sort.label, systemImage: "arrow.up.arrow.down")
                        .font(.ui(.subheadline, weight: .semibold))
                        .textCase(nil)
                }
                .tint(Theme.accent)
            }
        }
    }

    private func rowBackground(_ item: CareerItem) -> Color {
        selection == item ? Theme.accent.opacity(0.22) : Theme.surface
    }
}

/// Scheda "Riepilogo" della colonna laterale: voto di laurea, media, CFU e un mini grafico della media.
private struct CareerSummaryCard: View {
    let degree: Degree
    let estimate: GraduationEstimate?
    let average: Double?
    let earnedCFU: Int
    let trend: [TrendPoint]
    @ScaledMetric(relativeTo: .largeTitle) private var gradeSize: CGFloat = 38

    private var totalCFU: Int {
        degree == .triennale ? Exam.triennaleCFU : 120
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                Text("Riepilogo")
                    .font(.ui(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(degree.label)
                    .font(.ui(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(estimate.map(CareerStatsRow.gradeText) ?? "—")
                        .font(.system(size: gradeSize, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(Theme.gold)
                    Text("Voto di laurea")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                if trend.count >= 2 {
                    sparkline
                        .frame(width: 84, height: 40)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 20) {
                miniStat(value: CareerStatsRow.averageText(average), title: "Media", color: Theme.accent)
                miniStat(value: "\(earnedCFU)/\(totalCFU)", title: "CFU", color: Theme.textPrimary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func miniStat(value: String, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.ui(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Solo la linea della media, senza assi: un'anticipazione del grafico del riepilogo.
    private var sparkline: some View {
        let values = trend.map(\.average)
        let low = (values.min() ?? 18) - 0.5
        let high = (values.max() ?? 30) + 0.5
        return GeometryReader { proxy in
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = proxy.size.height * (1 - CGFloat((value - low) / max(high - low, 0.001)))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.chartLine, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
