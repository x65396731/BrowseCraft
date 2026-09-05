import Foundation
import UserNotifications

/// `PushNotificationAuthorizing` 的 UserNotifications 适配器。
struct UserNotificationsPushAuthorizationService: PushNotificationAuthorizing {
    func requestAuthorizationIfNeeded() async -> PushNotificationAuthorizationStatus {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        let settings: UNNotificationSettings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            break
        @unknown default:
            return .denied
        }
        do {
            let granted: Bool = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            AppLog.notice(
                .push,
                event: "authorization-requested",
                metadata: ["granted": granted ? "true" : "false"]
            )
            return granted ? .authorized : .denied
        } catch {
            AppLog.error(
                .push,
                event: "authorization-request-failed",
                metadata: ["error": AppLog.safeErrorCode(error)]
            )
            return .denied
        }
    }
}
