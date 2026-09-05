import Observation
import Combine
import Foundation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：SourcesViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：Sources 标签页的视图模型，管理源列表、选中源、刷新状态和错误信息。
/// 中文注释：SwiftUI 会观察这里的 @Published 属性，并在变化时刷新对应界面。
@MainActor
@Observable
final class SourcesViewModel {
    private struct RefreshedListPage {
        let items: [ContentItem]
        let nextPage: Int?
    }

    private enum FailedRefreshAction {
        case select(sourceID: String)
        case refresh(sourceID: String)
    }

    private(set) var sources: [Source] = []
    private(set) var selectedSourceID: String?
    var errorMessage: String?
    private(set) var isRefreshing: Bool = false
    private(set) var refreshingSourceID: String?
    private(set) var latestSourceAddID: String?
    private(set) var latestCatalogSourceAddID: String?
    private(set) var catalogSources: [CatalogSource] = []
    private(set) var isLoadingCatalogSources: Bool = false
    /// 当前用户的生成终态；nil 表示尚未读取。
    private(set) var videoGenerationOutcomesLoad: VideoGenerationOutcomesLoad?
    /// 用户点开生成推送的次数（请求信号）。
    private(set) var catalogPresentationRevision: Int = 0
    /// 中文注释：点开推送 → 待处理的导航。冷启动时主界面还在启动动画后面，`onChange` 没有
    /// 观察者、tab 也会被启动目的地覆盖，所以不能在收到时直接导航；RootView 在启动动画
    /// 结束后再消费这个标记（09-05 真机反馈）。
    private(set) var pendingCatalogPresentation: Bool = false
    /// 「规则目录」应当打开的次数；只在主界面就绪、RootView 已切到 Sources 之后递增。
    private(set) var catalogSheetRevision: Int = 0
    /// 个人规则的本地回执（catalogSourceId → 收到时刻）与本地隐藏集合。
    private(set) var personalRuleReceipts: [String: Date] = [:]
    private(set) var hiddenPersonalRuleIDs: Set<String> = []
    /// 目录里某条规则添加失败的具体原因（按 catalogSourceId），成功或刷新后清除。
    private(set) var catalogSourceAddFailureMessages: [String: String] = [:]
    private(set) var requestedSlotActivationSource: Source?
    private(set) var videoGenerationInputProgress: VideoGenerationInputPreflightProgress?
    private(set) var sourceSlotLimit: Int =
        SourceSlotPolicy.includedSiteSlotCount

    private let persistenceCoordinator: SourcesPersistenceCoordinator
    private let addComicRuleSourceUseCase: AddComicRuleSourceUseCase
    private let addRSSSourceUseCase: AddRSSSourceUseCase
    private let discoveryService: SourceDiscoveryService
    private let createVideoGenerationTaskUseCase: CreateVideoGenerationTaskUseCase?
    private let pushNotificationAuthorizer: (any PushNotificationAuthorizing)?
    private let loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase?
    private let outcomeRefreshRequests: RuleGenerationOutcomeRefreshRequests?
    private let personalRuleReceiptStore: (any PersonalRuleReceiptStoring)?
    private var outcomeRefreshTask: Task<Void, Never>?
    private let catalogService: SourceCatalogService
    private let ruleEditorService: SourceRuleEditorService
    private let ruleEditingCoordinator: SourceRuleEditingCoordinator
    private let recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase
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

    /// 目录两分组：网站默认数据 + 按当前用户生成结果挑出的个人数据。
    var catalogSourceGrouping: CatalogSourceGrouping {
        let outcomes: [VideoGenerationOutcome]
        if case .loaded(let loaded) = self.videoGenerationOutcomesLoad {
            outcomes = loaded
        } else {
            outcomes = []
        }
        return CatalogSourceGrouping.make(
            catalogSources: self.catalogSources,
            outcomes: outcomes,
            hiddenIDs: self.hiddenPersonalRuleIDs
        )
    }

