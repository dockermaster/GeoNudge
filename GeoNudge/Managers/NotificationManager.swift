import Foundation
import UserNotifications
import AudioToolbox
import Observation

struct ForegroundAlertInfo {
    let name: String
    let message: String
}

@Observable
@MainActor
final class NotificationManager: NSObject {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var foregroundAlert: ForegroundAlertInfo? = nil

    private let preferences: UserPreferences
    private var vibrationTimer: Timer?

    init(preferences: UserPreferences) {
        self.preferences = preferences
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // Convenience init for SwiftUI previews
    convenience override init() {
        self.init(preferences: UserPreferences())
    }

    func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                print("[NotificationManager] Authorization granted: \(granted)")
            } catch {
                print("[NotificationManager] Authorization error: \(error)")
            }
            registerNotificationCategories()
            await checkStatus()
        }
    }

    private func registerNotificationCategories() {
        let addAction = UNNotificationAction(
            identifier: "ADD_ALERT",
            title: "Add Alert",
            options: .foreground          // .foreground brings the app to the front
        )
        let category = UNNotificationCategory(
            identifier: "PENDING_IMPORT",
            actions: [addAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func schedule(for alert: GeoAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.name
        content.body = alert.message
        if preferences.notificationSound {
            content.sound = .default
        }

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

    func dismiss() {
        stopVibration()
        foregroundAlert = nil
    }

    private func startVibration() {
        guard preferences.notificationVibration else { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func stopVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Called when a notification arrives while the app is in the foreground.
    // Suppress the system banner and show our own persistent banner instead.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Let the share-extension handoff notification pass through as a normal system banner.
        if notification.request.content.categoryIdentifier == "PENDING_IMPORT" {
            completionHandler([.banner])
            return
        }

        // Play sound via system options if enabled (no banner — we show our own)
        let soundOption: UNNotificationPresentationOptions = [.sound]
        Task { @MainActor in
            self.foregroundAlert = ForegroundAlertInfo(
                name: notification.request.content.title,
                message: notification.request.content.body
            )
            self.startVibration()
            completionHandler(self.preferences.notificationSound ? soundOption : [])
        }
    }
}
