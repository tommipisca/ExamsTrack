import SwiftUI
import ExamsCore

/// Conferma prima di eliminare un esame; condivisa dalle schede che elencano esami.
struct ExamDeletionDialog: ViewModifier {
    @Environment(ExamStore.self) private var store
    @Binding var exam: Exam?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Eliminare l'esame?",
            isPresented: Binding(get: { exam != nil }, set: { if !$0 { exam = nil } }),
            titleVisibility: .visible,
            presenting: exam
        ) { exam in
            Button("Elimina \(exam.name)", role: .destructive) {
                store.deleteExam(id: exam.id)
            }
        } message: { _ in
            Text("Verranno eliminati anche tutti i suoi task.")
        }
    }
}

extension View {
    func examDeletionDialog(_ exam: Binding<Exam?>) -> some View {
        modifier(ExamDeletionDialog(exam: exam))
    }

    /// Stile comune alle schede: lista sul tema scuro e apertura del dettaglio di un esame.
    func tabScreenStyle() -> some View {
        themedListBackground()
            .floatingTabBarClearance()
            .readableContentWidth()
            .modifier(SyncRefresh())
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: UUID.self) { ExamDetailView(examID: $0) }
    }
}

/// "Trascina per aggiornare" sincronizza, se la sincronizzazione è attiva.
private struct SyncRefresh: ViewModifier {
    @Environment(SyncService.self) private var sync
    @Environment(ExamStore.self) private var store

    func body(content: Content) -> some View {
        // Sempre presente, per non ricreare le liste quando si collega o scollega la cartella.
        content.refreshable {
            if sync.isEnabled { await sync.sync(store: store) }
        }
    }
}

extension View {
    /// "Trascina per aggiornare" che sincronizza (se la sincronizzazione è attiva).
    func syncRefreshable() -> some View {
        modifier(SyncRefresh())
    }
}

/// Su iPad (larghezza regolare) il contenuto resta centrato con una larghezza comoda da leggere.
private struct ReadableContentWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .background(Theme.background)
        } else {
            content
        }
    }
}

extension View {
    func readableContentWidth() -> some View {
        modifier(ReadableContentWidth())
    }
}