    /// RootView 在主界面就绪且已切到 Sources 后调用：消费待处理导航，让「规则目录」打开。
    @discardableResult
    func presentCatalogSheetIfPending() -> Bool {
        guard self.pendingCatalogPresentation else {
            return false
        }
        self.pendingCatalogPresentation = false
        self.catalogSheetRevision += 1
        return true
    }

    /// 个人规则的剩余保留时间；还没有回执（本次刚出现、尚未记录）时按整段保留期显示。
    func personalRuleRemainingComponents(for catalogSource: CatalogSource) -> (days: Int, hours: Int) {
        let receivedAt: Date = self.personalRuleReceipts[catalogSource.id] ?? self.now()
        return PersonalRuleRetentionPolicy.remainingComponents(receivedAt: receivedAt, now: self.now())
    }

    /// 用户删除个人规则：本地隐藏 + 删掉已添加的本地副本；服务器目录不动。
    @MainActor
    func deletePersonalRule(catalogSourceID: String) async {
        await self.hidePersonalRule(id: catalogSourceID, reason: "user-delete")
    }

    /// 用户删除失败记录：只做本地隐藏。
    @MainActor
    func deleteFailedGenerationOutcome(jobID: UUID) async {
        await self.hidePersonalRule(id: jobID.uuidString, reason: "user-delete")
    }

