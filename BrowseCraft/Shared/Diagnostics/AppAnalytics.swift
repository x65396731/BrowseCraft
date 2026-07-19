import CryptoKit
import FirebaseAnalytics
import Foundation

// 中文注释：AppAnalytics 专门封装用户行为采集，避免与 Crashlytics 诊断职责混在一起。

final class AppAnalytics {
    static let shared: AppAnalytics = AppAnalytics()
    static let collectionEnabledDefaultsKey: String = "settings.analyticsEnabled"

    enum Event: String {
        case appOpen = "bc_app_open"
        case screenView = "screen_view"
        case sourceSelected = "source_selected"
        case searchSubmitted = "search_submitted"
        case readerOpened = "reader_opened"
        case chapterOpened = "chapter_opened"
        case bookmarkAdded = "bookmark_added"
        case bookmarkRemoved = "bookmark_removed"
        case ruleImportStarted = "rule_import_started"
        case ruleImportSucceeded = "rule_import_succeeded"
        case ruleImportFailed = "rule_import_failed"
        case networkRequestFailed = "network_request_failed"
        case parseFailed = "parse_failed"
        case settingChanged = "setting_changed"
    }

    enum Parameter {
        static let screenName: String = "screen_name"
        static let sourceType: String = "source_type"
        static let sourceIdHash: String = "source_id_hash"
        static let ruleStage: String = "rule_stage"
        static let errorCode: String = "error_code"
        static let statusCode: String = "status_code"
        static let resultCountBucket: String = "result_count_bucket"
        static let settingName: String = "setting_name"
        static let settingValue: String = "setting_value"
        static let appVersion: String = "app_version"
        static let buildNumber: String = "build_number"
        static let diagnosticCode: String = "diagnostic_code"
    }

    private enum UserProperty {
        static let diagnosticCode: String = "diagnostic_code"
        static let appVersion: String = "app_version"
        static let buildNumber: String = "build_number"
    }

    private init() {}

    func configure(identityStore: DiagnosticIdentityStore = .shared) {
        let identity: DiagnosticIdentity = identityStore.identity

        Analytics.setAnalyticsCollectionEnabled(Self.isCollectionEnabled)
        Analytics.setUserID(identity.supportUserId)
        Analytics.setUserProperty(identity.diagnosticCode, forName: UserProperty.diagnosticCode)
        Analytics.setUserProperty(Self.appVersion, forName: UserProperty.appVersion)
        Analytics.setUserProperty(Self.buildNumber, forName: UserProperty.buildNumber)
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Self.collectionEnabledDefaultsKey)
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    func logAppOpen() {
        self.log(
            .appOpen,
            parameters: Self.baseParameters()
        )
    }

    func logScreenView(_ screen: DiagnosticScreen) {
        self.log(
            .screenView,
            parameters: Self.baseParameters([
                Parameter.screenName: screen.rawValue
            ])
        )
    }

    func logSourceSelected(_ source: Source?) {
        guard let source: Source else {
            return
        }

        self.log(
            .sourceSelected,
            parameters: Self.baseParameters([
                Parameter.sourceType: source.diagnosticSourceType.rawValue,
                Parameter.sourceIdHash: Self.hashIdentifier(source.id)
            ])
        )
    }

    func logSearchSubmitted(sourceType: DiagnosticSourceType, resultCount: Int) {
        self.log(
            .searchSubmitted,
            parameters: Self.baseParameters([
                Parameter.sourceType: sourceType.rawValue,
                Parameter.resultCountBucket: Self.resultCountBucket(resultCount)
            ])
        )
    }

    func logReaderOpened(source: Source?) {
        self.logSourceAction(.readerOpened, source: source)
    }

    func logChapterOpened(source: Source?) {
        self.logSourceAction(.chapterOpened, source: source)
    }

    func logBookmarkChanged(isFavorite: Bool, source: Source?) {
        self.logSourceAction(isFavorite ? .bookmarkAdded : .bookmarkRemoved, source: source)
    }

    func logRuleImportStarted(sourceType: DiagnosticSourceType) {
        self.log(
            .ruleImportStarted,
            parameters: Self.baseParameters([
                Parameter.sourceType: sourceType.rawValue
            ])
        )
    }

    func logRuleImportSucceeded(source: Source?) {
        self.logSourceAction(.ruleImportSucceeded, source: source)
    }

    func logRuleImportFailed(sourceType: DiagnosticSourceType, errorCode: String) {
        self.log(
            .ruleImportFailed,
            parameters: Self.baseParameters([
                Parameter.sourceType: sourceType.rawValue,
                Parameter.errorCode: errorCode
            ])
        )
    }

    func logDiagnosticFailure(error: Error, stage: DiagnosticRuleStage, errorCode: String) {
        let classifiedError: RuleExecutionError = RuleExecutionErrorClassifier.classified(error)
        let event: Event

        switch classifiedError {
        case .network, .antiBot:
            event = .networkRequestFailed
        case .accessRequired, .selectorEmpty, .ruleConfiguration, .responseContract, .apiResponseContract, .sourceAPI, .protectedResource, .parserDiagnostics, .unknown:
            event = .parseFailed
        }

        self.log(
            event,
            parameters: Self.baseParameters([
                Parameter.ruleStage: stage.rawValue,
                Parameter.errorCode: errorCode
            ])
        )
    }

    func logSettingChanged(name: String, value: String) {
        self.log(
            .settingChanged,
            parameters: Self.baseParameters([
                Parameter.settingName: name,
                Parameter.settingValue: value
            ])
        )
    }

    func log(_ event: Event, parameters: [String: Any] = [:]) {
        guard Self.isCollectionEnabled else {
            return
        }

        Analytics.logEvent(event.rawValue, parameters: Self.safeParameters(parameters))
    }

    static var isCollectionEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.collectionEnabledDefaultsKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: Self.collectionEnabledDefaultsKey)
    }

    private static func safeParameters(_ parameters: [String: Any]) -> [String: Any] {
        let allowedKeys: Set<String> = [
            Parameter.screenName,
            Parameter.sourceType,
            Parameter.sourceIdHash,
            Parameter.ruleStage,
            Parameter.errorCode,
            Parameter.statusCode,
            Parameter.resultCountBucket,
            Parameter.settingName,
            Parameter.settingValue,
            Parameter.appVersion,
            Parameter.buildNumber,
            Parameter.diagnosticCode
        ]

        return parameters.filter { key, _ in
            return allowedKeys.contains(key)
        }
    }

    private static func baseParameters(_ parameters: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = parameters
        result[Parameter.appVersion] = Self.appVersion
        result[Parameter.buildNumber] = Self.buildNumber
        return result
    }

    private func logSourceAction(_ event: Event, source: Source?) {
        guard let source: Source else {
            self.log(event, parameters: Self.baseParameters())
            return
        }

        self.log(
            event,
            parameters: Self.baseParameters([
                Parameter.sourceType: source.diagnosticSourceType.rawValue,
                Parameter.sourceIdHash: Self.hashIdentifier(source.id)
            ])
        )
    }

    private static func resultCountBucket(_ count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case 1...5:
            return "1_5"
        case 6...20:
            return "6_20"
        case 21...50:
            return "21_50"
        default:
            return "51_plus"
        }
    }

    private static func hashIdentifier(_ value: String) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { byte in
            return String(format: "%02x", byte)
        }.joined()
    }

    private static var appVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var buildNumber: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }
}
