import BrowseCraftDomain
import BrowseCraftLog
import FirebaseCrashlytics
import Foundation

// 中文注释：CrashDiagnostics 封装 Crashlytics 写入点，业务层只更新诊断上下文。
// 上报范围、全局键与非致命错误的键见 docs/design/Analytics-Events-Design.md 第 6 节（BCA-OBS-006 ~ 009）。

final class CrashDiagnostics: Sendable {
    static let shared: CrashDiagnostics = CrashDiagnostics()
    static let collectionEnabledDefaultsKey: String = "settings.diagnosticsEnabled"

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
    }

    /// 中文注释：只描述一条非致命错误的键，随那条错误上报、不写成全局键（BCA-OBS-009）。
    private enum FailureKey {
        static let failurePoint: String = "failurePoint"
        static let failureKind: String = "failureKind"
        static let failureStage: String = "failureStage"
        static let failureSourceId: String = "failureSourceId"
        static let failureSourceType: String = "failureSourceType"
        static let bootstrapStage: String = "bootstrapStage"
        static let errorSummary: String = "errorSummary"
    }

    private static let bootstrapFailurePoint: String = "bootstrap"

    private init() {}

    func configure(identityStore: DiagnosticIdentityStore = .shared) {
        let identity: DiagnosticIdentity = identityStore.identity
        let crashlytics: Crashlytics = Crashlytics.crashlytics()

        crashlytics.setCrashlyticsCollectionEnabled(Self.isCollectionEnabled)
        if Self.isCollectionEnabled == false {
            // 中文注释：关闭期间崩溃留下的报告不补发（BCA-OBS-006）。
            crashlytics.deleteUnsentReports()
        }
        crashlytics.setUserID(identity.supportUserId)
        crashlytics.setCustomValue(identity.diagnosticCode, forKey: Key.diagnosticCode)
        crashlytics.setCustomValue(identity.sessionId, forKey: Key.sessionId)
        crashlytics.setCustomValue(Self.appVersion, forKey: Key.appVersion)
        crashlytics.setCustomValue(Self.buildNumber, forKey: Key.buildNumber)
        crashlytics.setCustomValue(Self.deviceModel, forKey: Key.deviceModel)
        crashlytics.setCustomValue(
            ProcessInfo.processInfo.operatingSystemVersionString,
            forKey: Key.systemVersion
        )
    }

    /// 中文注释：同时写一行日志，崩溃报告里的日志因此是一条页面轨迹（第 6.2 节）。
    func setScreen(_ screen: DiagnosticScreen) {
        let crashlytics: Crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(screen.rawValue, forKey: Key.screen)
        crashlytics.log("screen=\(screen.rawValue)")
    }

    /// 中文注释：统一日志的 Crashlytics 出口只经这里写日志行（BCA-OBS-017）：只带类别与事件名，采集关闭时不写。
    func logLine(category: String, event: String) {
        guard Self.isCollectionEnabled else {
            return
        }
        Crashlytics.crashlytics().log("\(category) \(event)")
    }

    func setSource(id: String?, type: DiagnosticSourceType) {
        Crashlytics.crashlytics().setCustomValue(id ?? "", forKey: Key.sourceId)
        Crashlytics.crashlytics().setCustomValue(type.rawValue, forKey: Key.sourceType)
    }

    func setSource(_ source: Source?) {
        guard let source: Source else {
            self.setSource(id: nil, type: .unknown)
            return
        }

        self.setSource(id: source.id, type: source.diagnosticSourceType)
    }

    func setRuleStage(_ stage: DiagnosticRuleStage) {
        Crashlytics.crashlytics().setCustomValue(stage.rawValue, forKey: Key.ruleStage)
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Self.collectionEnabledDefaultsKey)
        let crashlytics: Crashlytics = Crashlytics.crashlytics()
        crashlytics.setCrashlyticsCollectionEnabled(isEnabled)
        if isEnabled == false {
            // 中文注释：关闭前还没发出的报告也不再发（BCA-OBS-006）。
            crashlytics.deleteUnsentReports()
        }
    }

    /// 中文注释：规则执行失败的非致命错误。只由 `RuleFailureDiagnostics.report` 调用（BCA-OBS-007）。
    func recordRuleFailure(
        error: any Error,
        kind: DiagnosticFailureKind,
        stage: DiagnosticRuleStage,
        point: RuleFailurePoint,
        source: Source?
    ) {
        self.record(error: error, userInfo: [
            FailureKey.failurePoint: point.rawValue,
            FailureKey.failureKind: kind.rawValue,
            FailureKey.failureStage: stage.rawValue,
            FailureKey.failureSourceId: source?.id ?? "",
            FailureKey.failureSourceType: (source?.diagnosticSourceType ?? .unknown).rawValue
        ])
    }

    /// 中文注释：启动装配失败的非致命错误，规则执行之外唯一记录的一类（第 6.1 节）。
    func recordBootstrapFailure(error: any Error, stage: BootstrapFailureStage) {
        self.record(error: error, userInfo: [
            FailureKey.failurePoint: Self.bootstrapFailurePoint,
            FailureKey.bootstrapStage: stage.rawValue
        ])
    }

    /// 中文注释：只上传原错误的 domain 与 code 和脱敏摘要。Crashlytics 会把错误的 userInfo 原样写进报告，
    /// 系统网络错误的 userInfo 带完整网址与查询串，所以不能把原错误直接交给它（BCA-OBS-008）。
    private func record(error: any Error, userInfo: [String: String]) {
        guard Self.isCollectionEnabled else {
            return
        }

        let original: NSError = error as NSError
        let sanitized: NSError = NSError(domain: original.domain, code: original.code, userInfo: nil)
        var info: [String: String] = userInfo
        info[FailureKey.errorSummary] = ErrorDiagnostics.summary(for: error)
        Crashlytics.crashlytics().record(error: sanitized, userInfo: info)
    }

    static var isCollectionEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.collectionEnabledDefaultsKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: Self.collectionEnabledDefaultsKey)
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

        return identifier.isEmpty ? "unknown" : identifier
    }
}
