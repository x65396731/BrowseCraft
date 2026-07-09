import Combine
import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

// 中文注释：SourcesViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：Sources 标签页的视图模型，管理源列表、选中源、刷新状态和错误信息。
/// 中文注释：SwiftUI 会观察这里的 @Published 属性，并在变化时刷新对应界面。
final class SourcesViewModel: ObservableObject {
    private enum FailedRefreshAction {
        case select(sourceID: String)
        case refresh(sourceID: String)
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var selectedSourceID: String?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var refreshingSourceID: String?
    @Published private(set) var latestCatalogSourceAddID: String?
    @Published private(set) var catalogSources: [BrowseCraftCatalogSource] = []
    @Published private(set) var isLoadingCatalogSources: Bool = false

    private let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let addComicRuleSourceUseCase: AddComicRuleSourceUseCase
    private let addRSSSourceUseCase: AddRSSSourceUseCase
    private let addVideoSourceUseCase: AddVideoSourceUseCase
    private let discoverComicResourcesUseCase: DiscoverComicResourcesUseCase
    private let addCatalogSourceUseCase: AddCatalogSourceUseCase
    private let loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase
    private let deleteSourceUseCase: DeleteSourceUseCase
    private let updateSourceRuleUseCase: UpdateSourceRuleUseCase
    private let duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase
    private let exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase
    private let importSourceRulePackageUseCase: ImportSourceRulePackageUseCase
    private let recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase
    private let ruleValidator: SiteRuleValidator
    private let jsonEncoder: JSONEncoder
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private let userID: String
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var failedRefreshAction: FailedRefreshAction?

    init(
        syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        addComicRuleSourceUseCase: AddComicRuleSourceUseCase,
        addRSSSourceUseCase: AddRSSSourceUseCase,
        addVideoSourceUseCase: AddVideoSourceUseCase,
        discoverComicResourcesUseCase: DiscoverComicResourcesUseCase,
        addCatalogSourceUseCase: AddCatalogSourceUseCase,
        loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase,
        deleteSourceUseCase: DeleteSourceUseCase,
        updateSourceRuleUseCase: UpdateSourceRuleUseCase,
        duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase,
        exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase,
        importSourceRulePackageUseCase: ImportSourceRulePackageUseCase,
        recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase,
        ruleValidator: SiteRuleValidator = SiteRuleValidator(),
        jsonEncoder: JSONEncoder = JSONEncoder(),
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase,
        sourceSelectionStore: SourceSelectionStore,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.syncBuiltInSourcesUseCase = syncBuiltInSourcesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.addComicRuleSourceUseCase = addComicRuleSourceUseCase
        self.addRSSSourceUseCase = addRSSSourceUseCase
        self.addVideoSourceUseCase = addVideoSourceUseCase
        self.discoverComicResourcesUseCase = discoverComicResourcesUseCase
        self.addCatalogSourceUseCase = addCatalogSourceUseCase
        self.loadCatalogSourcesUseCase = loadCatalogSourcesUseCase
        self.deleteSourceUseCase = deleteSourceUseCase
        self.updateSourceRuleUseCase = updateSourceRuleUseCase
        self.duplicateSourceRuleUseCase = duplicateSourceRuleUseCase
        self.exportSourceRulePackageUseCase = exportSourceRulePackageUseCase
        self.importSourceRulePackageUseCase = importSourceRulePackageUseCase
        self.recommendSourceImportOptionUseCase = recommendSourceImportOptionUseCase
        self.ruleValidator = ruleValidator
        self.jsonEncoder = jsonEncoder
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.saveUserLibraryStateUseCase = saveUserLibraryStateUseCase
        self.sourceSelectionStore = sourceSelectionStore
        self.userID = userID
        self.now = now
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            try self.syncBuiltInSourcesUseCase.execute()
            let loadedSources: [Source] = try self.loadSourcesUseCase.execute()
            self.sources = loadedSources

            if self.selectedSourceID == nil {
                self.selectSource(id: loadedSources.first?.id)
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    @MainActor
    func discoverComicResources(siteURLString: String, keyword: String) async -> [TransientComicDiscoveryItem] {
        do {
            return try await self.discoverComicResourcesUseCase.execute(
                DiscoverComicResourcesInput(
                    siteURLString: siteURLString,
                    keyword: keyword
                )
            )
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "comic-discovery-error")
            self.errorMessage = error.localizedDescription
            return []
        }
    }

    @MainActor
    /// 中文注释：addRuleSource 方法封装网站规则导入路径。
    func addRuleSource(name: String, baseURL: String, ruleJSON: String) async -> Bool {
        do {
            let result: AddComicRuleSourceResult = try await self.addComicRuleSourceUseCase.execute(
                name: name,
                baseURL: baseURL,
                ruleJSON: ruleJSON
            )
            let source: Source = result.source

            self.load()
            let items: [ContentItem] = self.contentItems(from: result.listOutput, source: source)
            self.sourceSelectionStore.publishLibrarySnapshot(source: source, items: items)
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "rule-source-add")
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            return true
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "rule-source-add-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return false
        }
    }

