import ActivityKit
import Foundation
import ExamsCore

/// Avvia, aggiorna e chiude la Live Activity del giorno dell'esame. iOS permette di avviarla solo
/// con l'app in primo piano: la si controlla all'apertura e a ogni modifica degli esami.
/// Non isolato: le `Activity` non sono `Sendable` e così restano nello stesso contesto.
enum ExamActivityController {
    nonisolated static func refresh(exams: [Exam], now: Date = .now) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let plan = ExamActivityPlan.exam(in: exams, now: now)
        let running = Activity<ExamActivityAttributes>.activities

        // Chiude quelle che non servono più (esame passato, orario tolto, un altro esame prima).
        for activity in running where activity.attributes.examID != plan?.exam.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let plan else { return }

        let state = ExamActivityAttributes.ContentState(start: plan.start)
        // Dopo l'inizio il contenuto è "scaduto": la vista mostra "in bocca al lupo".
        let content = ActivityContent(state: state, staleDate: plan.start)
        if let current = running.first(where: { $0.attributes.examID == plan.exam.id }) {
            if current.content.state != state {
                await current.update(content)
            }
            return
        }
        let attributes = ExamActivityAttributes(
            examID: plan.exam.id, examName: plan.exam.name, colorIndex: plan.exam.colorIndex ?? 0
        )
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            NSLog("ExamsTrack: Live Activity non avviata (%@)", String(describing: error))
        }
    }
}
