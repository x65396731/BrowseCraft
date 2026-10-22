import Observation
import Combine
import Foundation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog
import BrowseCraftRuntime

// 中文注释：SourcesViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：Sources 标签页的视图模型，管理源列表、选中源、刷新状态和错误信息。
/// 中文注释：`@Observable`——SwiftUI 按视图实际读到的属性追踪变化并刷新。
@MainActor
@Observable
final class SourcesViewModel {
    private struct RefreshedListPage {
        let items: [ContentItem]
        let nextPage: Int?
    }

    private enum FailedRefreshAction {
        case select(sourceID: String, entry: SourceSelectionEntry)
        case refresh(sourceID: String)
    }

    /// 中文注释：一次目录规则跟随的结局，供 `catalog_rules_updated` 上报；没有可更新的条目时为 nil、不报。
    private struct CatalogRuleUpdateSummary {
        let updatedCount: Int
        let result: AnalyticsResult
    }

    private(set) var sources: [Source] = []
    private(set) var selectedSourceID: String?
    var errorMessage: String?
    private(set) var isRefreshing: Bool = false
    private(set) var refreshingSourceID: String?
    private(set) var latestSourceAddID: String?
    private(set) var latestCatalogSourceAddID: String?
    private(set) var catalogSources: [CatalogSource] = [] {
        didSet {
            self.rebuildCatalogSourceGrouping()
        }
    }
    /// 目录条目 id → 规则里给用户看的信息；解析不了的条目不在表里，卡片只显示名称与地址。
    /// 与 `catalogSources` 一起由 `setCatalogSources` 写入：目录到手时解析一次，不在滚动时反复解析规则 JSON。
    private(set) var catalogRuleFacts: [String: CatalogRuleFacts] = [:]
    private(set) var isLoadingCatalogSources: Bool = false
    /// 当前用户的生成终态；nil 表示尚未读取。
    private(set) var videoGenerationOutcomesLoad: VideoGenerationOutcomesLoad? {
        didSet {
            self.rebuildCatalogSourceGrouping()
        }
    }
    /// 目录两分组：网站默认数据 + 按当前用户生成结果挑出的个人数据。
    ///
    /// 中文注释：存储属性，只在 `catalogSources` / `videoGenerationOutcomesLoad` 变化时重建（与 `catalogRuleFacts` 同做法）；
    /// 此前是计算属性，目录页每行每次 body 都重算，内含逐条规则的 JSONSerialization（2026-10-20 审计 C-6）。
    private(set) var catalogSourceGrouping: CatalogSourceGrouping = CatalogSourceGrouping.make(catalogSources: [], outcomes: [])
    /// 目录里某条规则添加失败的具体原因（按 catalogSourceId），成功或刷新后清除。
    private(set) var catalogSourceAddFailureMessages: [String: String] = [:]
    private(set) var requestedSlotActivationSource: Source?
    private(set) var videoGenerationInputProgress: VideoGenerationInputPreflightProgress?
    private(set) var sourceSlotLimit: Int =
        SourceSlotPolicy.includedSiteSlotCount
    /// 刚删除、还能撤销的来源与删除前的库状态；底部提示随它出现和消失（`docs/design/Source-Deletion-Cascade-Design.md` 第五节）。
    private(set) var undoableDeletion: SourceDeletionReceipt?
    /// 本页每删除或撤销成功一次就加一；宿主据此重新载入历史与收藏，让被删来源的行显示为「来源已删除」或恢复正常。
    private(set) var sourceContentRevision: Int = 0
    @ObservationIgnored private var undoDismissTask: Task<Void, Never>?
    /// 中文注释：撤销窗口里那次删除是从哪里发起的（左滑 / 长按菜单）；窗口结束、真正提交删除时随 `source_deleted` 上报。
    @ObservationIgnored private var undoableDeletionEntry: SourceDeleteEntry?
    /// 中文注释：启用来源窗口是从哪里拉起的；窗口出结局（启用、换下、失败、取消）时随 `source_activated` 上报一次后清空。
    @ObservationIgnored private var requestedSlotActivationEntry: SourceActivationEntry?
    /// 启动与回到前台时的目录跟随（`syncAddedSourcesWithCatalog`）：进行中标记与上次成功读取的时刻。
    @ObservationIgnored private var isSyncingAddedSourcesWithCatalog: Bool = false
    @ObservationIgnored private var lastCatalogSyncDate: Date?

    /// 撤销提示停留的时长，与收藏页、历史页相同。
    static let undoDuration: Duration = .seconds(4)

    private let persistenceCoordinator: SourcesPersistenceCoordinator
    private let discoveryService: SourceDiscoveryService
    private let createVideoGenerationTaskUseCase: CreateVideoGenerationTaskUseCase?
    private let pushNotificationAuthorizer: (any PushNotificationAuthorizing)?
    private let loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase?
    /// 设计书第 30 节：提交页显示消耗与余额；提交响应带回的余额写回这里。
    let coinWalletStore: CoinWalletStore?
    private let hideVideoGenerationOutcomeUseCase: HideVideoGenerationOutcomeUseCase?
    /// 中文注释：网址输入页成功率一行（Campaign-And-Rate-Notices-Design.md 第三节）；nil 即未接线（测试替身），这一行不显示。
    private let generationRatesClient: (any GenerationRatesFetching)?
    private let catalogService: SourceCatalogService
    private let ruleDebugJSONFormatter: SourceRuleDebugJSONFormatter
    private let contentItemMapper: SourceListContentItemMapper
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let validateSourceTabsUseCase: ValidateSourceTabsUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var failedRefreshAction: FailedRefreshAction?
    private var videoGenerationAssessmentID: UUID?