    @MainActor
    /// 中文注释：addRSSSource 方法封装公开 RSS Feed 导入路径。
    func addRSSSource(feedURLString: String, name: String? = nil) async -> Source? {
        do {
            let result: AddRSSSourceResult = try await self.addRSSSourceUseCase.execute(
                feedURLString: feedURLString,
                name: name
            )
            let source: Source = result.source

            self.load()
            let items: [ContentItem] = self.contentItems(from: result.listOutput, source: source)
            self.sourceSelectionStore.publishLibrarySnapshot(source: source, items: items)
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "rss-source-add")
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            return source
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "rss-source-add-error")
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func addManualVideoSource(
        entryURLString: String,
        name: String? = nil,
        configuration: ManualVideoSourceConfigurationDraft
    ) async -> Source? {
        do {
            let result: AddManualVideoSourceResult = try await self.addVideoSourceUseCase.saveManualVideoSource(
                entryURLString: entryURLString,
                name: name,
                configuration: configuration
            )
            let source: Source = result.source

            self.load()
            let items: [ContentItem] = self.contentItems(from: result.listOutput, source: source)
            self.sourceSelectionStore.publishLibrarySnapshot(source: source, items: items)
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "manual-video-source-add")
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            return source
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "manual-video-source-add-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return nil
        }
    }

