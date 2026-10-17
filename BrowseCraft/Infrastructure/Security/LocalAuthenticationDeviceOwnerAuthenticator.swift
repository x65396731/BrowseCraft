import BrowseCraftLog
import Foundation
import LocalAuthentication

/// 中文注释：`DeviceOwnerAuthenticating` 的 LocalAuthentication 实现（`docs/design/Content-Lock-Design.md` 第 2.2 节）。
/// 验证用设备所有者策略：先用生物识别，不过时由系统转锁屏密码。每次都新建 `LAContext`，
/// 不复用上一次的验证结果——解锁一次只管到下次进入后台。
final class LocalAuthenticationDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    func availableMethod() -> DeviceOwnerAuthenticationMethod {
        let context: LAContext = LAContext()
        var deviceOwnerError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &deviceOwnerError) else {
            return .unavailable
        }

        // 中文注释：`biometryType` 只在调过 canEvaluatePolicy 后才有值，且没录入时也会报硬件类型；
        // 所以再问一次生物识别策略：能用，或只是被系统暂时锁住（之后还会恢复），才按生物识别命名。
        var biometricsError: NSError?
        let canUseBiometrics: Bool = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometricsError
        )
        let isBiometryLockedOut: Bool = biometricsError?.code == LAError.Code.biometryLockout.rawValue
        guard canUseBiometrics || isBiometryLockedOut else {
            return .passcode
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .passcode
        @unknown default:
            return .passcode
        }
    }

    func authenticate(reason: String) async -> DeviceOwnerAuthenticationResult {
        let context: LAContext = LAContext()
        do {
            let succeeded: Bool = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return succeeded ? .succeeded : .failed
        } catch {
            // 中文注释：取消、未通过、被锁住都只算没有通过；界面不弹错，只显示「没有通过验证」。
            AppLog.debug(.security, "content-lock-authentication-failed", ["error": .error(error)])
            if let laError: LAError = error as? LAError,
               laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                return .cancelled
            }
            return .failed
        }
    }
}
