import BrowseCraftDomain
import Foundation

// 中文注释：设计文档 A（应用与会话）、B（来源与规则目录）、C（规则生成）三组事件的上报方法。

extension AppAnalytics {
    // MARK: - A. 应用与会话

    func logAppOpen() {
        self.log(.appOpen)
    }

    func logAppForegrounded() {
        self.log(.appForegrounded)
    }

    func logAppBootstrapFailed(stage: BootstrapFailureStage) {
        self.log(.appBootstrapFailed, parameters: [
            Parameter.errorCode: AnalyticsErrorCode(stage).value
        ])
    }

    func logStartupFinished(outcome: StartupOutcome, landingTab: AnalyticsTab) {
        self.log(.startupFinished, parameters: [
            Parameter.result: outcome.rawValue,
            Parameter.entry: landingTab.rawValue
        ])
    }

    /// 中文注释：页面曝光只由 `.analyticsScreen(_:)` 修饰符调用，业务代码不直接调。
    func logScreenView(_ screen: DiagnosticScreen) {
        self.log(.screenView, parameters: [
            Parameter.screenName: screen.rawValue,
            Parameter.screenClass: screen.rawValue
        ])
    }

    func logRuleGenerationPushOpened() {
        self.log(.pushOpened, parameters: [
            Parameter.entry: "rule_generation"
        ])
    }

    func logSupportInfoCopied(_ kind: SupportInfoKind) {
        self.log(.supportInfoCopied, parameters: [
            Parameter.entry: kind.rawValue
        ])
    }

    // MARK: - B. 来源与规则目录

    func logSourceSelected(_ source: Source?, entry: SourceSelectionEntry) {
        guard let source: Source else {
            return
        }
        var parameters: [String: Any] = Self.sourceParameters(source)
        parameters[Parameter.entry] = entry.rawValue
        self.log(.sourceSelected, parameters: parameters)
    }

