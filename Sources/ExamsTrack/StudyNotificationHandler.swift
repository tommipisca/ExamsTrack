import Foundation
import UserNotifications
import ExamsCore

/// Risponde ai pulsanti della notifica di fine sessione e mostra le notifiche anche con l'app aperta.
/// "Segna fatto" e "Pausa" funzionano senza aprire l'app; "Altri 10 minuti" la apre, perché iOS avvia
/// le Live Activity solo con l'app in primo piano.
final class StudyNotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = StudyNotificationHandler()

    /// Da chiamare all'avvio, prima che arrivi qualsiasi notifica.
    static func install() {
        typealias Keys = StudySession.EndNotification
        let done = UNNotificationAction(identifier: Keys.markDoneAction, title: "Segna fatto",
                                        options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let more = UNNotificationAction(identifier: Keys.moreTimeAction, title: "Altri \(Keys.extraMinutes) minuti",
                                        options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "timer"))
        let pause = UNNotificationAction(identifier: Keys.pauseAction, title: "Pausa",
                                         options: [], icon: UNNotificationActionIcon(systemImageName: "cup.and.saucer"))
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Keys.categoryWithTask, actions: [done, more, pause], intentIdentifiers: []),
            UNNotificationCategory(identifier: Keys.category, actions: [more, pause], intentIdentifiers: []),
        ])
        center.delegate = shared
    }

    /// Con l'app aperta iOS non mostrerebbe le notifiche: le mostra comunque, come banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        typealias Keys = StudySession.EndNotification
        let info = response.notification.request.content.userInfo
        let examID = (info[Keys.examIDKey] as? String).flatMap(UUID.init(uuidString:))
        let taskID = (info[Keys.taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        await handle(action: action, examID: examID, taskID: taskID)
    }

    @MainActor
    private func handle(action: String, examID: UUID?, taskID: UUID?) async {
        typealias Keys = StudySession.EndNotification
        let store = AppServices.store
        let study = AppServices.study
        switch action {
        case Keys.markDoneAction:
            store.reloadFromDisk()
            if let examID, let taskID { store.setTaskDone(id: taskID, inExam: examID) }
            await study.stop()
        case Keys.moreTimeAction:
            store.reloadFromDisk()
            await study.refresh()
            // La sessione appena finita, o quella indicata nella notifica.
            let target = study.current?.target ?? examID.flatMap { id in
                store.exam(id: id).map { exam in
                    StudySessionController.Target(
                        examID: exam.id, examName: exam.name, colorIndex: exam.colorIndex ?? 0, taskID: taskID,
                        taskTitle: taskID.flatMap { tid in exam.tasks.first { $0.id == tid }?.title }
                    )
                }
            }
            if let target { await study.start(target, minutes: Keys.extraMinutes) }
        case Keys.pauseAction:
            await study.stop()
        default:
            // Tocco sulla notifica: si apre l'app, che al ritorno in primo piano chiude la sessione finita.
            break
        }
    }
}
