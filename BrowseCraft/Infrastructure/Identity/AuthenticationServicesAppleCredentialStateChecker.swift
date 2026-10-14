import AuthenticationServices
import Foundation

/// 中文注释：TN3194——启动与回到前台查一次凭据状态，并监听系统的撤销通知；查询失败一律归为 unknown，不动会话。
struct AuthenticationServicesAppleCredentialStateChecker: AppleCredentialStateChecking {
    func credentialState(forUserIdentifier userIdentifier: String) async -> AppleCredentialState {
        return await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { state, error in
                guard error == nil else {
                    continuation.resume(returning: .unknown)
                    return
                }
                switch state {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked:
                    continuation.resume(returning: .revoked)
                case .notFound:
                    continuation.resume(returning: .notFound)
                case .transferred:
                    continuation.resume(returning: .transferred)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    func revocationNotifications() -> AsyncStream<Void> {
        return AsyncStream { continuation in
            let task: Task<Void, Never> = Task {
                let notifications = NotificationCenter.default.notifications(
                    named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
                )
                for await _ in notifications {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