    /// 中文注释：添加成功时 `source` 是入库后的来源；失败时没有来源，只报类型与原因。
    func logSourceAdded(
        source: Source?,
        kind: AnalyticsContentKind,
        entry: SourceAddEntry,
        result: AnalyticsResult,
        errorCode: AnalyticsErrorCode? = nil
    ) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.entry] = entry.rawValue
        parameters[Parameter.result] = result.rawValue
        if let errorCode: AnalyticsErrorCode {
            parameters[Parameter.errorCode] = errorCode.value
        }
        self.log(.sourceAdded, parameters: parameters)
    }

    func logSourceDeleted(_ source: Source, entry: SourceDeleteEntry) {
        var parameters: [String: Any] = Self.sourceParameters(source)
        parameters[Parameter.entry] = entry.rawValue
        self.log(.sourceDeleted, parameters: parameters)
    }

    func logSourceDeletionUndone(_ source: Source?, result: AnalyticsResult) {
        self.log(.sourceDeletionUndone, parameters: [
            Parameter.contentKind: AnalyticsContentKind(source: source).rawValue,
            Parameter.result: result.rawValue
        ])
    }

    func logSourceActivated(
        _ source: Source?,
        entry: SourceActivationEntry,
        result: SourceActivationResult
    ) {
        self.log(.sourceActivated, parameters: [
            Parameter.contentKind: AnalyticsContentKind(source: source).rawValue,
            Parameter.entry: entry.rawValue,
            Parameter.result: result.rawValue
        ])
    }

    func logPremiumEntryTapped(_ entry: PremiumEntry) {
        self.log(.premiumEntryTapped, parameters: [
            Parameter.entry: entry.rawValue
        ])
    }

    func logCatalogItemDeleted(_ kind: CatalogItemKind, result: AnalyticsResult) {
        self.log(.catalogItemDeleted, parameters: [
            Parameter.entry: kind.rawValue,
            Parameter.result: result.rawValue
        ])
    }

    /// 中文注释：没有可更新的条目时调用方不调（`updatedCount == 0` 且成功）。
    func logCatalogRulesUpdated(trigger: CatalogUpdateTrigger, updatedCount: Int, result: AnalyticsResult) {
        self.log(.catalogRulesUpdated, parameters: [
            Parameter.trigger: trigger.rawValue,
            Parameter.itemCountBucket: Self.countBucket(updatedCount),
            Parameter.result: result.rawValue
        ])
    }

    // MARK: - C. 规则生成

    func logGenerationKindSelected(_ kind: AnalyticsContentKind) {
        self.log(.generationKindSelected, parameters: [
            Parameter.contentKind: kind.rawValue
        ])
    }

    func logGenerationGuideFinished(entry: GenerationGuideEntry, result: GenerationGuideResult) {
        self.log(.generationGuideFinished, parameters: [
            Parameter.entry: entry.rawValue,
            Parameter.result: result.rawValue
        ])
    }

    func logGenerationPreflightStarted(kind: AnalyticsContentKind, inputMethod: PreflightInputMethod) {
        self.log(.generationPreflightStarted, parameters: [
            Parameter.contentKind: kind.rawValue,
            Parameter.inputMethod: inputMethod.rawValue
        ])
    }

    /// 中文注释：预检得出结论时报一次。只报类别、原因码与入口主机名的哈希——不报网址、路径与查询串。
    func logGenerationPreflightResult(
        kind: AnalyticsContentKind,
        preflight: VideoGenerationInputPreflight
    ) {
        var parameters: [String: Any] = [
            Parameter.contentKind: kind.rawValue,
            Parameter.preflightStatus: preflight.status.rawValue
        ]
        if let reason: VideoGenerationInputPreflightReason = preflight.reason {
            parameters[Parameter.errorCode] = AnalyticsErrorCode(reason).value
        }
        if let hostHash: String = Self.hostHash(preflight.evaluatedInputURL.host) {
            parameters[Parameter.siteHostHash] = hostHash
        }
        self.log(.generationPreflightResult, parameters: parameters)
    }

    /// 中文注释：预检没得出结论而是抛错（输入不合法、请求失败等）时报一次。
    func logGenerationPreflightError(
        kind: AnalyticsContentKind,
        siteURLString: String,
        error: Error
    ) {
        var parameters: [String: Any] = [
            Parameter.contentKind: kind.rawValue,
            Parameter.preflightStatus: "error",
            Parameter.errorCode: Self.preflightErrorCode(for: error)
        ]
        if let hostHash: String = Self.hostHash(URL(string: siteURLString)?.host) {
            parameters[Parameter.siteHostHash] = hostHash
        }
        self.log(.generationPreflightResult, parameters: parameters)
    }

    /// 中文注释：用户取消预检时报一次（原来过滤掉不报，设计文档裁定改为 `preflight_status = cancelled`）。
    func logGenerationPreflightCancelled(kind: AnalyticsContentKind, siteURLString: String) {
        var parameters: [String: Any] = [
            Parameter.contentKind: kind.rawValue,
            Parameter.preflightStatus: "cancelled"
        ]
        if let hostHash: String = Self.hostHash(URL(string: siteURLString)?.host) {
            parameters[Parameter.siteHostHash] = hostHash
        }
        self.log(.generationPreflightResult, parameters: parameters)
    }

    static func preflightErrorCode(for error: Error) -> String {
        if error is VideoGenerationInputURLValidationError {
            return "invalid_input"
        }
        if let issue: VideoGenerationInputPreflightExecutionIssue =
            error as? VideoGenerationInputPreflightExecutionIssue {
            switch issue {
            case .unsafeURL:
                return "unsafe_url"
            case .unsupportedContent:
                return "unsupported_content"
            case .requestFailed:
                return "request_failed"
            case .cancelled:
                return "cancelled"
            }
        }
        if error is PreflightPageAcquisitionError {
            return "acquisition_failed"
        }
        return "unknown"
    }

    /// 中文注释：生成提交的结局（设计书 30.8）。只报 kind、档位、是否重新生成与结局，不报余额数值与用户标识。
    func logGenerationSubmitted(
        kind: AnalyticsContentKind,
        hardMode: Bool,
        isRefresh: Bool,
        result: GenerationSubmitResult,
        errorCode: AnalyticsErrorCode? = nil
    ) {
        var parameters: [String: Any] = [
            Parameter.contentKind: kind.rawValue,
            Parameter.hardMode: Self.boolValue(hardMode),
            Parameter.isRefresh: Self.boolValue(isRefresh),
            Parameter.result: result.rawValue
        ]
        if let errorCode: AnalyticsErrorCode {
            parameters[Parameter.errorCode] = errorCode.value
        }
        self.log(.generationSubmitted, parameters: parameters)
    }

    func logPushPermissionResult(_ result: PushPermissionResult) {
        self.log(.pushPermissionResult, parameters: [
            Parameter.result: result.rawValue
        ])
    }
}