    var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }

    var occupiedSourceSlotCount: Int {
        return self.sources.filter { source in
            return source.isBuiltIn == false
                && source.accessState == .active
        }.count
    }

    var lockedSourceCount: Int {
        return self.sources.filter { source in
            return source.accessState == .lockedBySlotLimit
        }.count
    }

    var activeCustomSources: [Source] {
        return self.sources.filter { source in
            return source.isBuiltIn == false
                && source.accessState == .active
        }
    }

    var canActivateRequestedSourceWithoutReplacement: Bool {
        return self.occupiedSourceSlotCount < self.sourceSlotLimit
    }

    private func rebuildCatalogSourceGrouping() {
        let outcomes: [VideoGenerationOutcome]
        if case .loaded(let loaded) = self.videoGenerationOutcomesLoad {
            outcomes = loaded
        } else {
            outcomes = []
        }
        self.catalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: self.catalogSources,
            outcomes: outcomes
        )
    }

    /// 个人规则的剩余可见时间（服务端 `expiresAt`）；没有截止信息时返回 nil，视图不显示。
    func personalRuleRemainingComponents(for catalogSource: CatalogSource) -> (days: Int, hours: Int)? {
        guard let expiresAt: Date = self.catalogSourceGrouping.personalOutcomes[catalogSource.id]?.expiresAt else {
            return nil
        }
        return PersonalRuleRetentionPolicy.remainingComponents(expiresAt: expiresAt, now: self.now())
    }

    /// 个人规则剩余可见时间占 7 天的比例（进度条用）；没有截止信息时返回 nil。
    func personalRuleRemainingFraction(for catalogSource: CatalogSource) -> Double? {
        guard let expiresAt: Date = self.catalogSourceGrouping.personalOutcomes[catalogSource.id]?.expiresAt else {
            return nil
        }
        return PersonalRuleRetentionPolicy.remainingFraction(expiresAt: expiresAt, now: self.now())
    }

    /// 「我的生成」时间线：成功规则与失败记录合并，按终结时间倒序、按自然日分组。
    var personalCatalogTimeline: CatalogPersonalTimeline {
        return CatalogPersonalTimeline.make(
            grouping: self.catalogSourceGrouping,
            now: self.now(),
            calendar: .current
        )
    }

    /// 「我的生成」标签上的数量角标：个人成功规则与失败记录之和。
    var personalCatalogItemCount: Int {
        let grouping: CatalogSourceGrouping = self.catalogSourceGrouping
        return grouping.personalSources.count + grouping.failedOutcomes.count
    }

    /// 用户删除个人规则：服务端软删除 + 删掉已添加的本地副本，然后重新读取终态。
    @MainActor
    func deletePersonalRule(catalogSourceID: String) async {
        guard let outcome: VideoGenerationOutcome = self.catalogSourceGrouping.personalOutcomes[catalogSourceID] else {
            return
        }
        let didHide: Bool = await self.hideOutcome(jobID: outcome.jobID, localSourceID: catalogSourceID)
        AppAnalytics.shared.logCatalogItemDeleted(.personalRule, result: didHide ? .success : .failed)
    }

    /// 用户删除失败记录：服务端软删除。
    ///
    /// 中文注释：时间线对同一入口只显示最近一次失败（`CatalogSourceGrouping` 按 `entryURL` 去重），用户删的是
    /// 「这个入口的失败」而不是「这一次」——只删最新那条，被盖住的更早一条会立刻浮上来，看起来像删不掉
    /// （2026-10-09 用户反馈）。所以同一入口的全部失败一起软删除，再重拉一次。
    @MainActor
    func deleteFailedGenerationOutcome(jobID: UUID) async {
        let didHide: Bool = await self.hideOutcomes(
            jobIDs: self.failedOutcomeJobIDs(sharingEntryURLWith: jobID),
            localSourceID: nil
        )
        AppAnalytics.shared.logCatalogItemDeleted(.failedOutcome, result: didHide ? .success : .failed)
    }

    /// 与给定失败记录同一入口的全部失败（含它自己）；找不到入口 URL 时只删它自己。
    private func failedOutcomeJobIDs(sharingEntryURLWith jobID: UUID) -> [UUID] {
        guard case .loaded(let outcomes) = self.videoGenerationOutcomesLoad,
              let target: VideoGenerationOutcome = outcomes.first(where: { $0.jobID == jobID }),
              let entryURL: String = target.entryURL else {
            return [jobID]
        }
        let sameEntry: [UUID] = outcomes
            .filter { $0.didSucceed == false && $0.entryURL == entryURL }
            .map(\.jobID)
        return sameEntry.isEmpty ? [jobID] : sameEntry
    }

    @MainActor
    private func hideOutcome(jobID: UUID, localSourceID: String?) async -> Bool {
        return await self.hideOutcomes(jobIDs: [jobID], localSourceID: localSourceID)
    }

    /// 逐条软删除；第一条失败就停下来报错，已删掉的不回滚（服务端幂等，下次重试照样可删）。
    /// 返回服务端软删除是否全部成功；本地副本删除失败只报错，不算删除失败。
    @MainActor
    private func hideOutcomes(jobIDs: [UUID], localSourceID: String?) async -> Bool {
        guard let useCase: HideVideoGenerationOutcomeUseCase = self.hideVideoGenerationOutcomeUseCase else {
            return false
        }
        for jobID: UUID in jobIDs {
            let result: HideVideoGenerationOutcomeUseCase.Result = await useCase.execute(jobID: jobID)
            switch result {
            case .hidden:
                AppLog.notice(.push, "outcome-hidden")
            case .authRequired:
                self.errorMessage = NSLocalizedString("catalog_personal_sign_in_hint", comment: "")
                return false
            case .failed(let code):
                AppLog.error(.push, "outcome-hide-failed", ["code": .code(code)])
                self.errorMessage = NSLocalizedString("rule_error_unknown", comment: "")
                return false
            }
        }
        if let localSourceID: String = localSourceID,
           self.sources.contains(where: { source in source.id == localSourceID }) {
            do {
                // 中文注释：服务端已软删除，本地副本的删除不给撤销。
                try await self.deleteSourcesWithoutUndo(ids: [localSourceID])
            } catch {
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "personal-rule-delete-error")
                self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            }
        }
        await self.loadVideoGenerationOutcomes()
        return true
    }

    /// 「发现」的站点示例（`section=example`，最多 6 条）。
    var exampleCatalogSources: [CatalogSource] {
        return self.catalogSourceGrouping.exampleSources
    }

    /// 「发现」的内部测试站点（`section=internal`）；Release 构建恒为空。
    var internalCatalogSources: [CatalogSource] {
        return self.catalogSourceGrouping.internalSources
    }

    var personalCatalogSources: [CatalogSource] {
        return self.catalogSourceGrouping.personalSources
    }

    var failedGenerationOutcomes: [VideoGenerationOutcome] {
        return self.catalogSourceGrouping.failedOutcomes
    }

    func personalRuleEntryURL(for catalogSource: CatalogSource) -> String? {
        return self.catalogSourceGrouping.personalEntryURLs[catalogSource.id]
    }

    /// 目录行副标题用的入口：个人规则取任务入口；公共目录同一主机有多条时取各自规则的入口；都没有返回 nil（视图显示 `baseURL`）。
    func catalogEntryURL(for catalogSource: CatalogSource) -> String? {
        let grouping: CatalogSourceGrouping = self.catalogSourceGrouping
        return grouping.personalEntryURLs[catalogSource.id] ?? grouping.defaultEntryURLs[catalogSource.id]
    }

    /// 个人分组需要登录才有内容；未接入 outcomes 用例（测试替身）时视为不需要。
    var isPersonalCatalogSignInRequired: Bool {
        return self.videoGenerationOutcomesLoad == .authRequired
    }

    init(
        persistenceCoordinator: SourcesPersistenceCoordinator,
        discoveryService: SourceDiscoveryService,
        createVideoGenerationTaskUseCase: CreateVideoGenerationTaskUseCase? = nil,
        pushNotificationAuthorizer: (any PushNotificationAuthorizing)? = nil,
        loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase? = nil,
        hideVideoGenerationOutcomeUseCase: HideVideoGenerationOutcomeUseCase? = nil,
        generationRatesClient: (any GenerationRatesFetching)? = nil,
        coinWalletStore: CoinWalletStore? = nil,
        catalogService: SourceCatalogService,
        ruleDebugJSONFormatter: SourceRuleDebugJSONFormatter,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        validateSourceTabsUseCase: ValidateSourceTabsUseCase,
        sourceSelectionStore: SourceSelectionStore,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.discoveryService = discoveryService
        self.createVideoGenerationTaskUseCase = createVideoGenerationTaskUseCase
        self.pushNotificationAuthorizer = pushNotificationAuthorizer
        self.loadVideoGenerationOutcomesUseCase = loadVideoGenerationOutcomesUseCase
        self.hideVideoGenerationOutcomeUseCase = hideVideoGenerationOutcomeUseCase
        self.generationRatesClient = generationRatesClient
        self.coinWalletStore = coinWalletStore
        self.catalogService = catalogService
        self.ruleDebugJSONFormatter = ruleDebugJSONFormatter
        self.contentItemMapper = SourceListContentItemMapper()
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceTabsUseCase = validateSourceTabsUseCase
        self.sourceSelectionStore = sourceSelectionStore
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
        self.now = now
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：普通页面加载沿用现有错误展示；启动层通过 loadForStartup 区分无源和读取失败。
    func load() async {
        do {
            _ = try await self.loadForStartup()
        } catch {
            // 中文注释：错误已经由 loadForStartup 记录并发布给 Sources 页面。
        }
    }

    @MainActor
    func loadForStartup() async throws -> Bool {
        do {
            let snapshot: SourcesPersistenceSnapshot = try await self.persistenceCoordinator.load(
                userID: self.currentUserID
            )
            let loadedSources: [Source] = snapshot.sources
            self.sources = loadedSources
            self.sourceSlotLimit = snapshot.sourceSlotLimit
            if let selectedSourceID: String = self.selectedSourceID,
               loadedSources.contains(where: { source in
                   return source.id == selectedSourceID
                       && source.accessState == .active
               }) == false {
                self.selectSource(
                    id: loadedSources.first(where: { source in
                        return source.accessState == .active
                    })?.id
                )
            }
            self.errorMessage = nil
            return loadedSources.isEmpty == false
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            throw error
        }
    }

    @MainActor
    func assessVideoGenerationInput(
        siteURLString: String,
        sourceKind: RuleGenerationSourceKind? = nil,
        inputMethod: PreflightInputMethod
    ) async throws -> VideoGenerationInputPreflight {
        let analyticsKind: AnalyticsContentKind = sourceKind.map { kind in
            return AnalyticsContentKind(ruleGenerationKind: kind)
        } ?? .unknown
        AppAnalytics.shared.logGenerationPreflightStarted(kind: analyticsKind, inputMethod: inputMethod)
        let assessmentID: UUID = UUID()
        self.videoGenerationAssessmentID = assessmentID
        self.errorMessage = nil
        self.videoGenerationInputProgress = .validatingInput
        do {
            let result: VideoGenerationInputPreflight = try await self.discoveryService
                .assessVideoGenerationInput(
                    siteURLString: siteURLString,
                    progress: { [weak self] progress in
                        guard self?.videoGenerationAssessmentID == assessmentID else {
                            return
                        }
                        self?.videoGenerationInputProgress = progress
                    }
                )
            if self.videoGenerationAssessmentID == assessmentID {
                self.videoGenerationInputProgress = nil
                self.videoGenerationAssessmentID = nil
            }
            AppAnalytics.shared.logGenerationPreflightResult(kind: analyticsKind, preflight: result)
            return result
        } catch is CancellationError {
            if self.videoGenerationAssessmentID == assessmentID {
                self.videoGenerationInputProgress = nil
                self.videoGenerationAssessmentID = nil
            }
            AppAnalytics.shared.logGenerationPreflightCancelled(kind: analyticsKind, siteURLString: siteURLString)
            throw CancellationError()
        } catch {
            if self.videoGenerationAssessmentID == assessmentID {
                self.videoGenerationInputProgress = nil
                self.videoGenerationAssessmentID = nil
                self.errorMessage = error.localizedDescription
            }
            if (error as? VideoGenerationInputPreflightExecutionIssue) == .cancelled {
                AppAnalytics.shared.logGenerationPreflightCancelled(kind: analyticsKind, siteURLString: siteURLString)
            } else {
                AppAnalytics.shared.logGenerationPreflightError(
                    kind: analyticsKind, siteURLString: siteURLString, error: error
                )
            }
            throw error
        }
    }

    /// 中文注释：未接线任务客户端时 UI 不得出现可点的「生成」（`BC-PREFLIGHT-048`）。
    /// 网址输入页出现时取一次成功率（Campaign-And-Rate-Notices-Design.md 第三节）：不要登录、不挡任何操作。
    /// 失败、超时一律返回 nil——界面不显示这一行，不弹错、不重试；请求的完成与失败已由 PortalAPIClient 的公共钩子记网络日志，
    /// 这里再记一条吞错（`BCA-OBS-015`）。
    func loadGenerationRates(kind: RuleGenerationSourceKind) async -> GenerationRates? {
        guard let client: any GenerationRatesFetching = self.generationRatesClient else {
            return nil
        }
        do {
            return try await client.fetchRates(kind: kind)
        } catch is CancellationError {
            // 中文注释：sheet 关掉时任务被取消，是预期内的，不记。
            return nil
        } catch {
            AppLog.error(.generation, "generation-rates-unavailable", [
                "kind": .enumValue(kind),
                "error": .error(error)
            ])
            return nil
        }
    }

    /// 检查可提交后问一次这个网址能不能直接取用现成规则（Generation-Input-Page-Redesign-Design.md 第三节）。
    /// 未接线、未登录、不可取用与失败一律返回 nil，输入页照常显示取页方式与「滑动生成」。
    func loadReusePreview(
        preflight: VideoGenerationInputPreflight,
        sourceKind: RuleGenerationSourceKind
    ) async -> GenerationReusePreview? {
        guard let useCase: CreateVideoGenerationTaskUseCase = self.createVideoGenerationTaskUseCase else {
            return nil
        }
        return await useCase.reusePreview(preflight: preflight, sourceKind: sourceKind)
    }

    /// 取用之后点「添加为来源」：与规则目录的「添加」同一条路径（`addCatalogSource`），由用户手动触发，
    /// 不是 2026-10-03 裁定不要的自动添加。错误不弹窗，由输入页在按钮下说明。
    @MainActor
    func addReusedRule(_ rule: VideoGenerationReusedRule) async -> Bool {
        return await self.addCatalogSource(
            rule.catalogSource,
            entry: .generationReuse,
            shouldPresentError: false
        )
    }

    var canSubmitVideoGenerationTasks: Bool {
        return self.createVideoGenerationTaskUseCase != nil
    }

    @MainActor
    func submitVideoGenerationTask(
        preflight: VideoGenerationInputPreflight,
        sourceKind: RuleGenerationSourceKind,
        refresh: Bool = false,
        acquisitionTier: GenerationAcquisitionTier = .normal,
        idempotencyKey: String? = nil
    ) async throws -> VideoGenerationTaskSubmissionOutcome {
        let analyticsKind: AnalyticsContentKind = AnalyticsContentKind(ruleGenerationKind: sourceKind)
        let hardMode: Bool = acquisitionTier == .hard
        guard let useCase: CreateVideoGenerationTaskUseCase =
            self.createVideoGenerationTaskUseCase else {
            AppAnalytics.shared.logGenerationSubmitted(
                kind: analyticsKind, hardMode: hardMode, isRefresh: refresh, result: .localRejected
            )
            throw VideoGenerationTaskSubmissionRejection.preflightNotAccepted(preflight.status)
        }
        let outcome: VideoGenerationTaskSubmissionOutcome
        do {
            outcome = try await useCase.execute(
                preflight: preflight,
                sourceKind: sourceKind,
                refresh: refresh,
                acquisitionTier: acquisitionTier,
                idempotencyKey: idempotencyKey
            )
        } catch {
            // 中文注释：本地拒绝（预检未通过、版本漂移）或异常，没到服务端；输入页把它显示成 `local-rejection`。
            // 用户改网址或关页导致的取消不是提交结局，不报。
            if (error is CancellationError) == false {
                AppAnalytics.shared.logGenerationSubmitted(
                    kind: analyticsKind, hardMode: hardMode, isRefresh: refresh, result: .localRejected
                )
            }
            throw error
        }
        let submitResult: (result: GenerationSubmitResult, errorCode: AnalyticsErrorCode?) =
            Self.generationSubmitResult(for: outcome)
        AppAnalytics.shared.logGenerationSubmitted(
            kind: analyticsKind,
            hardMode: hardMode,
            isRefresh: refresh,
            result: submitResult.result,
            errorCode: submitResult.errorCode
        )
        // 设计书 30.6：提交响应（`202` 与 `200 cached`）带扣后的余额；余额不足时服务端给的是当前余额，重新拉一次对齐。
        switch outcome {
        case .submitted(let receipt):
            if let balance: Int = receipt.coinBalance, let revision: Int = receipt.coinRevision {
                self.coinWalletStore?.apply(balance: balance, revision: revision)
            }
        case .reused(let rule):
            // PortalCore 发布前检查清单第 9 项：取用现成的公共规则也扣 coin，响应带扣后的余额。
            if let balance: Int = rule.coinBalance, let revision: Int = rule.coinRevision {
                self.coinWalletStore?.apply(balance: balance, revision: revision)
            }
        case .insufficientCoins:
            if let store: CoinWalletStore = self.coinWalletStore {
                Task { await store.refresh() }
            }
        default:
            break
        }
        // 中文注释：任务排队成功是用户最能理解「为什么要通知权限」的时刻——终态靠推送告知。
        // 只在这一刻请求，且不阻塞提交结果的展示；已决定过的系统不会再弹。
        if case .submitted = outcome,
           let authorizer: any PushNotificationAuthorizing = self.pushNotificationAuthorizer {
            Task {
                let authorizationOutcome: PushNotificationAuthorizationOutcome = await authorizer.requestAuthorizationIfNeeded()
                let result: PushPermissionResult
                if authorizationOutcome.didPrompt == false {
                    result = .alreadyDecided
                } else {
                    result = authorizationOutcome.status == .authorized ? .granted : .denied
                }
                AppAnalytics.shared.logPushPermissionResult(result)
            }
        }
        return outcome
    }

    /// 中文注释：提交结局 → `generation_submitted` 的 result 与 error_code。服务端失败码是开放字符串，
    /// 只按 `GenerationSubmitFailureCode` 归成有限几类再上报，不报原始码。
    private static func generationSubmitResult(
        for outcome: VideoGenerationTaskSubmissionOutcome
    ) -> (result: GenerationSubmitResult, errorCode: AnalyticsErrorCode?) {
        switch outcome {
        case .submitted:
            return (.submitted, nil)
        case .reused:
            return (.reused, nil)
        case .insufficientCoins:
            return (.insufficientCoins, nil)
        case .authRequired:
            return (.authRequired, nil)
        case .activeJobLimit:
            return (.activeJobLimit, nil)
        case .previousJobActive:
            return (.previousJobActive, nil)
        case .rateLimited:
            return (.rateLimited, nil)
        case .failed(let code):
            return (.failed, AnalyticsErrorCode(GenerationSubmitFailureCode(code: code)))
        }
    }

    @MainActor
    func saveTemporaryHistory(_ history: TemporaryResourceHistory) {
        var ownedHistory: TemporaryResourceHistory = history
        ownedHistory.userID = self.currentUserID
        let transfer: TemporaryResourceHistoryTransfer = TemporaryResourceHistoryTransfer(
            value: ownedHistory
        )
        Task { [persistenceCoordinator] in
            do {
                try await persistenceCoordinator.saveTemporaryHistory(transfer)
            } catch {
                RuleExecutionErrorClassifier.log(
                    error: error,
                    stage: .list,
                    event: "temporary-history-save-error"
                )
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// `BC-PREFLIGHT-066`：「规则目录」每次呈现与下拉刷新都走这里——新生成的规则不依赖推送刷新。
    /// 目录与个人终态并行读取；个人终态失败不影响默认分组的展示。
    @MainActor
    func refreshCatalogSources() async {
        CrashDiagnostics.shared.setRuleStage(.list)
        if self.isLoadingCatalogSources {
            return
        }

        self.isLoadingCatalogSources = true
        defer {
            self.isLoadingCatalogSources = false
        }
        self.catalogSourceAddFailureMessages.removeAll()

        async let outcomes: Void = self.loadVideoGenerationOutcomes()
        do {
            self.setCatalogSources(try await self.catalogService.loadSources())
            self.lastCatalogSyncDate = self.now()
            AppLog.notice(.rule, "catalog-sources-loaded", ["count": .int(self.catalogSources.count), "trigger": .code("catalog-open")])
            await self.applyCatalogRuleUpdates(self.catalogSources, trigger: .catalogOpen)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
        await outcomes
    }

    /// 启动与回到前台时调用：读一次公共目录，让已添加的来源跟上服务器上的规则。
    ///
    /// 中文注释：规则目录页不开也要跟——只在目录页里跟随的话，平时只用书架的用户会一直跑旧规则。
    /// 与目录页的读取不同，这里静默进行：不置 `isLoadingCatalogSources`、失败只记日志不弹错；
    /// 距上次成功读取不足 `catalogSyncMinimumInterval` 时跳过，免得来回切 App 反复拉整份目录。
    @MainActor
    func syncAddedSourcesWithCatalog() async {
        guard self.isSyncingAddedSourcesWithCatalog == false,
              self.sources.isEmpty == false else {
            return
        }
        if let lastCatalogSyncDate: Date = self.lastCatalogSyncDate,
           self.now().timeIntervalSince(lastCatalogSyncDate) < Self.catalogSyncMinimumInterval {
            return
        }
        self.isSyncingAddedSourcesWithCatalog = true
        defer {
            self.isSyncingAddedSourcesWithCatalog = false
        }
        do {
            let catalogSources: [CatalogSource] = try await self.catalogService.loadSources()
            self.setCatalogSources(catalogSources)
            self.lastCatalogSyncDate = self.now()
            AppLog.notice(.rule, "catalog-sources-loaded", ["count": .int(catalogSources.count), "trigger": .code("foreground")])
            // 中文注释：启动时的那次跟随也走这里，`CatalogUpdateTrigger` 没有单独的启动取值，一并记作 foreground。
            await self.applyCatalogRuleUpdates(catalogSources, trigger: .foreground)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-sync-error")
        }
    }

    private func setCatalogSources(_ catalogSources: [CatalogSource]) {
        self.catalogSources = catalogSources
        self.catalogRuleFacts = CatalogRuleFacts.makeIndex(catalogSources)
    }

    /// 两次后台目录跟随之间的最短间隔。目录页的打开与下拉刷新不受它限制。
    static let catalogSyncMinimumInterval: TimeInterval = 15 * 60

    /// 已添加的来源一律跟随目录：目录里同 id 的规则与本地不同，就用目录版覆盖本地副本。
    ///
    /// 中文注释：规则在 App 内只读（`BCA-UI-003`），本地副本不可能被用户改过，覆盖不会丢任何用户数据；
    /// 覆盖走同一条添加路径，`createdAt` / `enabled` / `origin` 与阅读历史都不动。
    /// 与个人规则的 `refreshPersonalSourcesFromOutcomes` 是同一条原则：规则内容由服务器裁决。
    /// - Parameter trigger: 为 nil 时不上报 `catalog_rules_updated`。
    @MainActor
    func applyCatalogRuleUpdates(_ catalogSources: [CatalogSource], trigger: CatalogUpdateTrigger? = nil) async {
        let summary: CatalogRuleUpdateSummary? = await self.applyRuleUpdatesFollowingServer(
            catalogSources,
            event: "catalog-sources-updated"
        )
        guard let trigger: CatalogUpdateTrigger = trigger,
              let summary: CatalogRuleUpdateSummary = summary else {
            return
        }
        AppAnalytics.shared.logCatalogRulesUpdated(
            trigger: trigger,
            updatedCount: summary.updatedCount,
            result: summary.result
        )
    }

    /// 中文注释：目录跟随的共同路径（复审 B-4）：比较与物化在用例里、离开主线程，先比指纹再物化；
    /// 有更新的条目合成一个写事务写入，最后只重读一次来源表。不走 `addCatalogSource`——
    /// 后台自动覆盖不该碰当前选择，也不该触发 `latestSourceAddID` 的切标签。
    /// 返回这次跟随的结局；没有可更新的条目时返回 nil。
    @MainActor
    @discardableResult
    private func applyRuleUpdatesFollowingServer(
        _ catalogSources: [CatalogSource],
        event: String
    ) async -> CatalogRuleUpdateSummary? {
        let existingSources: [Source] = self.sources
        let plan: CatalogRuleUpdatePlan
        do {
            plan = try await self.catalogService.ruleUpdates(in: catalogSources, existingSources: existingSources)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-rule-update-plan-error")
            return CatalogRuleUpdateSummary(updatedCount: 0, result: .failed)
        }
        if plan.unchangedFingerprintsBySourceID.isEmpty == false {
            do {
                try await self.catalogService.stampCatalogRuleFingerprints(plan.unchangedFingerprintsBySourceID)
            } catch {
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-rule-fingerprint-stamp-error")
            }
        }
        guard plan.updates.isEmpty == false else {
            return nil
        }
        let applied: AppliedCatalogRuleUpdates
        do {
            applied = try await self.catalogService.applyRuleUpdates(plan.updates, existingSources: existingSources)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-update-failed")
            return CatalogRuleUpdateSummary(updatedCount: 0, result: .failed)
        }
        for (sourceID, reason) in applied.failuresBySourceID {
            AppLog.error(.rule, "catalog-source-update-failed", ["sourceID": .id(sourceID), "reason": .code(reason)])
        }
        // 中文注释：有条目物化失败、保留旧规则时整次记 failed，条数仍按实际写入的算。
        let summary: CatalogRuleUpdateSummary = CatalogRuleUpdateSummary(
            updatedCount: applied.sources.count,
            result: applied.failuresBySourceID.isEmpty ? .success : .failed
        )
        guard applied.sources.isEmpty == false else {
            return applied.failuresBySourceID.isEmpty ? nil : summary
        }
        await self.load()
        AppLog.notice(.rule, event, ["count": .int(applied.sources.count)])
        return summary
    }

    /// 读取当前用户的生成终态；失败只记日志，不覆盖目录的错误提示。
    @MainActor
    private func loadVideoGenerationOutcomes() async {
        guard let useCase: LoadVideoGenerationOutcomesUseCase = self.loadVideoGenerationOutcomesUseCase else {
            return
        }
        let load: VideoGenerationOutcomesLoad = await useCase.execute()
        if case .failed(let code) = load {
            AppLog.error(.push, "outcomes-load-failed", ["code": .code(code)])
            // 中文注释：读取失败时保留上一次的结果，不把个人分组清空。
            if self.videoGenerationOutcomesLoad == nil {
                self.videoGenerationOutcomesLoad = load
            }
            return
        }
        if case .loaded(let outcomes) = load {
            AppLog.notice(.push, "outcomes-loaded", [
                "count": .int(outcomes.count),
                "succeeded": .int(outcomes.filter(\.didSucceed).count)
            ])
        } else {
            AppLog.notice(.push, "outcomes-auth-required")
        }
        self.videoGenerationOutcomesLoad = load
        if case .loaded(let outcomes) = load {
            await self.removePersonalSourcesMissingFromOutcomes(outcomes)
            await self.refreshPersonalSourcesFromOutcomes(outcomes)
        }
    }

    /// 中文注释：个人规则的**内容**同样由服务器裁决。上面那个方法做的是「服务端说它没了就删本地」，
    /// 本方法是对称的另一半：「服务端说它变了就更新本地」。
    ///
    /// 缺了这一半，用户自己刚生成的规则要等他去来源列表点一次「更新规则」才生效，而推送已经
    /// 告诉他成功了。`BC-CATALOG-071` 让第二个入口并进已有来源之后这条缝更明显——「成功」的
    /// 表现形式是已有来源多一个分类，而不是列表多一条，用户回到库里会觉得什么都没发生。
    ///
    /// **判据是「这次变化是不是我触发的」**（用户 2026-09-22 裁定）：本地来源是个人生成的，**或者**这条成功结果
    /// 完成于本地副本最后一次更新之后——即这次变化来自我自己的生成（例如我的新入口并进了一条从公共目录加的来源，
    /// `BC-CATALOG-071`）。此前只认 `origin == .personalGeneration`，同样是「我点了生成」，重新生成自动更新、
    /// 并进公共来源却要手动点「更新」，两种操作不一致。公共目录里的变化由 `applyCatalogRuleUpdates`
    /// 在读取目录时同样自动覆盖（2026-09-30 用户裁定：推荐由服务器给，本地副本跟随服务器，不再设手动更新）。
    @MainActor
    private func refreshPersonalSourcesFromOutcomes(_ outcomes: [VideoGenerationOutcome]) async {
        var candidates: [CatalogSource] = []
        for outcome: VideoGenerationOutcome in outcomes where outcome.didSucceed {
            guard let catalogSource: CatalogSource = outcome.catalogSource,
                  let existing: Source = self.sources.first(where: { source in
                      return source.id == catalogSource.id
                  }),
                  existing.origin == .personalGeneration
                      || (outcome.finishedDate.map { $0 > existing.updatedAt } ?? false) else {
                continue
            }
            candidates.append(catalogSource)
        }
        guard candidates.isEmpty == false else {
            return
        }
        await self.applyRuleUpdatesFollowingServer(candidates, event: "personal-sources-refreshed")
    }

    /// 中文注释：个人规则的存活由服务器裁决（7 天可见期、软删除）。标记为「来自个人生成」的本地来源
    /// 一旦不在 `/outcomes` 的成功任务里，本地副本随之删除。只在读取成功时执行——读取失败或未登录时
    /// 保留，避免离线或掉线把用户的来源清空。按 `catalogSourceID` 比对而不是按解密后的规则，
    /// 解密失败不会误删。
    @MainActor
    private func removePersonalSourcesMissingFromOutcomes(_ outcomes: [VideoGenerationOutcome]) async {
        let liveSourceIDs: Set<String> = Set(
            outcomes.filter(\.didSucceed).compactMap(\.catalogSourceID)
        )
        let expiredSourceIDs: [String] = self.sources
            .filter { source in
                return source.origin == .personalGeneration && liveSourceIDs.contains(source.id) == false
            }
            .map(\.id)
        guard expiredSourceIDs.isEmpty == false else {
            return
        }
        do {
            try await self.deleteSourcesWithoutUndo(ids: expiredSourceIDs)
            AppLog.notice(.push, "personal-sources-expired", ["count": .int(expiredSourceIDs.count)])
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "personal-source-expire-error")
        }
    }

    func isCatalogSourceAdded(_ catalogSource: CatalogSource) -> Bool {
        return self.sources.contains { source in
            return source.id == catalogSource.id
        }
    }

    /// 中文注释：已添加的来源，目录里的规则是否比本地新（2026-09-14 biquhua 复验倒查：服务器替换了规则，
    /// 目录刷新只重拉列表、「已添加」行没有动作，老用户只能删掉重加、连历史一起丢）。
    /// 为真时由 `applyCatalogRuleUpdates` / `refreshPersonalSourcesFromOutcomes` 自动覆盖本地副本，界面不再有「更新」按钮。
    /// 判据是**规则本体不同**：把目录条目按本地来源的 createdAt / updatedAt / enabled / origin 物化后，
    /// 比较名称、站点地址与配置；物化失败（规则不合法）按「无更新」处理，交给添加路径报错。
    func catalogSourceHasRuleUpdate(_ catalogSource: CatalogSource) -> Bool {
        guard let existing: Source = self.sources.first(where: { $0.id == catalogSource.id }) else {
            return false
        }
        guard let candidate: Source = try? CatalogSourceMaterializer().source(
            from: catalogSource,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            enabled: existing.enabled,
            origin: existing.origin
        ) else {
            return false
        }
        return candidate.name != existing.name
            || candidate.baseURL != existing.baseURL
            || candidate.configuration != existing.configuration
    }

    /// 中文注释：规则目录添加超过总时限时，在那一行留「这个网站太久没有响应，请稍后再试。」；
    /// 超时算失败，报 `source_added` failed（error_code 按网络类）。用户自己点「取消」不报。
    @MainActor
    func recordCatalogSourceAddTimeout(_ catalogSource: CatalogSource, entry: SourceAddEntry? = nil) {
        self.catalogSourceAddFailureMessages[catalogSource.id] = NSLocalizedString("catalog_add_timeout", comment: "")
        AppLog.notice(.rule, "catalog-source-add-timed-out", ["source": .id(catalogSource.id)])
        if let entry: SourceAddEntry = entry {
            AppAnalytics.shared.logSourceAdded(
                source: nil,
                kind: AnalyticsContentKind(catalogSourceKind: catalogSource.kind),
                entry: entry,
                result: .failed,
                errorCode: AnalyticsErrorCode(DiagnosticFailureKind.network)
            )
        }
    }

    @MainActor
    /// - Parameter preserveSelection: 自动更新已添加来源时为真——**不得把用户从他正在看的来源上拽走**。
    ///   为真时只有当这条来源就是当前选中的那条，才重建库快照；其余情况只覆盖数据、不动界面。
    /// - Parameter entry: 在规则目录的哪一块点的添加；为 nil 时不上报 `source_added`。
    func addCatalogSource(
        _ catalogSource: CatalogSource,
        entry: SourceAddEntry? = nil,
        shouldPresentError: Bool = true,
        preserveSelection: Bool = false
    ) async -> Bool {
        let analyticsKind: AnalyticsContentKind = AnalyticsContentKind(catalogSourceKind: catalogSource.kind)
        CrashDiagnostics.shared.setRuleStage(.list)
        self.catalogSourceAddFailureMessages.removeValue(forKey: catalogSource.id)
        // 中文注释：来自「我的生成」分组的规则记出身，之后服务器不再返回时本地副本随之删除；
        // 公共目录与「已生成过、直接复用」的规则不记——它们不在本人的 /outcomes 里，记了会被误删。
        // **更新已有来源时保留它原来的出身**：我的新入口并进一条从公共目录加的来源后，它也会出现在我的
        // /outcomes 里；若在这里改记成个人生成，7 天后那条结果过期，`removePersonalSourcesMissingFromOutcomes`
        // 会把这条公共来源从本地删掉。
        let existingSource: Source? = self.sources.first(where: { $0.id == catalogSource.id })
        let origin: SourceOrigin? = existingSource.map { $0.origin }
            ?? (self.catalogSourceGrouping.personalOutcomes[catalogSource.id] == nil
                ? nil
                : .personalGeneration)
        do {
            let result: AddCatalogSourceResult = try await self.catalogService.addSource(
                catalogSource,
                origin: origin
            )
            var source: Source = result.source
            source.userID = self.currentUserID
            let wasSelected: Bool = self.selectedSourceID == source.id
            await self.load()
            // 中文注释：来源增删与启用记 notice（Logging-Design.md 第 8 节）；覆盖已添加的来源时 `replaced` 为 true。
            AppLog.notice(.rule, "catalog-source-added", [
                "source": .id(source.id),
                "kind": .enumValue(catalogSource.kind),
                "replaced": .bool(existingSource != nil),
                "preserveSelection": .bool(preserveSelection)
            ])
            if let entry: SourceAddEntry = entry {
                AppAnalytics.shared.logSourceAdded(
                    source: self.source(id: source.id) ?? source,
                    kind: analyticsKind,
                    entry: entry,
                    result: .success
                )
            }
            if preserveSelection && wasSelected == false {
                // 中文注释：后台自动更新一条用户没在看的来源——数据已经覆盖，界面一个字不动。
                return true
            }
            if let listOutput: SourceListOutput = result.listOutput {
                let items: [ContentItem] = self.contentItemMapper.map(
                    output: listOutput,
                    source: source,
                    context: nil
                )
                self.sourceSelectionStore.publishLibrarySnapshot(
                    source: source,
                    items: items,
                    listContext: nil,
                    nextPage: listOutput.pagination?.nextPage
                )
                self.logPublishedLibrarySnapshot(source: source, items: items, origin: "catalog-source-add")
            }
            self.selectSource(id: source.id, savesLibraryState: true, entry: wasSelected ? nil : .catalogAdd)
            if result.listOutput != nil {
                self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            }
            self.latestSourceAddID = source.id
            self.latestCatalogSourceAddID = source.id
            return true
        } catch {
            // 中文注释：规则目录里点了「取消」或超过总时限（调用方取消了任务）：不是失败，不写失败文案、不报 `source_added`。
            // 超时的文案由 `recordCatalogSourceAddTimeout` 另写。
            if Task.isCancelled {
                AppLog.info(.rule, "catalog-source-add-cancelled", ["source": .id(catalogSource.id)])
                return false
            }
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-add-error")
            if let entry: SourceAddEntry = entry {
                AppAnalytics.shared.logSourceAdded(
                    source: nil,
                    kind: analyticsKind,
                    entry: entry,
                    result: .failed,
                    errorCode: AnalyticsErrorCode(RuleExecutionErrorClassifier.diagnosticFailureKind(for: error))
                )
            }
            let message: String = RuleExecutionErrorClassifier.userMessage(for: error)
            // 中文注释：不弹全局错误时也要把原因留在那一行——只写「加载失败」用户无从下手。
            self.catalogSourceAddFailureMessages[catalogSource.id] = message
            if shouldPresentError {
                self.errorMessage = message
            }
            return false
        }
    }

    @MainActor
    /// 中文注释：按下标删除；与按 id 删除同一条路径，只删一个时同样可撤销。
    func deleteSources(at offsets: IndexSet) async {
        let sourceIDs: [String] = offsets.map { offset in
            return self.sources[offset].id
        }
        await self.deleteSources(ids: sourceIDs, entry: .menu)
    }

    /// 中文注释：来源页的左滑与长按菜单按来源删除（`docs/design/Sources-Page-Redesign-Design.md` 2.5）：
    /// 不弹确认，删除后它的历史与收藏保留（`BCA-DB-005`），底部给出可撤销提示。
    /// - Parameter entry: 左滑还是长按菜单；撤销窗口结束、真正提交删除时随 `source_deleted` 上报。
    @MainActor
    func deleteSource(id sourceID: String, entry: SourceDeleteEntry = .menu) async {
        await self.deleteSources(ids: [sourceID], entry: entry)
    }

    /// 中文注释：用户发起的删除。新删除开始前先结束上一个撤销窗口（提示被替换）；只删一个且拿到留底时可撤销，
    /// 同步通知推迟到窗口结束；其余情况删完立刻通知。
    @MainActor
    private func deleteSources(ids sourceIDs: [String], entry: SourceDeleteEntry) async {
        self.finishUndoableDeletion()
        do {
            let result: SourcesDeletionResult = try await self.persistenceCoordinator.delete(
                sourceIDs: sourceIDs,
                userID: self.currentUserID
            )
            self.applyDeletion(result)
            AppLog.notice(.rule, "sources-deleted", [
                "count": .int(result.receipts.count),
                "source": .id(sourceIDs.count == 1 ? sourceIDs.first : nil),
                "undoable": .bool(sourceIDs.count == 1 && result.receipts.isEmpty == false),
                "entry": .enumValue(entry)
            ])
            if sourceIDs.count == 1, let receipt: SourceDeletionReceipt = result.receipts.first {
                self.showUndo(for: receipt, entry: entry)
            } else {
                // 中文注释：没有撤销窗口的删除立刻算提交。
                for receipt: SourceDeletionReceipt in result.receipts {
                    AppAnalytics.shared.logSourceDeleted(receipt.source, entry: entry)
                }
                await self.notifyDeletionChanges(for: result.receipts)
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-delete-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    /// 中文注释：不可撤销的删除（删除个人规则、个人规则过期）：删完立刻把变更告知同步。
    @MainActor
    private func deleteSourcesWithoutUndo(ids sourceIDs: [String]) async throws {
        self.finishUndoableDeletion()
        let result: SourcesDeletionResult = try await self.persistenceCoordinator.delete(
            sourceIDs: sourceIDs,
            userID: self.currentUserID
        )
        self.applyDeletion(result)
        AppLog.notice(.rule, "sources-deleted", [
            "count": .int(result.receipts.count),
            "source": .id(sourceIDs.count == 1 ? sourceIDs.first : nil),
            "undoable": .bool(false)
        ])
        await self.notifyDeletionChanges(for: result.receipts)
    }

    /// 中文注释：删除成功后的共同收尾：换上归置后的列表，当前来源不在了就选第一个在用的，并记一次内容变更。
    @MainActor
    private func applyDeletion(_ result: SourcesDeletionResult) {
        let loadedSources: [Source] = result.snapshot.sources
        self.sources = loadedSources
        self.sourceSlotLimit = result.snapshot.sourceSlotLimit

        if let selectedSourceID: String = self.selectedSourceID,
           loadedSources.contains(where: { source in
               return source.id == selectedSourceID
                   && source.accessState == .active
           }) == false {
            self.selectSource(
                id: loadedSources.first(where: { source in
                    return source.accessState == .active
                })?.id
            )
        }
        self.sourceContentRevision += 1
    }

    private func notifyDeletionChanges(for receipts: [SourceDeletionReceipt]) async {
        guard receipts.contains(where: \.enqueuedSyncChanges) else {
            return
        }
        await self.persistenceCoordinator.notifyDeletionChanges()
    }

    /// 中文注释：撤销删除：来源回到在册；删除前它是当前来源的，撤销后改回当前来源
    /// （库状态已由仓储连同列表位置一起写回，这里不再覆盖）。撤销不发删除的通知，写回后仓储照常通知。
    @MainActor
    func undoDeletion() async {
        guard let receipt: SourceDeletionReceipt = self.undoableDeletion else {
            return
        }
        self.undoDismissTask?.cancel()
        self.undoDismissTask = nil
        self.undoableDeletion = nil
        self.undoableDeletionEntry = nil
        do {
            let snapshot: SourcesPersistenceSnapshot = try await self.persistenceCoordinator.restore(
                receipt,
                userID: self.currentUserID
            )
            self.sources = snapshot.sources
            self.sourceSlotLimit = snapshot.sourceSlotLimit
            if receipt.librarySelection != nil {
                self.selectSource(id: receipt.source.id, savesLibraryState: false, entry: nil)
            }
            self.sourceContentRevision += 1
            AppLog.notice(.rule, "source-deletion-undone", ["source": .id(receipt.source.id)])
            AppAnalytics.shared.logSourceDeletionUndone(receipt.source, result: .success)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-undo-delete-error")
            AppAnalytics.shared.logSourceDeletionUndone(receipt.source, result: .failed)
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    /// 中文注释：结束撤销窗口：提示消失，攒下的删除这才告知同步。提示超时、被新删除替换、离开来源页或 App 切走时调用。
    func finishUndoableDeletion() {
        self.undoDismissTask?.cancel()
        self.undoDismissTask = nil
        guard let receipt: SourceDeletionReceipt = self.undoableDeletion else {
            return
        }
        self.undoableDeletion = nil
        AppAnalytics.shared.logSourceDeleted(receipt.source, entry: self.undoableDeletionEntry ?? .menu)
        self.undoableDeletionEntry = nil
        guard receipt.enqueuedSyncChanges else {
            return
        }
        Task { [persistenceCoordinator] in
            await persistenceCoordinator.notifyDeletionChanges()
        }
    }

    private func showUndo(for receipt: SourceDeletionReceipt, entry: SourceDeleteEntry) {
        self.undoDismissTask?.cancel()
        self.undoableDeletion = receipt
        self.undoableDeletionEntry = entry
        self.undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoDuration)
            guard Task.isCancelled == false,
                  let self = self,
                  self.undoableDeletion?.source.id == receipt.source.id else {
                return
            }
            self.finishUndoableDeletion()
        }
    }

    /// 中文注释：程序内的选择（启动兜底、删除后改选等），不上报 `source_selected`。
    func selectSource(id: String?) {
        self.selectSource(id: id, savesLibraryState: true, entry: nil)
    }

    /// - Parameter savesLibraryState: 为假时只切换当前来源、不写库状态——撤销删除时库状态已由仓储原样写回。
    /// - Parameter entry: 用户发起的切换从哪里来；为 nil（程序内的兜底选择）或当前来源没变时不上报 `source_selected`。
    private func selectSource(id: String?, savesLibraryState: Bool, entry: SourceSelectionEntry?) {
        if let source: Source = self.source(id: id),
           source.accessState == .lockedBySlotLimit {
            self.requestedSlotActivationSource = source
            self.requestedSlotActivationEntry = .sourcesList
            return
        }

        let previousSourceID: String? = self.selectedSourceID
        self.selectedSourceID = id
        self.sourceSelectionStore.selectedSourceID = id
        let selectedSource: Source? = self.source(id: id)
        CrashDiagnostics.shared.setSource(selectedSource)
        if let entry: SourceSelectionEntry = entry, previousSourceID != id {
            AppAnalytics.shared.logSourceSelected(selectedSource, entry: entry)
        }
        if savesLibraryState {
            self.saveLibraryStateForSelectedSource(lastRefreshAt: nil)
        }
    }

    /// 中文注释：已暂停的来源请求启用：打开启用来源窗口（2.4 / 2.6）。
    /// - Parameter entry: 从哪里点到了暂停的来源；窗口出结局时随 `source_activated` 上报。
    func requestSlotActivation(for source: Source, entry: SourceActivationEntry = .sourcesList) {
        guard source.accessState == .lockedBySlotLimit else {
            return
        }
        self.requestedSlotActivationSource = source
        self.requestedSlotActivationEntry = entry
    }

    /// 返回调用结束时这个来源是否是当前来源——来源页据此决定是否跳到库（`docs/design/Sources-Page-Redesign-Design.md` 2.3）：
    /// 已是当前来源为 true；切换成功为 true；被锁定、另一次切换进行中或加载第一页失败为 false。
    /// - Parameter entry: 切换从哪里发起，切换成功时随 `source_selected` 上报；失败后的重试沿用同一个入口。
    @MainActor
    @discardableResult
    func selectSourceAfterRefresh(_ source: Source, entry: SourceSelectionEntry = .sourcesList) async -> Bool {
        guard source.accessState == .active else {
            self.requestedSlotActivationSource = source
            self.requestedSlotActivationEntry = .sourcesList
            return false
        }

        if self.selectedSourceID == source.id {
            return true
        }
        if self.isRefreshing {
            return false
        }

        self.isRefreshing = true
        self.refreshingSourceID = source.id
        self.sourceSelectionStore.beginPreparingSource(source)
        defer {
            self.sourceSelectionStore.endPreparingSource(id: source.id)
        }

        do {
            let page: RefreshedListPage = try await self.refreshSourceForSelection(source)
            self.sourceSelectionStore.publishLibrarySnapshot(
                source: source,
                items: page.items,
                listContext: nil,
                nextPage: page.nextPage
            )
            self.logPublishedLibrarySnapshot(source: source, items: page.items, origin: "select-source-refresh")
            self.failedRefreshAction = nil
            self.selectSource(id: source.id, savesLibraryState: true, entry: entry)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
        } catch {
            self.failedRefreshAction = .select(sourceID: source.id, entry: entry)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-select-refresh-error")
            RuleFailureDiagnostics.report(
                error: error,
                kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error),
                stage: .list,
                point: .sourceSelectRefresh,
                source: source
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
        return self.selectedSourceID == source.id
    }

    @MainActor
    func activateRequestedSource(
        replacingSourceID: String?
    ) async -> Bool {
        guard let requestedSource: Source = self.requestedSlotActivationSource else {
            return false
        }
        let entry: SourceActivationEntry = self.requestedSlotActivationEntry ?? .sourcesList
        // 中文注释：结局在这里报，先清掉入口，窗口随后收起时 `dismissRequestedSlotActivation` 就不会再报一次取消。
        self.requestedSlotActivationEntry = nil

        do {
            let loadedSources: [Source] = try await self.persistenceCoordinator.activate(
                sourceID: requestedSource.id,
                replacingSourceID: replacingSourceID
            ).sources
            self.sources = loadedSources
            self.requestedSlotActivationSource = nil

            if let replacementSourceID: String = replacingSourceID,
               self.selectedSourceID == replacementSourceID {
                self.selectSource(id: nil)
            }

            guard let activatedSource: Source = self.source(id: requestedSource.id),
                  activatedSource.accessState == .active else {
                throw SourceRepositoryError.invalidSourceSlotReplacement
            }
            AppLog.notice(.rule, "source-activated", [
                "source": .id(activatedSource.id),
                "replaced": .id(replacingSourceID),
                "entry": .enumValue(entry)
            ])
            AppAnalytics.shared.logSourceActivated(
                activatedSource,
                entry: entry,
                result: replacingSourceID == nil ? .success : .replaced
            )
            await self.selectSourceAfterRefresh(activatedSource, entry: .activation)
            return true
        } catch {
            RuleExecutionErrorClassifier.log(
                error: error,
                stage: .list,
                event: "source-slot-activation-error"
            )
            AppAnalytics.shared.logSourceActivated(requestedSource, entry: entry, result: .failed)
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return false
        }
    }

    /// 中文注释：窗口收起（取消、下滑、「获取更多位置」）。还没出结局的算取消；启用或失败已经报过，不再报。
    func dismissRequestedSlotActivation() {
        if let entry: SourceActivationEntry = self.requestedSlotActivationEntry {
            AppAnalytics.shared.logSourceActivated(self.requestedSlotActivationSource, entry: entry, result: .cancelled)
        }
        self.requestedSlotActivationEntry = nil
        self.requestedSlotActivationSource = nil
    }

    /// 返回重试的是不是一次切换、并且这次切换成功了——来源页据此在重试成功后打开库。
    @MainActor
    @discardableResult
    func retryFailedRefresh() async -> Bool {
        let failedRefreshAction: FailedRefreshAction? = self.failedRefreshAction
        self.errorMessage = nil

        guard let failedRefreshAction: FailedRefreshAction = failedRefreshAction else {
            return false
        }

        switch failedRefreshAction {
        case .select(let sourceID, let entry):
            guard let source: Source = self.source(id: sourceID) else {
                return false
            }

            return await self.selectSourceAfterRefresh(source, entry: entry)
        case .refresh(let sourceID):
            guard let source: Source = self.source(id: sourceID) else {
                return false
            }

            await self.refreshSource(source)
            return false
        }
    }

    func clearError() {
        self.errorMessage = nil
    }

    func formattedDebugJSON(for source: Source) -> String {
        return self.ruleDebugJSONFormatter.formattedDebugJSON(for: source)
    }

    @MainActor
    func validateAllTabs(sourceID: String) async -> SourceTabsValidationResult? {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return nil
        }

        return await self.validateSourceTabsUseCase.execute(source: source)
    }

    var selectedSource: Source? {
        return self.source(id: self.selectedSourceID)
    }

    var canRetryFailedRefresh: Bool {
        return self.failedRefreshAction != nil
    }

    func source(id: String?) -> Source? {
        guard let id: String = id else {
            return nil
        }

        return self.sources.first { source in
            return source.id == id
        }
    }

    @MainActor
    private func refreshSource(_ source: Source) async {
        if self.isRefreshing {
            return
        }

        self.isRefreshing = true
        self.refreshingSourceID = source.id
        self.sourceSelectionStore.beginPreparingSource(source)
        defer {
            self.sourceSelectionStore.endPreparingSource(id: source.id)
        }

        do {
            let page: RefreshedListPage = try await self.refreshSourceForSelection(source)
            self.sourceSelectionStore.publishLibrarySnapshot(
                source: source,
                items: page.items,
                listContext: nil,
                nextPage: page.nextPage
            )
            self.logPublishedLibrarySnapshot(source: source, items: page.items, origin: "manual-refresh")
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            self.failedRefreshAction = nil
        } catch {
            self.failedRefreshAction = .refresh(sourceID: source.id)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-refresh-error")
            RuleFailureDiagnostics.report(
                error: error,
                kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error),
                stage: .list,
                point: .sourceRefresh,
                source: source
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
    }


    private func refreshSourceForSelection(_ source: Source) async throws -> RefreshedListPage {
        CrashDiagnostics.shared.setRuleStage(.list)
        // Sources 页的刷新只针对默认入口；非默认 tab 由 Library 按当前 ListContext 单独刷新。
        let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: ListContextTransfer(value: nil)
        )
        return RefreshedListPage(
            items: self.contentItemMapper.map(output: output, source: source, context: nil),
            nextPage: output.pagination?.nextPage
        )
    }

    private func saveLibraryStateForSelectedSource(lastRefreshAt: Date?) {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return
        }

        self.saveLibraryState(sourceID: selectedSourceID, lastRefreshAt: lastRefreshAt)
    }

    private func saveLibraryState(sourceID: String, lastRefreshAt: Date?) {
        let state: UserLibraryState = UserLibraryState(
            userID: self.currentUserID,
            selectedSourceID: sourceID,
            listContext: nil,
            lastRefreshAt: lastRefreshAt,
            updatedAt: self.now()
        )

        Task { [persistenceCoordinator] in
            do {
                try await persistenceCoordinator.saveLibraryState(
                    UserLibraryStateTransfer(value: state)
                )
            } catch {
                AppLog.error(.sync, "source-library-state-save-failed", ["error": .error(error)])
            }
        }
    }

    private func logPublishedLibrarySnapshot(
        source: Source,
        items: [ContentItem],
        origin: String
    ) {
        #if DEBUG
        AppLog.debug(.rule, "library-data", [
            "origin": .text("\(origin)"),
            "source": .text("\(source.id)"),
            "kind": .text("\(source.configuration.kind.rawValue)"),
            "items": .text("\(items.count)"),
            "firstItem": .text("\(items.first?.id ?? "nil")")
        ])
        #endif
    }

    private func bindSourceSelection() {
        self.sourceSelectionStore.$selectedSourceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedSourceID in
                self?.selectedSourceID = selectedSourceID
            }
            .store(in: &self.cancellables)
    }
}

extension AnalyticsContentKind {
    /// 中文注释：目录条目的 kind → 埋点 content_kind（`source_added` 失败时没有入库的来源，只能从目录条目取类型）。
    init(catalogSourceKind: CatalogSourceKind) {
        switch catalogSourceKind {
        case .comic:
            self = .comic
        case .video:
            self = .video
        case .book:
            self = .book
        }
    }
}

/// 中文注释：`generation_submitted` 失败时的 error_code。服务端失败码是开放字符串，这里归成有限几类，原始码不上报。
private enum GenerationSubmitFailureCode: String {
    case transport
    case reusedRuleKindUnsupported = "reused_rule_kind_unsupported"
    case reusedRuleDecryptionFailed = "reused_rule_decryption_failed"
    case server

    init(code: String) {
        switch code {
        case CreateVideoGenerationTaskUseCase.transportFailureCode:
            self = .transport
        case CreateVideoGenerationTaskUseCase.reusedRuleKindUnsupportedCode:
            self = .reusedRuleKindUnsupported
        case CreateVideoGenerationTaskUseCase.reusedRuleDecryptionFailedCode:
            self = .reusedRuleDecryptionFailed
        default:
            self = .server
        }
    }
}
