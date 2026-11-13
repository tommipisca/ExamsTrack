import ActivityKit
import Foundation
import Observation
import UserNotifications
import ExamsCore

/// Sessione di studio a tempo: Live Activity col timer e notifica alla fine.
/// La sessione vive nella Live Activity (che sopravvive alla chiusura dell'app): qui se ne tiene una copia
/// per mostrarla in "Oggi".
@MainActor
@Observable
final class StudySessionController {
    struct Session: Equatable {
        var examID: UUID
        var examName: String
        var colorIndex: Int
        var taskID: UUID?
        var taskTitle: String?
        var end: Date

        var target: Target {
            Target(examID: examID, examName: examName, colorIndex: colorIndex, taskID: taskID, taskTitle: taskTitle)
        }
    }

    /// Cosa studiare: un task preciso, o il suggerimento del momento.
    struct Target: Identifiable, Equatable {
        var examID: UUID
        var examName: String
        var colorIndex: Int
        var taskID: UUID?
        var taskTitle: String?

        var id: String { "\(examID.uuidString)|\(taskID?.uuidString ?? "")" }
    }

    private(set) var current: Session?
    /// Sessione da avviare dopo aver scelto la durata: `RootView` mostra il selettore.
    var durationRequest: Target?

    /// Ultima durata scelta, proposta di nuovo nei menu e usata da Comandi Rapidi e dal controllo.
    var lastMinutes: Int { StudySession.lastDuration(in: AppGroup.sharedDefaults) }
    /// Senza Live Activity (iPad, o disattivate nelle Impostazioni) la sessione resta solo nell'app.
    private var fallbackEnd: Date?

    var isRunning: Bool { current.map { $0.end > .now } ?? false }

    func start(_ target: Target, minutes: Int) async {
        await start(examID: target.examID, examName: target.examName, colorIndex: target.colorIndex,
                    taskID: target.taskID, taskTitle: target.taskTitle, minutes: minutes)
    }

    /// Il suggerimento del momento: il primo task da fare oggi, o il prossimo esame.
    func suggestedTarget(exams: [Exam]) -> Target? {
        StudySession.suggestion(exams: exams, today: .now).map {
            Target(examID: $0.examID, examName: $0.examName, colorIndex: $0.colorIndex, taskID: $0.taskID, taskTitle: $0.taskTitle)
        }
    }

    func start(examID: UUID, examName: String, colorIndex: Int, taskID: UUID? = nil, taskTitle: String?, minutes: Int) async {
        let minutes = min(max(minutes, StudySession.range.lowerBound), StudySession.range.upperBound)
        AppGroup.sharedDefaults.set(minutes, forKey: StudySession.lastDurationKey)
        await stop()
        let now = Date.now
        let end = now.addingTimeInterval(TimeInterval(minutes * 60))
        current = Session(examID: examID, examName: examName, colorIndex: colorIndex, taskID: taskID, taskTitle: taskTitle, end: end)

        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = StudySessionAttributes(examID: examID, examName: examName, colorIndex: colorIndex,
                                                    taskID: taskID, taskTitle: taskTitle, start: now)
            let content = ActivityContent(state: StudySessionAttributes.ContentState(end: end), staleDate: end)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                NSLog("ExamsTrack: Live Activity della sessione non avviata (%@)", String(describing: error))
            }
        } else {
            fallbackEnd = end
        }
        await scheduleEndNotification(at: end, session: current!, minutes: minutes)
    }

    /// Avvia una sessione sul prossimo task di oggi (o sul prossimo esame).
    /// Senza durata usa l'ultima scelta.
    func startSuggested(exams: [Exam], minutes: Int? = nil) async -> Bool {
        guard let target = suggestedTarget(exams: exams) else { return false }
        await start(target, minutes: minutes ?? lastMinutes)
        return true
    }

    func stop() async {
        current = nil
        fallbackEnd = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [StudySession.notificationID])
        await Self.endActivities()
    }

    /// Riprende la sessione dalla Live Activity all'apertura; chiude quelle finite.
    func refresh() async {
        let now = Date.now
        let activities = Activity<StudySessionAttributes>.activities
        for activity in activities where activity.content.state.end <= now {
            await activity.end(nil, dismissalPolicy: .default)
        }
        if let running = activities.first(where: { $0.content.state.end > now }) {
            let attributes = running.attributes
            current = Session(examID: attributes.examID, examName: attributes.examName, colorIndex: attributes.colorIndex,
                              taskID: attributes.taskID, taskTitle: attributes.taskTitle, end: running.content.state.end)
        } else if let fallbackEnd, fallbackEnd > now {
            // Sessione senza Live Activity: resta quella in memoria.
        } else {
            current = nil
            fallbackEnd = nil
        }
    }

    nonisolated private static func endActivities() async {
        for activity in Activity<StudySessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func scheduleEndNotification(at end: Date, session: Session, minutes: Int) async {
        guard await NotificationScheduler.requestAuthorizationIfNeeded() else { return }
        typealias Keys = StudySession.EndNotification
        let content = UNMutableNotificationContent()
        content.title = "Sessione finita"
        if let task = session.taskTitle {
            content.body = "\(minutes) minuti su «\(task)» (\(session.examName)). Hai finito, o ti serve ancora un po'?"
        } else {
            content.body = "\(minutes) minuti di \(session.examName): ora fai una pausa."
        }
        content.sound = .default
        // Tenendo premuta la notifica: Segna fatto, Altri 10 minuti, Pausa (vedi `StudyNotificationHandler`).
        content.categoryIdentifier = session.taskID == nil ? Keys.category : Keys.categoryWithTask
        var info: [String: String] = [Keys.examIDKey: session.examID.uuidString]
        if let taskID = session.taskID { info[Keys.taskIDKey] = taskID.uuidString }
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: StudySession.notificationID, content: content, trigger: trigger)
        )
    }
}