    @MainActor
    func loadCatalogSourcesIfNeeded() async {
        if self.catalogSources.isEmpty == false || self.isLoadingCatalogSources {
            return
        }

        self.isLoadingCatalogSources = true
        defer {
            self.isLoadingCatalogSources = false
        }

        do {
            self.catalogSources = try await self.loadCatalogSourcesUseCase.execute()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func isCatalogSourceAdded(_ catalogSource: BrowseCraftCatalogSource) -> Bool {
        return self.sources.contains { source in
            return source.id == catalogSource.id
        }
    }

    @MainActor
    func addCatalogSource(_ catalogSource: BrowseCraftCatalogSource) async -> Bool {
        do {
            let result: AddCatalogSourceResult = try await self.addCatalogSourceUseCase.execute(catalogSource)
            let source: Source = result.source
            self.load()
            if let listOutput: SourceListOutput = result.listOutput {
                let items: [ContentItem] = self.contentItems(from: listOutput, source: source)
                self.sourceSelectionStore.publishLibrarySnapshot(source: source, items: items)
                self.logPublishedLibrarySnapshot(source: source, items: items, origin: "catalog-source-add")
            }
            self.selectSource(id: source.id)
            if result.listOutput != nil {
                self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            }
            self.latestCatalogSourceAddID = source.id
            return true
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "catalog-source-add-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return false
        }
    }

    @MainActor
    /// 中文注释：deleteSources 方法封装当前类型的一段业务或界面行为。
    func deleteSources(at offsets: IndexSet) {
        do {
            let sourceIDs: [String] = offsets.map { offset in
                return self.sources[offset].id
            }

            for sourceID: String in sourceIDs {
                try self.deleteSourceUseCase.execute(sourceId: sourceID)
            }

            let loadedSources: [Source] = try self.loadSourcesUseCase.execute()
            self.sources = loadedSources

            if let selectedSourceID: String = self.selectedSourceID,
               loadedSources.contains(where: { source in source.id == selectedSourceID }) == false {
                self.selectSource(id: loadedSources.first?.id)
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-delete-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func selectSource(id: String?) {
        self.selectedSourceID = id
        self.sourceSelectionStore.selectedSourceID = id
        self.saveLibraryStateForSelectedSource(lastRefreshAt: nil)
    }

    @MainActor
    func selectSourceAfterRefresh(_ source: Source) async {
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
            let items: [ContentItem] = try await self.refreshSourceForSelection(source)
            self.sourceSelectionStore.publishLibrarySnapshot(source: source, items: items)
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "select-source-refresh")
            self.failedRefreshAction = nil
            self.selectSource(id: source.id)
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
        } catch {
            self.failedRefreshAction = .select(sourceID: source.id)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-select-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
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
        return self.ruleValidator.validate(ruleJSON: ruleJSON)
    }

    func formattedRuleJSON(for rule: SiteRule) -> String {
        do {
            let encodedRule: Data = try self.jsonEncoder.encode(rule)
            return String(data: encodedRule, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    @MainActor
    func updateSourceRule(sourceID: String, ruleJSON: String, expectedUpdatedAt: Date? = nil) -> Bool {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return false
        }

        do {
            let updatedSource: Source = try self.updateSourceRuleUseCase.execute(
                source: source,
                ruleJSON: ruleJSON,
                expectedUpdatedAt: expectedUpdatedAt
            )
            self.replaceSource(updatedSource)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func duplicateSource(sourceID: String) -> Source? {
        guard let source: Source = self.source(id: sourceID) else {
            self.errorMessage = "Source was not found."
            return nil
        }

        do {
            let duplicatedSource: Source = try self.duplicateSourceRuleUseCase.execute(source: source)
            self.load()
            self.selectSource(id: duplicatedSource.id)
            return duplicatedSource
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func exportRulePackage(sourceID: String) -> RulePackageExport? {
        do {
            return try self.exportSourceRulePackageUseCase.execute(sourceID: sourceID)
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func importRulePackage(packageJSON: String) -> Source? {
        do {
            let importedSource: Source = try self.importSourceRulePackageUseCase.execute(packageJSON: packageJSON)
            self.load()
            self.selectSource(id: importedSource.id)
            return importedSource
        } catch {
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
            self.load()
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
            let items: [ContentItem] = try await self.refreshSourceForSelection(source)
            self.sourceSelectionStore.publishLibrarySnapshot(source: source, items: items)
            self.logPublishedLibrarySnapshot(source: source, items: items, origin: "manual-refresh")
            self.saveLibraryState(sourceID: source.id, lastRefreshAt: self.now())
            self.failedRefreshAction = nil
        } catch {
            self.failedRefreshAction = .refresh(sourceID: source.id)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
    }


    private func refreshSourceForSelection(_ source: Source) async throws -> [ContentItem] {
        let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: nil
        )
        return self.contentItems(from: output, source: source)
    }

    private func contentItems(from output: SourceListOutput, source: Source) -> [ContentItem] {
        return output.items.enumerated().map { index, item in
            return ContentItem(
                id: item.id,
                sourceId: source.id,
                title: item.title,
                detailURL: item.detailURL?.absoluteString ?? item.id,
                coverURL: item.coverURL?.absoluteString,
                type: self.contentType(for: source),
                latestText: item.latestText,
                updatedAt: item.updatedAt,
                listOrder: index,
                listContext: nil
            )
        }
    }

    private func saveLibraryStateForSelectedSource(lastRefreshAt: Date?) {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return
        }

        self.saveLibraryState(sourceID: selectedSourceID, lastRefreshAt: lastRefreshAt)
    }

    private func saveLibraryState(sourceID: String, lastRefreshAt: Date?) {
        let state: UserLibraryState = UserLibraryState(
            userID: self.userID,
            selectedSourceID: sourceID,
            listContext: nil,
            lastRefreshAt: lastRefreshAt,
            updatedAt: self.now()
        )

        do {
            try self.saveUserLibraryStateUseCase.execute(state: state)
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftUserLibraryState] source save failed " +
                "sourceID=\(sourceID) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func contentType(for source: Source) -> SourceContentKind {
        switch source.configuration {
        case .rss:
            return .article
        case .comic:
            return .comic
        case .video:
            return .video
        case .plugin:
            return .article
        }
    }

    private func logPublishedLibrarySnapshot(
        source: Source,
        items: [ContentItem],
        origin: String
    ) {
        #if DEBUG
        print(
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