    @MainActor
    private func hidePersonalRule(id: String, reason: String) async {
        self.hiddenPersonalRuleIDs.insert(id)
        self.personalRuleReceipts.removeValue(forKey: id)
        self.personalRuleReceiptStore?.hide(id: id, userID: self.currentUserID)
        AppLog.notice(.push, event: "personal-rule-hidden", metadata: ["reason": reason])
        if self.sources.contains(where: { source in source.id == id }) {
            do {
                let snapshot: SourcesPersistenceSnapshot = try await self.persistenceCoordinator.delete(
                    sourceIDs: [id],
                    userID: self.currentUserID
                )
                self.sources = snapshot.sources
                self.sourceSlotLimit = snapshot.sourceSlotLimit
                if self.selectedSourceID == id {
                    self.selectSource(id: snapshot.sources.first(where: { $0.accessState == .active })?.id)
                }
            } catch {
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "personal-rule-delete-error")
                self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            }
        }
    }

    /// 中文注释：读取回执，为新出现的个人规则记回执，并把到期的按「删除」处理（`PersonalRuleRetentionPolicy`）。
    @MainActor
    private func applyPersonalRuleRetention() async {
        guard let store: any PersonalRuleReceiptStoring = self.personalRuleReceiptStore else {
            return
        }
        let userID: String = self.currentUserID
        self.hiddenPersonalRuleIDs = store.hiddenIDs(userID: userID)
        let now: Date = self.now()
        for source in self.catalogSourceGrouping.personalSources {
            store.recordReceiptIfAbsent(catalogSourceID: source.id, userID: userID, receivedAt: now)
        }
        var receipts: [String: Date] = [:]
        for receipt in store.receipts(userID: userID) {
            receipts[receipt.catalogSourceID] = receipt.receivedAt
        }
        self.personalRuleReceipts = receipts
        for (catalogSourceID, receivedAt) in receipts
        where PersonalRuleRetentionPolicy.isExpired(receivedAt: receivedAt, now: now) {
            await self.hidePersonalRule(id: catalogSourceID, reason: "expired")
        }
    }

    var defaultCatalogSources: [CatalogSource] {
        return self.catalogSourceGrouping.defaultSources
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

    /// 个人分组需要登录才有内容；未接入 outcomes 用例（测试替身）时视为不需要。
    var isPersonalCatalogSignInRequired: Bool {
        return self.videoGenerationOutcomesLoad == .authRequired
    }

    init(
        persistenceCoordinator: SourcesPersistenceCoordinator,
        addComicRuleSourceUseCase: AddComicRuleSourceUseCase,
        addRSSSourceUseCase: AddRSSSourceUseCase,
        discoveryService: SourceDiscoveryService,
        createVideoGenerationTaskUseCase: CreateVideoGenerationTaskUseCase? = nil,
        pushNotificationAuthorizer: (any PushNotificationAuthorizing)? = nil,
        loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase? = nil,
        outcomeRefreshRequests: RuleGenerationOutcomeRefreshRequests? = nil,
        personalRuleReceiptStore: (any PersonalRuleReceiptStoring)? = nil,
        catalogService: SourceCatalogService,
        ruleEditorService: SourceRuleEditorService,
        ruleEditingCoordinator: SourceRuleEditingCoordinator,
        recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        validateSourceTabsUseCase: ValidateSourceTabsUseCase,
        sourceSelectionStore: SourceSelectionStore,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.addComicRuleSourceUseCase = addComicRuleSourceUseCase
        self.addRSSSourceUseCase = addRSSSourceUseCase
        self.discoveryService = discoveryService
        self.createVideoGenerationTaskUseCase = createVideoGenerationTaskUseCase
        self.pushNotificationAuthorizer = pushNotificationAuthorizer
        self.loadVideoGenerationOutcomesUseCase = loadVideoGenerationOutcomesUseCase
        self.outcomeRefreshRequests = outcomeRefreshRequests
        self.personalRuleReceiptStore = personalRuleReceiptStore
        self.catalogService = catalogService
        self.ruleEditorService = ruleEditorService
        self.ruleEditingCoordinator = ruleEditingCoordinator
        self.recommendSourceImportOptionUseCase = recommendSourceImportOptionUseCase
        self.contentItemMapper = SourceListContentItemMapper()
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceTabsUseCase = validateSourceTabsUseCase
        self.sourceSelectionStore = sourceSelectionStore
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
        self.now = now
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
        self.observeOutcomeRefreshRequests()
    }

    /// 中文注释：推送到达或被点开 → 刷新目录与个人生成结果（`BC-PREFLIGHT-058` App 侧）。
    private func observeOutcomeRefreshRequests() {
        guard let outcomeRefreshRequests: RuleGenerationOutcomeRefreshRequests =
            self.outcomeRefreshRequests else {
            return
        }
        self.outcomeRefreshTask = Task { [weak self] in
            for await trigger in outcomeRefreshRequests.requests {
                guard let self else {
                    return
                }
                AppLog.notice(
                    .push,
                    event: "outcome-refresh-requested",
                    metadata: ["trigger": trigger.rawValue]
                )
                if trigger == .opened {
                    self.pendingCatalogPresentation = true
                    self.catalogPresentationRevision += 1
                }
                await self.refreshCatalogSources()
            }
        }
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
    func discoverComicResources(siteURLString: String, keyword: String) async -> [TransientComicDiscoveryItem] {
        CrashDiagnostics.shared.setRuleStage(.search)
        do {
            let results: [TransientComicDiscoveryItem] = try await self.discoveryService.discoverComicResources(
                siteURLString: siteURLString,
                keyword: keyword
            )
            AppAnalytics.shared.logSearchSubmitted(sourceType: .comic, resultCount: results.count)
            return results
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "comic-discovery-error")
            AppAnalytics.shared.logSearchSubmitted(sourceType: .comic, resultCount: 0)
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .search, errorCode: "comic-discovery-error")
            self.errorMessage = error.localizedDescription
            return []
        }
    }

    @MainActor
    func discoverVideoResources(siteURLString: String, keyword: String) async -> [TransientVideoDiscoveryItem] {
        CrashDiagnostics.shared.setRuleStage(.search)
        do {
            let results: [TransientVideoDiscoveryItem] = try await self.discoveryService.discoverVideoResources(
                siteURLString: siteURLString,
                keyword: keyword
            )
            AppAnalytics.shared.logSearchSubmitted(sourceType: .video, resultCount: results.count)
            return results
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "video-discovery-error")
            AppAnalytics.shared.logSearchSubmitted(sourceType: .video, resultCount: 0)
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .search, errorCode: "video-discovery-error")
            self.errorMessage = error.localizedDescription
            return []
        }
    }

    @MainActor
    func assessVideoGenerationInput(
        siteURLString: String
    ) async throws -> VideoGenerationInputPreflight {
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
            return result
        } catch is CancellationError {
            if self.videoGenerationAssessmentID == assessmentID {
                self.videoGenerationInputProgress = nil
                self.videoGenerationAssessmentID = nil
            }
            throw CancellationError()
        } catch {
            if self.videoGenerationAssessmentID == assessmentID {
                self.videoGenerationInputProgress = nil
                self.videoGenerationAssessmentID = nil
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// 中文注释：未接线任务客户端时 UI 不得出现可点的「生成」（`BC-PREFLIGHT-048`）。
    var canSubmitVideoGenerationTasks: Bool {
        return self.createVideoGenerationTaskUseCase != nil
    }

    @MainActor
    func submitVideoGenerationTask(
        preflight: VideoGenerationInputPreflight
    ) async throws -> VideoGenerationTaskSubmissionOutcome {
        guard let useCase: CreateVideoGenerationTaskUseCase =
            self.createVideoGenerationTaskUseCase else {
            throw VideoGenerationTaskSubmissionRejection.preflightNotAccepted(preflight.status)
        }
        let outcome: VideoGenerationTaskSubmissionOutcome = try await useCase.execute(
            preflight: preflight
        )
        // 中文注释：任务排队成功是用户最能理解「为什么要通知权限」的时刻——终态靠推送告知。
        // 只在这一刻请求，且不阻塞提交结果的展示；已决定过的系统不会再弹。
        if case .submitted = outcome,
           let authorizer: any PushNotificationAuthorizing = self.pushNotificationAuthorizer {
            Task {
                _ = await authorizer.requestAuthorizationIfNeeded()
            }
        }
        return outcome
    }

    @MainActor
    func discoverRSSFeeds(siteURLString: String) async -> [DiscoveredRSSFeedItem] {
        CrashDiagnostics.shared.setRuleStage(.rssFeed)
        self.errorMessage = nil
        do {
            let results: [DiscoveredRSSFeedItem] = try await self.discoveryService.discoverRSSFeeds(
                siteURLString: siteURLString
            )
            AppAnalytics.shared.logSearchSubmitted(sourceType: .rss, resultCount: results.count)
            self.errorMessage = nil
            return results
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "rss-discovery-error")
            AppAnalytics.shared.logSearchSubmitted(sourceType: .rss, resultCount: 0)
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .rssFeed, errorCode: "rss-discovery-error")
            self.errorMessage = error.localizedDescription
            return []
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

    @MainActor
    /// 中文注释：addRuleSource 方法封装网站规则导入路径。
    func addRuleSource(name: String, baseURL: String, ruleJSON: String) async -> Bool {
        CrashDiagnostics.shared.setRuleStage(.list)
        AppAnalytics.shared.logRuleImportStarted(sourceType: .comic)
        do {
            let result: AddComicRuleSourceResult = try await self.addComicRuleSourceUseCase.execute(
                name: name,
                baseURL: baseURL,
                ruleJSON: ruleJSON
            )
            var source: Source = result.source
            source.userID = self.currentUserID

            await self.load()
            let items: [ContentItem] = self.contentItemMapper.map(
                output: result.listOutput,
                source: source,
                context: nil
            )
            self.sourceSelectionStore.publishLibrarySnapshot(
                source: source,
                items: items,
                listContext: nil,
                nextPage: result.listOutput.pagination?.nextPage
            )
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "rule-source-add")
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            self.latestSourceAddID = source.id
            AppAnalytics.shared.logRuleImportSucceeded(source: source)
            return true
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "rule-source-add-error")
            AppAnalytics.shared.logRuleImportFailed(sourceType: .comic, errorCode: "rule-source-add-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "rule-source-add-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return false
        }
    }

    @MainActor
    /// 中文注释：addRSSSource 方法封装公开 RSS Feed 导入路径。
    func addRSSSource(feedURLString: String, name: String? = nil) async -> Source? {
        CrashDiagnostics.shared.setRuleStage(.rssFeed)
        do {
            let result: AddRSSSourceResult = try await self.addRSSSourceUseCase.execute(
                feedURLString: feedURLString,
                name: name
            )
            var source: Source = result.source
            source.userID = self.currentUserID

            await self.load()
            let items: [ContentItem] = self.contentItemMapper.map(
                output: result.listOutput,
                source: source,
                context: nil
            )
            self.sourceSelectionStore.publishLibrarySnapshot(
                source: source,
                items: items,
                listContext: nil,
                nextPage: result.listOutput.pagination?.nextPage
            )
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "rss-source-add")
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            self.latestSourceAddID = source.id
            return source
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "rss-source-add-error")
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func loadCatalogSourcesIfNeeded() async {
        CrashDiagnostics.shared.setRuleStage(.list)
        if self.catalogSources.isEmpty == false || self.isLoadingCatalogSources {
            if self.videoGenerationOutcomesLoad == nil {
                await self.loadVideoGenerationOutcomes()
            }
            return
        }

        self.isLoadingCatalogSources = true
        defer {
            self.isLoadingCatalogSources = false
        }

        // 中文注释：目录与个人终态并行读取；个人终态失败不影响默认分组的展示。
        async let outcomes: Void = self.loadVideoGenerationOutcomes()
        do {
            self.catalogSources = try await self.catalogService.loadSources()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
        await outcomes
        await self.applyPersonalRuleRetention()
    }

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
            self.catalogSources = try await self.catalogService.loadSources()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
        await outcomes
        await self.applyPersonalRuleRetention()
    }

    /// 读取当前用户的生成终态；失败只记日志，不覆盖目录的错误提示。
    @MainActor
    private func loadVideoGenerationOutcomes() async {
        guard let useCase: LoadVideoGenerationOutcomesUseCase = self.loadVideoGenerationOutcomesUseCase else {
            return
        }
        let load: VideoGenerationOutcomesLoad = await useCase.execute()
        if case .failed(let code) = load {
            AppLog.error(.push, event: "outcomes-load-failed", metadata: ["code": code])
            // 中文注释：读取失败时保留上一次的结果，不把个人分组清空。
            if self.videoGenerationOutcomesLoad == nil {
                self.videoGenerationOutcomesLoad = load
            }
            return
        }
        if case .loaded(let outcomes) = load {
            AppLog.notice(
                .push,
                event: "outcomes-loaded",
                metadata: [
                    "count": String(outcomes.count),
                    "succeeded": String(outcomes.filter(\.didSucceed).count)
                ]
            )
        } else {
            AppLog.notice(.push, event: "outcomes-auth-required")
        }
        self.videoGenerationOutcomesLoad = load
    }

    func isCatalogSourceAdded(_ catalogSource: CatalogSource) -> Bool {
        return self.sources.contains { source in
            return source.id == catalogSource.id
        }
    }

    @MainActor
    func addCatalogSource(
        _ catalogSource: CatalogSource,
        shouldPresentError: Bool = true
    ) async -> Bool {
        CrashDiagnostics.shared.setRuleStage(.list)
        self.catalogSourceAddFailureMessages.removeValue(forKey: catalogSource.id)
        do {
            let result: AddCatalogSourceResult = try await self.catalogService.addSource(catalogSource)
            var source: Source = result.source
            source.userID = self.currentUserID
            await self.load()
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
            self.selectSource(id: source.id)
            if result.listOutput != nil {
                self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            }
            self.latestSourceAddID = source.id
            self.latestCatalogSourceAddID = source.id
            return true
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-add-error")
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
    /// 中文注释：deleteSources 方法封装当前类型的一段业务或界面行为。
    func deleteSources(at offsets: IndexSet) async {
        do {
            let sourceIDs: [String] = offsets.map { offset in
                return self.sources[offset].id
            }
            let snapshot: SourcesPersistenceSnapshot = try await self.persistenceCoordinator.delete(
                sourceIDs: sourceIDs,
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
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-delete-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func selectSource(id: String?) {
        if let source: Source = self.source(id: id),
           source.accessState == .lockedBySlotLimit {
            self.requestedSlotActivationSource = source
            return
        }

        self.selectedSourceID = id
        self.sourceSelectionStore.selectedSourceID = id
        let selectedSource: Source? = self.source(id: id)
        CrashDiagnostics.shared.setSource(selectedSource)
        AppAnalytics.shared.logSourceSelected(selectedSource)
        self.saveLibraryStateForSelectedSource(lastRefreshAt: nil)
    }

    @MainActor
    func selectSourceAfterRefresh(_ source: Source) async {
        guard source.accessState == .active else {
            self.requestedSlotActivationSource = source
            return
        }

        if self.selectedSourceID == source.id || self.isRefreshing {
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
            self.logPublishedLibrarySnapshot(source: source, items: page.items, origin: "select-source-refresh")
            self.failedRefreshAction = nil
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
        } catch {
            self.failedRefreshAction = .select(sourceID: source.id)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-select-refresh-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "source-select-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
    }

    @MainActor
    func activateRequestedSource(
        replacingSourceID: String?
    ) async -> Bool {
        guard let requestedSource: Source = self.requestedSlotActivationSource else {
            return false
        }

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
            await self.selectSourceAfterRefresh(activatedSource)
            return true
        } catch {
            RuleExecutionErrorClassifier.log(
                error: error,
                stage: .list,
                event: "source-slot-activation-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return false
        }
    }

    func dismissRequestedSlotActivation() {
        self.requestedSlotActivationSource = nil
    }

    @MainActor
    /// 中文注释：refreshSelectedSource 方法封装当前类型的一段业务或界面行为。
    func refreshSelectedSource() async {
        guard let selectedSource: Source = self.selectedSource else {
            return
        }

        await self.refreshSource(selectedSource)
    }

    @MainActor
    func retryFailedRefresh() async {
        let failedRefreshAction: FailedRefreshAction? = self.failedRefreshAction
        self.errorMessage = nil

        guard let failedRefreshAction: FailedRefreshAction = failedRefreshAction else {
            return
        }

        switch failedRefreshAction {
        case .select(let sourceID):
            guard let source: Source = self.source(id: sourceID) else {
                return
            }

            await self.selectSourceAfterRefresh(source)
        case .refresh(let sourceID):
            guard let source: Source = self.source(id: sourceID) else {
                return
            }

            await self.refreshSource(source)
        }
    }

    func clearError() {
        self.errorMessage = nil
    }

    func recommendSourceImport(
        draft: SourceImportDraft,
        selectedOptionKind: SourceImportOptionKind? = nil,
        html: String? = nil,
        headers: [String: String] = [:]
    ) -> SourceImportRecommendation {
        return self.recommendSourceImportOptionUseCase.execute(
            draft: draft,
            selectedOptionKind: selectedOptionKind,
            html: html,
            headers: headers
        )
    }

    func validateRuleJSON(_ ruleJSON: String) -> SiteRuleValidationResult {
        return self.ruleEditorService.validateRuleJSON(ruleJSON)
    }

    func formattedRuleJSON(for rule: SiteRule) -> String {
        return self.ruleEditorService.formattedRuleJSON(for: rule)
    }

    func formattedDebugJSON(for source: Source) -> String {
        return self.ruleEditorService.formattedDebugJSON(for: source)
    }

    func canEditDebugJSON(for source: Source) -> Bool {
        return self.ruleEditorService.canEditDebugJSON(for: source)
    }

    func validateDebugJSON(sourceID: String, json: String) -> SourceDebugJSONValidationResult {
        guard let source: Source = self.source(id: sourceID) else {
            return SourceDebugJSONValidationResult(isValid: false, message: "Source was not found.")
        }

        return self.ruleEditorService.validateDebugJSON(source: source, json: json)
    }

    @MainActor
    func validateAllTabs(sourceID: String) async -> SourceTabsValidationResult? {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return nil
        }

        return await self.validateSourceTabsUseCase.execute(source: source)
    }

    @MainActor
    func updateSourceRule(sourceID: String, ruleJSON: String, expectedUpdatedAt: Date? = nil) async -> Bool {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return false
        }

        do {
            let updatedSource: Source = try await self.ruleEditingCoordinator.updateRule(
                source: SourceTransfer(value: source),
                ruleJSON: ruleJSON,
                expectedUpdatedAt: expectedUpdatedAt
            ).value
            self.replaceSource(updatedSource)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func updateDebugJSON(sourceID: String, json: String, expectedUpdatedAt: Date? = nil) async -> Bool {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return false
        }

        do {
            let updatedSource: Source = try await self.ruleEditingCoordinator.updateDebugJSON(
                source: SourceTransfer(value: source),
                json: json,
                expectedUpdatedAt: expectedUpdatedAt
            ).value
            self.replaceSource(updatedSource)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func duplicateSource(sourceID: String) async -> Source? {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return nil
        }

        do {
            let duplicatedSource: Source = try await self.ruleEditingCoordinator
                .duplicate(SourceTransfer(value: source)).value
            await self.load()
            guard let persistedSource: Source = self.source(id: duplicatedSource.id) else {
                self.errorMessage = "The duplicated source could not be reloaded."
                return nil
            }
            self.selectSource(id: persistedSource.id)
            return persistedSource
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func exportRulePackage(sourceID: String) async -> RulePackageExport? {
        do {
            return try await self.ruleEditingCoordinator.export(sourceID: sourceID).value
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func importRulePackage(packageJSON: String) async -> Source? {
        AppAnalytics.shared.logRuleImportStarted(sourceType: .unknown)
        do {
            let importedSource: Source = try await self.ruleEditingCoordinator
                .importPackage(packageJSON).value
            await self.load()
            guard let persistedSource: Source = self.source(id: importedSource.id) else {
                self.errorMessage = "The imported source could not be reloaded."
                return nil
            }
            self.selectSource(id: persistedSource.id)
            AppAnalytics.shared.logRuleImportSucceeded(source: persistedSource)
            return persistedSource
        } catch {
            AppAnalytics.shared.logRuleImportFailed(sourceType: .unknown, errorCode: "rule-package-import-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "rule-package-import-error")
            self.errorMessage = error.localizedDescription
            return nil
        }
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
    private func replaceSource(_ source: Source) {
        guard let index: Array<Source>.Index = self.sources.firstIndex(where: { existingSource in
            return existingSource.id == source.id
        }) else {
            self.sources.append(source)
            return
        }

        self.sources[index] = source
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
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "source-refresh-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "source-refresh-error",
                event: "source-refresh-error"
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
                AppLog.error(
                    .sync,
                    event: "source-library-state-save-failed",
                    metadata: ["error": AppLog.safeErrorCode(error)]
                )
            }
        }
    }

    private func logPublishedLibrarySnapshot(
        source: Source,
        items: [ContentItem],
        origin: String
    ) {
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftLibraryData] origin=\(origin) " +
            "source=\(source.id) " +
            "kind=\(source.configuration.kind.rawValue) " +
            "items=\(items.count) " +
            "firstItem=\(items.first?.id ?? "nil")"
        )
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

private extension String {
    var nilIfEmpty: String? {
        return self.isEmpty ? nil : self
    }
}
