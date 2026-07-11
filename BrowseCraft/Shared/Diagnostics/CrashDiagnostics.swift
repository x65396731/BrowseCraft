import FirebaseCrashlytics
import Foundation
import UIKit

// 中文注释：CrashDiagnostics 封装 Crashlytics 写入点，业务层只更新诊断上下文。

final class CrashDiagnostics {
    static let shared: CrashDiagnostics = CrashDiagnostics()

    private enum Key {
        static let diagnosticCode: String = "diagnosticCode"
        static let sessionId: String = "sessionId"
        static let appVersion: String = "appVersion"
        static let buildNumber: String = "buildNumber"
        static let deviceModel: String = "deviceModel"
        static let systemVersion: String = "systemVersion"
        static let screen: String = "screen"
        static let sourceId: String = "sourceId"
        static let sourceType: String = "sourceType"
        static let ruleStage: String = "ruleStage"
        static let severity: String = "severity"
        static let category: String = "category"
        static let errorCode: String = "errorCode"
    }

    private init() {}

    func configure(identityStore: DiagnosticIdentityStore = .shared) {
        let identity: DiagnosticIdentity = identityStore.identity
        let crashlytics: Crashlytics = Crashlytics.crashlytics()

        crashlytics.setUserID(identity.supportUserId)
        crashlytics.setCustomValue(identity.diagnosticCode, forKey: Key.diagnosticCode)
        crashlytics.setCustomValue(identity.sessionId, forKey: Key.sessionId)
        crashlytics.setCustomValue(Self.appVersion, forKey: Key.appVersion)
        crashlytics.setCustomValue(Self.buildNumber, forKey: Key.buildNumber)
        crashlytics.setCustomValue(Self.deviceModel, forKey: Key.deviceModel)
        crashlytics.setCustomValue(UIDevice.current.systemVersion, forKey: Key.systemVersion)
    }

    func setScreen(_ screen: DiagnosticScreen) {
        Crashlytics.crashlytics().setCustomValue(screen.rawValue, forKey: Key.screen)
    }

    func setSource(id: String?, type: DiagnosticSourceType) {
        Crashlytics.crashlytics().setCustomValue(id ?? "", forKey: Key.sourceId)
        Crashlytics.crashlytics().setCustomValue(type.rawValue, forKey: Key.sourceType)
    }

    func setRuleStage(_ stage: DiagnosticRuleStage) {
        Crashlytics.crashlytics().setCustomValue(stage.rawValue, forKey: Key.ruleStage)
    }

    func record(
        error: Error,
        severity: DiagnosticSeverity = .error,
        category: DiagnosticLogCategory = .unknown,
        errorCode: String? = nil
    ) {
        let crashlytics: Crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(severity.rawValue, forKey: Key.severity)
        crashlytics.setCustomValue(category.rawValue, forKey: Key.category)
        crashlytics.setCustomValue(errorCode ?? "", forKey: Key.errorCode)
        crashlytics.record(error: error)
    }

    private static var appVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var buildNumber: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private static var deviceModel: String {
        var systemInfo: utsname = utsname()
        uname(&systemInfo)

        let mirror: Mirror = Mirror(reflecting: systemInfo.machine)
        let identifier: String = mirror.children.reduce(into: "") { result, element in
            guard let value: Int8 = element.value as? Int8, value != 0 else {
                return
            }
            result.append(String(UnicodeScalar(UInt8(value))))
        }

        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}
