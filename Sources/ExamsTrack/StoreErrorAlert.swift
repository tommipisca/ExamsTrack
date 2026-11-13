import SwiftUI
import ExamsCore

/// Mostra `store.lastError` come avviso. Va applicato a ogni livello presentato
/// (stack di navigazione e sheet), perché un avviso non compare sopra uno sheet aperto.
struct StoreErrorAlert: ViewModifier {
    @Environment(ExamStore.self) private var store

    func body(content: Content) -> some View {
        content.alert("Errore", isPresented: isPresented, presenting: store.lastError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}

extension View {
    func storeErrorAlert() -> some View {
        modifier(StoreErrorAlert())
    }
}
