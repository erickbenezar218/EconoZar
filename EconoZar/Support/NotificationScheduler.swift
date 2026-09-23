import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()
    static let identifier = "econozar.flex.daily"

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func apply(preferences: AppPreferences) async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        guard preferences.reminderEnabled else {
            return await center.notificationSettings().authorizationStatus
        }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized || status == .provisional else { return status }

        let content = UNMutableNotificationContent()
        content.title = "Hora do Aporte Flex!"
        content.body = "Quanto você separa hoje?"
        content.sound = .default

        var components = DateComponents()
        components.hour = preferences.reminderHour
        components.minute = preferences.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        try? await center.add(request)
        return status
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
