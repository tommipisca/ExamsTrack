import SwiftUI
import ExamsCore

/// Chiavi delle preferenze di visualizzazione, salvate sul dispositivo.
enum DisplayPreferences {
    static let startTab = "startTab"
    /// Corso mostrato in Carriera alla prima apertura dopo l'avvio.
    static let careerFilter = "careerFilter"
    /// Tipo di tesi magistrale, per la stima del voto di laurea: prima era nelle preferenze dell'app,
    /// ora è in quelle condivise (`ThesisType.storageKey`) perché lo legge anche il widget.
    static let legacyThesisType = "thesisType"
    /// Ordine degli esami sostenuti in Carriera.
    static let careerSort = "careerSort"
}

/// Le schede dell'app.
enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case today, exams, career, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Oggi"
        case .exams: "Esami"
        case .career: "Carriera"
        case .settings: "Impostazioni"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .exams: "calendar"
        case .career: "graduationcap.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Task da mostrare aprendo un esame da un link del widget: il dettaglio ci scorre e lo evidenzia.
@MainActor
@Observable
final class TaskFocus {
    var taskID: UUID?
}

/// Schede con barra personalizzata: un'isola arrotondata che fluttua sopra il contenuto.
struct RootView: View {
    @Environment(ExamStore.self) private var store
    @Environment(StudySessionController.self) private var study
    @Environment(\.degreeVisibility) private var visibility
    /// Si parte dalla scheda scelta in Impostazioni.
    @State var selection: AppTab =
        AppTab(rawValue: UserDefaults.standard.string(forKey: DisplayPreferences.startTab) ?? "") ?? .today
    /// Corso visualizzato in Carriera; nil fino alla prima apertura della scheda dopo l'avvio.
    @State private var careerDegree: Degree?
    /// Esami aperti nella scheda Esami.
    @State private var examsPath: [UUID] = []
    @State var isExamSearchPresented = false
    @State var showingNewExam = false
    /// Altezza dell'isola con i suoi margini, misurata: le liste la usano come spazio finale.
    @State private var tabBarHeight: CGFloat = 0
    @State private var taskFocus = TaskFocus()

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(AppTab.today)
                .toolbar(.hidden, for: .tabBar)
            ExamListView(path: $examsPath, isSearchPresented: $isExamSearchPresented)
                .tag(AppTab.exams)
                .toolbar(.hidden, for: .tabBar)
            CareerView(shownDegree: $careerDegree)
                .tag(AppTab.career)
                .toolbar(.hidden, for: .tabBar)
            SettingsView()
                .tag(AppTab.settings)
                .toolbar(.hidden, for: .tabBar)
        }
        .environment(\.floatingTabBarHeight, tabBarHeight)
        .environment(taskFocus)
        // L'isola fluttua sopra il contenuto, che può scorrerle sotto.
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { tabBarHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in tabBarHeight = height }
                    }
                }
        }
        .background(Theme.background.ignoresSafeArea())
        .background { keyboardShortcuts }
        .sheet(isPresented: $showingNewExam) {
            ExamFormView(exam: nil)
        }
        // "Altra durata…" da qualunque menu della sessione di studio.
        .sheet(item: Bindable(study).durationRequest) { target in
            StudyDurationSheet(target: target, initialMinutes: study.lastMinutes)
        }
        // Link da un widget: "Oggi" per il tocco generico, altrimenti la scheda Esami sul dettaglio
        // di quell'esame (e, se indicato, sul task).
        .onOpenURL { url in
            if ExamLink.isToday(url) {
                selection = .today
                return
            }
            if ExamLink.isCareer(url) {
                selection = .career
                return
            }
            if ExamLink.isStudy(url) {
                // Dal controllo del Centro di Controllo: sessione sul prossimo task di oggi.
                selection = .today
                Task { _ = await study.startSuggested(exams: store.exams.visible(visibility)) }
                return
            }
            // Ignora link a esami eliminati o del corso nascosto (widget non ancora aggiornato).
            guard let examID = ExamLink.examID(from: url),
                  let exam = store.exam(id: examID), visibility.includes(exam.degree) else { return }
            selection = .exams
            examsPath = [examID]
            taskFocus.taskID = ExamLink.taskID(from: url)
        }
    }
}

extension RootView {
    /// Scorciatoie da tastiera (iPad con tastiera): ⌘1–4 schede, ⌘N nuovo esame, ⌘F cerca.
    /// Tenendo premuto ⌘ iPadOS le elenca.
    var keyboardShortcuts: some View {
        Group {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selection = tab }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button("Nuovo esame") { showingNewExam = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Cerca esami") {
                selection = .exams
                isExamSearchPresented = true
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Barra delle schede: l'evidenziazione scorre sulla scheda scelta.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = tab == selection
                Button {
                    guard tab != selection else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                        Text(tab.title)
                            .font(.ui(.caption2, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.elevated)
                                .matchedGeometryEffect(id: "selected", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        // Le etichette crescono con il testo di sistema, ma entro un limite che non sfonda l'isola.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        }
        // Su iPad l'isola resta compatta al centro invece di allungarsi su tutto lo schermo.
        .frame(maxWidth: 480)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct FloatingTabBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Spazio occupato dall'isola sopra il bordo inferiore sicuro.
    var floatingTabBarHeight: CGFloat {
        get { self[FloatingTabBarHeightKey.self] }
        set { self[FloatingTabBarHeightKey.self] = newValue }
    }
}

/// Spazio in fondo al contenuto scorrevole pari all'isola: se la pagina è più alta dello
/// spazio libero si può scorrere fino a vedere l'ultimo elemento sopra l'isola;
/// se è più corta non nasce nessuno scorrimento in più.
private struct FloatingTabBarClearance: ViewModifier {
    @Environment(\.floatingTabBarHeight) private var height

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, height, for: .scrollContent)
            .contentMargins(.bottom, height, for: .scrollIndicators)
    }
}

extension View {
    func floatingTabBarClearance() -> some View {
        modifier(FloatingTabBarClearance())
    }
}
