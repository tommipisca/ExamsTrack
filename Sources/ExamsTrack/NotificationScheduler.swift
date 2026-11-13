import Foundation
import Observation
import UserNotifications
import ExamsCore

/// Preferenze delle notifiche, salvate sul dispositivo.
@MainActor
@Observable
final class NotificationSettingsStore {
    private static let key = "notificationSettings"

    var settings: NotificationSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Sostituisce le notifiche in attesa con quelle pianificate da `NotificationPlanner`.
@MainActor
enum NotificationScheduler {
    /// Pianificazione in corso: le nuove aspettano che finisca, così non si mescolano notifiche vecchie e nuove.
    private static var running: Task<Void, Never>?
    private static let warnedExpirationKey = "warnedAppExpiration"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Chiede il permesso solo la prima volta; poi decide l'utente nelle Impostazioni di iOS.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await authorizationStatus() {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    static func reschedule(exams: [Exam], settings: NotificationSettings) async {
        running?.cancel()
        let previous = running
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await perform(exams: exams, settings: settings)
        }
        running = task
        await task.value
    }

    private static func perform(exams: [Exam], settings: NotificationSettings) async {
        let center = UNUserNotificationCenter.current()
        // Tutte tranne la fine della sessione di studio, che non dipende da esami e preferenze.
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0 != StudySession.notificationID })
        let expiration = ProvisioningProfile.embeddedExpirationDate()
        // L'avviso di scadenza dell'app vale anche con i promemoria spenti.
        guard settings.isAnyEnabled || expiration != nil, await requestAuthorizationIfNeeded() else { return }

        let now = Date.now
        let warned = UserDefaults.standard.object(forKey: warnedExpirationKey) as? Date
        for planned in NotificationPlanner.plan(
            exams: exams, settings: settings, now: now, appExpiration: expiration, warnedExpiration: warned
        ) {
            // Una pianificazione più recente prenderà il posto di questa.
            guard !Task.isCancelled else { return }
            if planned.id == "app-expiration", planned.fireDate.timeIntervalSince(now) <= 120 {
                // Avviso immediato: non va ripetuto a ogni nuova pianificazione.
                UserDefaults.standard.set(expiration, forKey: warnedExpirationKey)
            }
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: planned.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger))
            } catch {
                NSLog("ExamsTrack: notifica %@ non pianificata (%@)", planned.id, String(describing: error))
            }
        }
    }
}
