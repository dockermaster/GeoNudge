import Foundation
import UserNotifications
import Observation

@Observable
@MainActor
final class NotificationManager {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                print("[NotificationManager] Authorization granted: \(granted)")
            } catch {
                print("[NotificationManager] Authorization error: \(error)")
            }
            await checkStatus()
        }
    }

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func schedule(for alert: GeoAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.name
        content.body = alert.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("[NotificationManager] Failed to schedule notification: \(error)")
            }
        }
    }
}
