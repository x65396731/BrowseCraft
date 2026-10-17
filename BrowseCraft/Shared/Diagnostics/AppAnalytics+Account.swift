import BrowseCraftDomain
import Foundation

// 中文注释：设计文档 G（账号、购买与删除账号）、H（设置、同步与缓存）、I（规则执行诊断）三组事件的上报方法。

extension AppAnalytics {
    // MARK: - G. 账号、购买与删除账号

    func logSignInResult(_ result: AnalyticsResult, errorCode: AnalyticsErrorCode? = nil) {
        var parameters: [String: Any] = [
            Parameter.result: result.rawValue
        ]
        if let errorCode: AnalyticsErrorCode {
            parameters[Parameter.errorCode] = errorCode.value
        }
        self.log(.signInResult, parameters: parameters)
    }

    func logSignOutCompleted(trigger: SignOutTrigger) {
        self.log(.signOutCompleted, parameters: [
            Parameter.trigger: trigger.rawValue
        ])
    }

    func logPaywallProductsLoaded(_ result: PaywallLoadResult) {
        self.log(.paywallProductsLoaded, parameters: [
            Parameter.result: result.rawValue
        ])
    }

    func logPurchaseStarted(productID: String) {
        self.log(.purchaseStarted, parameters: [
            Parameter.productId: productID
        ])
    }

    func logPurchaseResult(productID: String, result: PurchaseResult, errorCode: AnalyticsErrorCode? = nil) {
        var parameters: [String: Any] = [
            Parameter.productId: productID,
            Parameter.result: result.rawValue
        ]
        if let errorCode: AnalyticsErrorCode {
            parameters[Parameter.errorCode] = errorCode.value
        }
        self.log(.purchaseResult, parameters: parameters)
    }

    func logRestoreResult(_ result: RestoreResult) {
        self.log(.restoreResult, parameters: [
            Parameter.result: result.rawValue
        ])
    }

    func logEntitlementChanged(_ change: EntitlementChange, productID: String?) {
        var parameters: [String: Any] = [
            Parameter.result: change.rawValue
        ]
        if let productID: String {
            parameters[Parameter.productId] = productID
        }
        self.log(.entitlementChanged, parameters: parameters)
    }

    func logAccountDeletionResult(_ result: AnalyticsResult, errorCode: AnalyticsErrorCode? = nil) {
        var parameters: [String: Any] = [
            Parameter.result: result.rawValue
        ]
        if let errorCode: AnalyticsErrorCode {
            parameters[Parameter.errorCode] = errorCode.value
        }
        self.log(.accountDeletionResult, parameters: parameters)
    }

    // MARK: - H. 设置、同步与缓存

    func logSettingChanged(_ name: AnalyticsSettingName, value: String) {
        self.log(.settingChanged, parameters: [
            Parameter.settingName: name.rawValue,
            Parameter.settingValue: value
        ])
    }

    func logSettingChanged(_ name: AnalyticsSettingName, isOn: Bool) {
        self.logSettingChanged(name, value: Self.boolValue(isOn))
    }

    func logSettingsLinkOpened(_ link: SettingsLink) {
        self.log(.settingsLinkOpened, parameters: [
            Parameter.entry: link.rawValue
        ])
    }

    func logCacheCleared(freedBytes: Int64) {
        self.log(.cacheCleared, parameters: [
            Parameter.sizeBucket: Self.sizeBucket(bytes: freedBytes)
        ])
    }

    func logCloudSyncFirstEnableResult(choice: CloudSyncFirstEnableChoice?, result: AnalyticsResult) {
        var parameters: [String: Any] = [
            Parameter.result: result.rawValue
        ]
        if let choice: CloudSyncFirstEnableChoice {
            parameters[Parameter.entry] = choice.rawValue
        }
        self.log(.cloudSyncFirstEnableResult, parameters: parameters)
    }

    func logCloudSyncRun(trigger: AnalyticsCloudSyncTrigger, result: AnalyticsResult) {
        self.log(.cloudSyncRun, parameters: [
            Parameter.trigger: trigger.rawValue,
            Parameter.result: result.rawValue
        ])
    }

    func logCloudInitialRestoreResult(trigger: CloudInitialRestoreTrigger, result: AnalyticsResult) {
        self.log(.cloudInitialRestoreResult, parameters: [
            Parameter.trigger: trigger.rawValue,
            Parameter.result: result.rawValue
        ])
    }

    // MARK: - I. 规则执行诊断

    /// 中文注释：只按已判定的类别选事件桶。判定由 Application 的 `RuleExecutionErrorClassifier` 完成——
    /// Shared 在 Application 之下，不得反向引用它的错误类型。
    func logDiagnosticFailure(
        kind: DiagnosticFailureKind,
        stage: DiagnosticRuleStage,
        point: RuleFailurePoint,
        source: Source? = nil
    ) {
        let event: Event
        switch kind {
        case .network:
            event = .networkRequestFailed
        case .parse:
            event = .parseFailed
        }

        var parameters: [String: Any] = Self.sourceParameters(source)
        parameters[Parameter.ruleStage] = AnalyticsErrorCode.snakeCased(stage.rawValue)
        parameters[Parameter.errorCode] = point.rawValue
        self.log(event, parameters: parameters)
    }
}
