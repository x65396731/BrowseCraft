import BrowseCraftLog
import Foundation
import UserNotifications

/// `PushNotificationAuthorizing` 的 UserNotifications 适配器。
struct UserNotificationsPushAuthorizationService: PushNotificationAuthorizing {
    func requestAuthorizationIfNeeded() async -> PushNotificationAuthorizationOutcome {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        let settings: UNNotificationSettings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return PushNotificationAuthorizationOutcome(status: .authorized, didPrompt: false)
        case .denied:
            return PushNotificationAuthorizationOutcome(status: .denied, didPrompt: false)
        case .notDetermined:
            break
        @unknown default:
            return PushNotificationAuthorizationOutcome(status: .denied, didPrompt: false)
        }
        do {
            let granted: Bool = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            AppLog.notice(.push, "authorization-requested", ["granted": .bool(granted)])
            return PushNotificationAuthorizationOutcome(status: granted ? .authorized : .denied, didPrompt: true)
        } catch {
            AppLog.error(.push, "authorization-request-failed", ["error": .error(error)])
            return PushNotificationAuthorizationOutcome(status: .denied, didPrompt: true)
        }
    }
}
