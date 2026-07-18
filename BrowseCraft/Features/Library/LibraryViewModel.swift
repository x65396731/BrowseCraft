import Combine
import Foundation
import BrowseCraftCore

// 中文注释：LibraryViewModel 负责 Library 当前 source、runtime 刷新、当前快照和列表状态。

struct LibraryListTabState: Identifiable, Hashable {
    let id: String
    let title: String
    let isSelected: Bool
}

enum LibrarySourceLoginStatus: Hashable {
    case guest
    case authenticated
}

struct LibrarySourceLoginState: Hashable, Identifiable {
    let sourceID: String
    let sourceName: String
    let baseURL: URL
    let loginURL: URL
    let credentialKeys: [String]
    let status: LibrarySourceLoginStatus

    var id: String {
        return "\(self.sourceID)|\(self.loginURL.absoluteString)"
    }
}

// 中文注释：L1 仅解析当前 Source 是否声明登录入口及已有凭据状态；WebUI 登录行为由 L2 接入。
struct LibrarySourceLoginStateResolver {
    let credentialStore: SourceCredentialStoring
    let now: () -> Date

    init(
        credentialStore: SourceCredentialStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.now = now
    }

    func resolve(source: Source?) -> LibrarySourceLoginState? {
        guard let source: Source,
              let loginURL: URL = self.loginURL(for: source),
              let baseURL: URL = URL(string: source.baseURL) else {
            return nil
        }

        return LibrarySourceLoginState(
            sourceID: source.id,
            sourceName: source.name,
            baseURL: baseURL,
            loginURL: loginURL,
            credentialKeys: self.credentialKeys(for: source),
            status: self.hasActiveCredential(for: source.id) ? .authenticated : .guest
        )
    }

    private func loginURL(for source: Source) -> URL? {
        guard case .comic(let configuration) = source.configuration,
              let rawLoginURL: String = configuration.rule.site?.loginURL else {
            return nil
        }

        let loginURLString: String = rawLoginURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loginURLString.isEmpty == false,
              let loginURL: URL = URL(string: loginURLString),
              let scheme: String = loginURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return loginURL
    }

    private func credentialKeys(for source: Source) -> [String] {
        guard case .comic(let configuration) = source.configuration,
              let context: [String: SiteRuleContextValue] = configuration.rule.context else {
            return []
        }

        let keys: Set<String> = Set(context.values.compactMap { value in
            return value.userValue.flatMap(self.credentialKey(from:))
        })
        return keys.sorted()
    }

    private func credentialKey(from template: String) -> String? {
        var value: String = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("{") && value.hasSuffix("}") {
            value.removeFirst()
            value.removeLast()
        }

        let prefix: String = "credentialStore."
        guard value.hasPrefix(prefix) else {
            return nil
        }

        let key: String = String(value.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false,
              key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return key
    }

    private func hasActiveCredential(for sourceID: String) -> Bool {
        guard let credential: SourceCredential = self.credentialStore.credential(sourceID: sourceID),
              credential.expiresAt.map({ $0 > self.now() }) ?? true else {
            return false
        }

        let now: Date = self.now()
        let hasActiveCookie: Bool = credential.cookies.contains { cookie in
            return cookie.expiresDate.map({ $0 > now }) ?? true
        }

        return hasActiveCookie
            || credential.headers.isEmpty == false
            || credential.accessToken?.isEmpty == false
            || credential.refreshToken?.isEmpty == false
            || credential.localStorage.isEmpty == false
            || credential.sessionStorage.isEmpty == false
    }
}

private struct LibraryListCacheEntry {
    let sourceID: String
    let context: ListContext?
    let items: [ContentItem]
}

/// 中文注释：LibraryViewModel 以 SourceRuntimeKind 作为 Library 展示和刷新入口。
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published private(set) var favoriteItemIDs: Set<String> = []
    @Published private(set) var selectedSourceID: String?
    @Published var selectedListTabID: String?
    @Published var errorMessage: String?
    @Published private(set) var selectedListTabErrorMessage: String?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var isValidatingTabs: Bool = false
    @Published private(set) var preparingSource: SourceLoadingState?
    @Published private(set) var preparedLibrarySnapshot: SourceLibrarySnapshot?
    @Published private(set) var requestedSourceLogin: LibrarySourceLoginState?
    @Published private var credentialRevision: Int = 0

    private let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase?
    private let validateSourceTabsUseCase: ValidateSourceTabsUseCase?
    private let loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let sourceCredentialStore: SourceCredentialStoring
    private let sourceSelectionStore: SourceSelectionStore
    private let userID: String
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var tabDiscoveryAttemptedSourceIDs: Set<String> = Set<String>()
    private var tabValidationAttemptedSourceIDs: Set<String> = Set<String>()
    private var confirmedEmptyListTabKeys: Set<String> = Set<String>()
    private var listTabErrorMessages: [String: String] = [:]
    private var listCache: [String: LibraryListCacheEntry] = [:]
    /// 中文注释：刷新令牌用于避免旧 source 的慢请求回写或提前关闭当前 source 的 loading。
    private var refreshToken: Int = 0

    init(
        syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase? = nil,
        validateSourceTabsUseCase: ValidateSourceTabsUseCase? = nil,
        loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase,
        resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase,
        sourceCredentialStore: SourceCredentialStoring,
        sourceSelectionStore: SourceSelectionStore,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.syncBuiltInSourcesUseCase = syncBuiltInSourcesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.videoTabDiscoveryUseCase = videoTabDiscoveryUseCase
        self.validateSourceTabsUseCase = validateSourceTabsUseCase
        self.loadUserLibraryStateUseCase = loadUserLibraryStateUseCase
        self.saveUserLibraryStateUseCase = saveUserLibraryStateUseCase
        self.resolveLibrarySourcePresentationUseCase = resolveLibrarySourcePresentationUseCase
        self.sourceCredentialStore = sourceCredentialStore
        self.sourceSelectionStore = sourceSelectionStore
        self.userID = userID
        self.now = now
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        do {
            try self.syncBuiltInSourcesUseCase.execute()
            self.sources = try self.loadSourcesUseCase.execute()
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()

            try self.restoreStartupLibraryState()
            if self.applyPreparedSnapshotIfAvailable() == false {
                self.items = []
                self.logLibraryItems(
                    origin: "empty-no-current-snapshot",
                    sourceID: self.selectedSourceID,
                    context: self.selectedListContext
                )
            }
            #if DEBUG
            print(
                "[BrowseCraftLibrary] load source=\(self.selectedSourceID ?? "nil") " +
                "items=\(self.items.count) " +
                "context=\(self.contextDescription(self.selectedListContext))"
            )
            #endif

            await self.refreshSelectedListTab(validateTabsFirst: false)
            await self.prepareTabsForSelectedSourceIfNeeded()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    @MainActor
    func selectListTab(id tabID: String) async {
        guard self.isValidatingTabs == false else {
            return
        }

        guard self.visibleListTabs.contains(where: { tab in tab.id == tabID }) else {
            self.ensureSelectedListTab()
            return
        }

        if self.selectedListTabID != tabID {
            self.refreshToken += 1
            self.selectedListTabID = tabID
            self.selectedListTabErrorMessage = self.currentListTabErrorMessage()
            self.loadCachedItemsForSelectedTab()
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }

        await self.refreshSelectedListTab()
    }

    @MainActor
    func refreshSelectedListTab(validateTabsFirst: Bool = true) async {
        guard self.selectedSource != nil else {
            return
        }

        if validateTabsFirst {
            await self.prepareTabsForSelectedSourceIfNeeded()
        }
        CrashDiagnostics.shared.setRuleStage(.list)
        self.ensureSelectedListTab()
        guard let refreshedSelectedSource: Source = self.selectedSource else {
            return
        }

        let expectedSourceID: String = refreshedSelectedSource.id
        let expectedTabID: String? = self.selectedListTabID
        let expectedListContext: ListContext? = self.selectedListContext
        let expectedListStateKey: String = self.listStateKey(sourceID: expectedSourceID, context: expectedListContext)
        self.setListTabError(nil, sourceID: expectedSourceID, context: expectedListContext)
        self.refreshToken += 1
        let currentRefreshToken: Int = self.refreshToken
        let requestID: Int = currentRefreshToken
        var shouldRefreshReplacementTab: Bool = false
        self.isRefreshing = true
        #if DEBUG
        print(
            "[BrowseCraftLibraryRefresh] event=start " +
            "requestID=\(requestID) " +
            "source=\(expectedSourceID) " +
            "context=\(self.contextDescription(expectedListContext))"
        )
        #endif

        do {
            let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
                source: refreshedSelectedSource,
                listContext: expectedListContext
            )
            if Task.isCancelled == false,
               self.refreshToken == currentRefreshToken,
               self.isCurrentListState(sourceID: expectedSourceID, key: expectedListStateKey) {
                let refreshedItems: [ContentItem] = self.contentItems(
                    from: output,
                    source: refreshedSelectedSource,
                    context: expectedListContext
                )
                self.items = refreshedItems
                self.cacheListItems(
                    source: refreshedSelectedSource,
                    items: refreshedItems,
                    context: expectedListContext
                )
                self.setListTabError(nil, sourceID: expectedSourceID, context: expectedListContext)
                if self.updateConfirmedEmptyListTab(
                    sourceID: expectedSourceID,
                    tabID: expectedTabID,
                    itemCount: refreshedItems.count
                ) {
                    self.ensureSelectedListTab()
                    shouldRefreshReplacementTab = self.selectedListTabID != expectedTabID
                }
                self.sourceSelectionStore.publishLibrarySnapshot(
                    source: refreshedSelectedSource,
                    items: self.items,
                    listContext: expectedListContext
                )
                self.logLibraryItems(
                    origin: "runtime-refresh-result",
                    sourceID: expectedSourceID,
                    context: expectedListContext,
                    requestID: requestID
                )
                self.saveCurrentLibraryState(lastRefreshAt: self.now())
                #if DEBUG
                print(
                    "[BrowseCraftLibrary] reload after refresh source=\(expectedSourceID) " +
                    "requestID=\(requestID) " +
                    "items=\(self.items.count) " +
                    "context=\(self.contextDescription(expectedListContext))"
                )
                #endif
                self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
            } else {
                #if DEBUG
                print(
                    "[BrowseCraftLibraryRefresh] event=stale-result " +
                    "requestID=\(requestID) " +
                    "source=\(expectedSourceID) " +
                    "context=\(self.contextDescription(expectedListContext)) " +
                    "current=\(self.currentListStateKey() ?? "nil")"
                )
                #endif
            }
        } catch is CancellationError {
            // 中文注释：快速切换 source 时取消旧请求；取消结果不能显示为用户错误。
        } catch {
            if self.refreshToken == currentRefreshToken,
               self.isCurrentListState(sourceID: expectedSourceID, key: expectedListStateKey) {
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-refresh-error")
                AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "library-refresh-error")
                self.setListTabError(
                    RuleExecutionErrorClassifier.userMessage(for: error),
                    sourceID: expectedSourceID,
                    context: expectedListContext
                )
            }
        }

        if self.refreshToken == currentRefreshToken {
            self.isRefreshing = false
        }

        if shouldRefreshReplacementTab,
           self.refreshToken == currentRefreshToken,
           self.selectedSourceID == expectedSourceID {
            await self.refreshSelectedListTab()
        }
    }

    @MainActor
    /// 中文注释：toggleFavorite 方法封装当前类型的一段业务或界面行为。
    func toggleFavorite(item: ContentItem) {
        do {
            let wasFavorite: Bool = self.favoriteItemIDs.contains(item.id)
            let source: Source? = self.source(for: item.sourceId)
            let favoriteItem: FavoriteContentItem = FavoriteContentItem(
                id: item.id,
                sourceID: item.sourceId,
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                kind: self.favoriteKind(for: item),
                latestText: item.latestText,
                updatedAt: item.updatedAt,
                favoritedAt: self.now(),
                listOrder: item.listOrder,
                listContext: item.listContext,
                sourceSnapshot: source.map(FavoriteSourceSnapshot.init(source:))
            )
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.execute(item: favoriteItem)
            AppAnalytics.shared.logBookmarkChanged(isFavorite: wasFavorite == false, source: source)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "favorite-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    /// 中文注释：sourceName 方法封装当前类型的一段业务或界面行为。
    func sourceName(for sourceId: String) -> String {
        return self.source(for: sourceId)?.name ?? "Unknown Source"
    }

    /// 中文注释：source 方法封装当前类型的一段业务或界面行为。
    func source(for sourceId: String) -> Source? {
        return self.sources.first { source in
            return source.id == sourceId
        }
    }

    var selectedSource: Source? {
        return self.sources.first { source in
            return source.id == self.selectedSourceID
        }
    }

    var selectedSourceLoginState: LibrarySourceLoginState? {
        _ = self.credentialRevision
        return LibrarySourceLoginStateResolver(
            credentialStore: self.sourceCredentialStore,
            now: self.now
        ).resolve(source: self.selectedSource)
    }

    @MainActor
    func requestSelectedSourceLogin() {
        self.requestedSourceLogin = self.selectedSourceLoginState
    }

    @MainActor
    func dismissRequestedSourceLogin() {
        self.requestedSourceLogin = nil
    }

    @MainActor
    func completeRequestedSourceLogin(credential: SourceCredential) {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID else {
            return
        }

        self.sourceCredentialStore.save(credential)
        self.credentialRevision += 1
        self.requestedSourceLogin = nil
    }

    @MainActor
    func removeSelectedSourceCredential() {
        guard let sourceID: String = self.selectedSourceID else {
            return
        }

        self.sourceCredentialStore.removeCredential(sourceID: sourceID)
        self.credentialRevision += 1
        self.requestedSourceLogin = nil
    }

    var isShowingSourceLoading: Bool {
        return self.isRefreshing || self.preparingSource != nil
    }

    var loadingTitle: String {
        if self.preparingSource?.runtimeKind == .rss || self.selectedSource?.configuration.kind == .rss {
            return "Loading RSS"
        }

        if self.preparingSource != nil {
            return "Loading Source"
        }

        return "Loading Tab"
    }

    var loadingMessage: String {
        if let preparingSource: SourceLoadingState = self.preparingSource {
            return "Fetching the latest items from \(preparingSource.sourceName)."
        }

        return "Fetching the latest items for this tab."
    }

    var listTabStates: [LibraryListTabState] {
        let tabs: [ListTabRule] = self.visibleListTabs
        #if DEBUG
        self.logListTabs(
            origin: "listTabStates",
            source: self.selectedSource,
            tabs: tabs
        )
        #endif
        return tabs.map { tab in
            return LibraryListTabState(
                id: tab.id,
                title: tab.title,
                isSelected: self.selectedListTabID == tab.id
            )
        }
    }

    func imageRequestConfig(for source: Source) -> RequestConfig? {
        return self.resolveLibrarySourcePresentationUseCase.imageRequestConfig(
            for: source,
            listTab: self.selectedListTab
        )
    }

    func primaryActionTitle(for source: Source) -> String {
        if self.shouldOpenReaderDirectly(for: source) {
            return "Read"
        }

        return "Chapters"
    }

    func primaryActionSystemImage(for source: Source) -> String {
        if self.shouldOpenReaderDirectly(for: source) {
            return "book"
        }

        return "list.bullet"
    }

    func shouldOpenReaderDirectly(for source: Source) -> Bool {
        return self.resolveLibrarySourcePresentationUseCase.shouldOpenReaderDirectly(for: source)
    }

    private var listTabs: [ListTabRule] {
        return self.resolveLibrarySourcePresentationUseCase.listTabs(for: self.selectedSource)
    }

    private var visibleListTabs: [ListTabRule] {
        let tabs: [ListTabRule] = self.listTabs
        guard self.selectedSource?.configuration.kind == .video,
              let sourceID: String = self.selectedSourceID else {
            return tabs
        }

        let visibleTabs: [ListTabRule] = tabs.filter { tab in
            return self.confirmedEmptyListTabKeys.contains(self.listTabKey(sourceID: sourceID, tabID: tab.id)) == false
        }

        return visibleTabs.isEmpty ? tabs : visibleTabs
    }

    private var selectedListTab: ListTabRule? {
        guard let selectedListTabID: String = self.selectedListTabID else {
            return self.visibleListTabs.first
        }

        return self.visibleListTabs.first { tab in
            return tab.id == selectedListTabID
        } ?? self.visibleListTabs.first
    }

    private func ensureSelectedListTab() {
        let tabs: [ListTabRule] = self.visibleListTabs
        #if DEBUG
        self.logListTabs(
            origin: "ensureSelectedListTab",
            source: self.selectedSource,
            tabs: tabs
        )
        #endif

        if let selectedListTabID: String = self.selectedListTabID,
           tabs.contains(where: { tab in tab.id == selectedListTabID }) {
            return
        }

        self.selectedListTabID = tabs.first?.id
        self.selectedListTabErrorMessage = self.currentListTabErrorMessage()
    }

    private func updateConfirmedEmptyListTab(
        sourceID: String,
        tabID: String?,
        itemCount: Int
    ) -> Bool {
        guard let tabID: String else {
            return false
        }

        let key: String = self.listTabKey(sourceID: sourceID, tabID: tabID)
        let wasHidden: Bool = self.confirmedEmptyListTabKeys.contains(key)
        if itemCount == 0 {
            self.confirmedEmptyListTabKeys.insert(key)
        } else {
            self.confirmedEmptyListTabKeys.remove(key)
        }

        return wasHidden != self.confirmedEmptyListTabKeys.contains(key)
    }

    private func listTabKey(sourceID: String, tabID: String) -> String {
        return "\(sourceID)::\(tabID)"
    }

    private func listStateKey(sourceID: String, context: ListContext?) -> String {
        return [
            sourceID,
            context?.pageId ?? "nil",
            context?.tabId ?? "nil",
            context?.sectionId ?? "nil",
            context?.listRuleId ?? "nil"
        ].joined(separator: "::")
    }

    private func currentListStateKey() -> String? {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return nil
        }

        return self.listStateKey(sourceID: selectedSourceID, context: self.selectedListContext)
    }

    private func isCurrentListState(sourceID: String, key: String) -> Bool {
        return self.selectedSourceID == sourceID && self.currentListStateKey() == key
    }

    private func currentListTabErrorMessage() -> String? {
        guard let key: String = self.currentListStateKey() else {
            return nil
        }

        return self.listTabErrorMessages[key]
    }

    private func setListTabError(_ message: String?, sourceID: String, context: ListContext?) {
        let key: String = self.listStateKey(sourceID: sourceID, context: context)

        if let message: String {
            self.listTabErrorMessages[key] = message
        } else {
            self.listTabErrorMessages.removeValue(forKey: key)
        }

        if self.currentListStateKey() == key {
            self.selectedListTabErrorMessage = message
        }
    }

    private func isSelectedDefaultListTab() -> Bool {
        guard let selectedTabID: String = self.selectedListTab?.id,
              let firstTabID: String = self.visibleListTabs.first?.id else {
            return false
        }

        return selectedTabID == firstTabID
    }

    @MainActor
    private func prepareTabsForSelectedSourceIfNeeded() async {
        if self.validateSourceTabsUseCase == nil {
            await self.discoverTabsForSelectedVideoSourceIfNeeded()
            return
        }

        await self.validateTabsForSelectedSourceIfNeeded()
    }

    @MainActor
    private func validateTabsForSelectedSourceIfNeeded() async {
        guard let validateSourceTabsUseCase: ValidateSourceTabsUseCase,
              let source: Source = self.selectedSource,
              source.configuration.kind != .plugin,
              self.tabValidationAttemptedSourceIDs.contains(source.id) == false else {
            return
        }

        self.tabValidationAttemptedSourceIDs.insert(source.id)
        self.isValidatingTabs = true
        defer {
            self.isValidatingTabs = false
        }
        let expectedSourceID: String = source.id
        let result: SourceTabsValidationResult = await validateSourceTabsUseCase.execute(source: source)
        guard self.selectedSourceID == expectedSourceID else {
            return
        }

        self.upsertSource(result.validatedSource)
        self.logTabValidationResult(result)
        self.ensureSelectedListTab()
    }

    private func logTabValidationResult(_ result: SourceTabsValidationResult) {
        #if DEBUG
        for entry: SourceTabValidationEntry in result.entries {
            print(
                "[BrowseCraftTabValidation] source=\(result.sourceID) " +
                "kind=\(result.runtimeKind.rawValue) " +
                "tab=\(entry.tabID ?? "nil") " +
                "title=\(entry.title) " +
                "status=\(self.tabValidationStatusDescription(entry.status)) " +
                "items=\(entry.itemCount)"
            )
        }
        #endif
    }

    private func tabValidationStatusDescription(_ status: SourceTabValidationStatus) -> String {
        switch status {
        case .valid:
            return "valid"
        case .empty:
            return "empty"
        case .failed(let message):
            return "failed(\(message))"
        case .skipped(let reason):
            return "skipped(\(reason))"
        }
    }

    @MainActor
    private func discoverTabsForSelectedVideoSourceIfNeeded() async {
        guard let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase,
              let source: Source = self.selectedSource,
              case .video(let configuration) = source.configuration,
              configuration.listTabs.count <= 1,
              self.tabDiscoveryAttemptedSourceIDs.contains(source.id) == false else {
            return
        }

        self.tabDiscoveryAttemptedSourceIDs.insert(source.id)
        self.isValidatingTabs = true
        defer {
            self.isValidatingTabs = false
        }
        CrashDiagnostics.shared.setRuleStage(.list)

        do {
            let tabs: [VideoSourceListTab] = try await videoTabDiscoveryUseCase.discoverTabs(
                sourceID: source.id,
                definition: configuration.definition,
                explicitTabs: configuration.listTabs
            )
            guard tabs != configuration.listTabs else {
                return
            }

            var updatedSource: Source = source
            updatedSource.configuration = .video(
                VideoSourceConfiguration(
                    definition: configuration.definition,
                    listTabs: tabs
                )
            )
            self.upsertSource(updatedSource)
            self.ensureSelectedListTab()
            #if DEBUG
            print(
                "[BrowseCraftLibraryTabs] origin=webview-discovery " +
                "source=\(source.id) " +
                "count=\(tabs.count)"
            )
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(
                error: error,
                stage: .list,
                event: "library-tab-discovery-error"
            )
        }
    }

    #if DEBUG
    private func logListTabs(
        origin: String,
        source: Source?,
        tabs: [ListTabRule]
    ) {
        let tabDescription: String = tabs.map { tab in
            return [
                tab.id,
                tab.title,
                tab.list.url
            ].joined(separator: "|")
        }
        .joined(separator: ", ")

        print(
            "[BrowseCraftLibraryTabs] origin=\(origin) " +
            "source=\(source?.id ?? "nil") " +
            "kind=\(source?.configuration.kind.rawValue ?? "nil") " +
            "selected=\(self.selectedListTabID ?? "nil") " +
            "count=\(tabs.count) " +
            "tabs=[\(tabDescription)]"
        )
    }
    #endif


    private func contextDescription(_ context: ListContext?) -> String {
        guard let context: ListContext = context else {
            return "nil"
        }

        return [
            "page=\(context.pageId ?? "nil")",
            "tab=\(context.tabId ?? "nil")",
            "section=\(context.sectionId ?? "nil")",
            "rule=\(context.listRuleId ?? "nil")"
        ].joined(separator: ",")
    }

    private func bindSourceSelection() {
        self.sourceSelectionStore.$selectedSourceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedSourceID in
                self?.applySelectedSourceID(selectedSourceID)
            }
            .store(in: &self.cancellables)

        self.sourceSelectionStore.$preparingSource
            .receive(on: DispatchQueue.main)
            .assign(to: &self.$preparingSource)

        self.sourceSelectionStore.$preparedLibrarySnapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.applyPreparedLibrarySnapshot(snapshot)
            }
            .store(in: &self.cancellables)
    }

    private func applySelectedSourceID(_ selectedSourceID: String?) {
        if self.selectedSourceID == selectedSourceID {
            return
        }

        self.switchToSource(selectedSourceID)
    }

    private func switchToSource(_ selectedSourceID: String?) {
        // 中文注释：切换 source 时先清除旧 source 的画面状态，避免旧列表在新网站加载期间继续可见。
        self.refreshToken += 1
        self.isRefreshing = false
        self.isValidatingTabs = false
        self.selectedSourceID = selectedSourceID
        CrashDiagnostics.shared.setSource(selectedSourceID.flatMap { self.source(for: $0) })
        self.selectedListTabID = nil
        self.errorMessage = nil
        self.selectedListTabErrorMessage = nil
        self.requestedSourceLogin = nil
        self.items = []
        self.ensureSelectedListTab()
        self.selectedListTabErrorMessage = self.currentListTabErrorMessage()
        self.saveCurrentLibraryState(lastRefreshAt: nil)

        do {
            // 中文注释：优先展示 Sources 入口刚请求到的当前结果；没有当前快照时保持空态，不从持久化缓存补数据。
            if self.applyPreparedSnapshotIfAvailable() == false {
                self.items = []
                self.logLibraryItems(
                    origin: "empty-after-source-switch-no-snapshot",
                    sourceID: selectedSourceID,
                    context: self.selectedListContext
                )
            }
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "switch-source-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "switch-source-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func applyPreparedLibrarySnapshot(_ snapshot: SourceLibrarySnapshot?) {
        self.preparedLibrarySnapshot = snapshot

        if let snapshot: SourceLibrarySnapshot = snapshot {
            self.upsertSource(snapshot.source)
            if self.selectedSourceID == snapshot.sourceID {
                self.ensureSelectedListTab()
            }
        }

        guard self.applyPreparedSnapshotIfAvailable() else {
            return
        }

        do {
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "snapshot-favorite-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func applyPreparedSnapshotIfAvailable() -> Bool {
        guard let snapshot: SourceLibrarySnapshot = self.preparedLibrarySnapshot,
              snapshot.sourceID == self.selectedSourceID,
              self.snapshotMatchesSelectedListContext(snapshot) else {
            return false
        }

        self.upsertSource(snapshot.source)
        self.items = snapshot.items
        let cacheContext: ListContext? = snapshot.listContext ?? self.selectedListContext
        self.cacheListItems(
            source: snapshot.source,
            items: snapshot.items,
            context: cacheContext
        )
        self.setListTabError(nil, sourceID: snapshot.sourceID, context: self.selectedListContext)
        self.logLibraryItems(
            origin: "current-snapshot",
            sourceID: snapshot.sourceID,
            context: self.selectedListContext
        )
        return true
    }

    private func snapshotMatchesSelectedListContext(_ snapshot: SourceLibrarySnapshot) -> Bool {
        guard let selectedContext: ListContext = self.selectedListContext else {
            return snapshot.listContext == nil && snapshot.items.first?.listContext == nil
        }

        guard let snapshotContext: ListContext = snapshot.listContext ?? snapshot.items.first?.listContext else {
            return self.isSelectedDefaultListTab()
        }

        return snapshotContext == selectedContext
    }

    private func upsertSource(_ source: Source) {
        if let index: Array<Source>.Index = self.sources.firstIndex(where: { existingSource in
            return existingSource.id == source.id
        }) {
            self.sources[index] = source
            return
        }

        self.sources.insert(source, at: 0)
    }

    private func loadCachedItemsForSelectedTab() {
        if self.applyPreparedSnapshotIfAvailable() == false {
            if let key: String = self.currentListStateKey(),
               let cacheEntry: LibraryListCacheEntry = self.listCache[key] {
                self.items = cacheEntry.items
                self.setListTabError(nil, sourceID: cacheEntry.sourceID, context: cacheEntry.context)
                self.logLibraryItems(
                    origin: "tab-cache-hit",
                    sourceID: cacheEntry.sourceID,
                    context: cacheEntry.context
                )
                return
            }

            self.logLibraryItems(
                origin: "tab-switch-no-snapshot-retain-current",
                sourceID: self.selectedSourceID,
                context: self.selectedListContext
            )
        }
    }

    private func cacheListItems(source: Source, items: [ContentItem], context: ListContext?) {
        let key: String = self.listStateKey(sourceID: source.id, context: context)
        self.listCache[key] = LibraryListCacheEntry(
            sourceID: source.id,
            context: context,
            items: items
        )
    }

    private var selectedListContext: ListContext? {
        return self.resolveLibrarySourcePresentationUseCase.listContext(from: self.selectedListTab)
    }

    private func restoreStartupLibraryState() throws {
        let persistedState: UserLibraryState? = try self.loadUserLibraryStateUseCase.execute(userID: self.userID)
        let persistedSource: Source? = persistedState.flatMap { state in
            guard let selectedSourceID: String = state.selectedSourceID else {
                return nil
            }

            return self.source(for: selectedSourceID)
        }
        let resolvedSource: Source? = persistedSource ?? self.sources.first

        guard let source: Source = resolvedSource else {
            self.selectedSourceID = nil
            self.sourceSelectionStore.selectedSourceID = nil
            self.selectedListTabID = nil
            self.items = []
            return
        }

        self.selectedSourceID = source.id
        self.sourceSelectionStore.selectedSourceID = source.id
        CrashDiagnostics.shared.setSource(source)

        if persistedSource?.id == source.id {
            self.restoreSelectedListTab(from: persistedState?.listContext)
        } else {
            self.selectedListTabID = nil
            self.ensureSelectedListTab()
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }
    }

    private func restoreSelectedListTab(from context: ListContext?) {
        guard let context: ListContext = context else {
            self.selectedListTabID = nil
            self.ensureSelectedListTab()
            return
        }

        let tabs: [ListTabRule] = self.listTabs
        self.selectedListTabID = tabs.first { tab in
            let tabContext: ListContext? = self.resolveLibrarySourcePresentationUseCase.listContext(from: tab)
            return tabContext == context ||
                tab.id == context.tabId ||
                tab.list.id == context.listRuleId
        }?.id
        self.ensureSelectedListTab()

        if self.selectedListContext != context {
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }
    }

    private func saveCurrentLibraryState(lastRefreshAt: Date?) {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return
        }

        let state: UserLibraryState = UserLibraryState(
            userID: self.userID,
            selectedSourceID: selectedSourceID,
            listContext: self.selectedListContext,
            lastRefreshAt: lastRefreshAt,
            updatedAt: self.now()
        )

        do {
            try self.saveUserLibraryStateUseCase.execute(state: state)
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftUserLibraryState] save failed " +
                "sourceID=\(selectedSourceID) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func contentItems(
        from output: SourceListOutput,
        source: Source,
        context: ListContext?
    ) -> [ContentItem] {
        return output.items.enumerated().map { index, item in
            return ContentItem(
                id: item.id,
                sourceId: source.id,
                title: item.title,
                detailURL: item.detailURL?.absoluteString ?? item.id,
                coverURL: item.coverURL?.absoluteString,
                type: self.contentType(for: source),
                latestText: item.latestText,
                richContent: item.richContent,
                updatedAt: item.updatedAt,
                listOrder: index,
                listContext: context
            )
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

    private func logLibraryItems(
        origin: String,
        sourceID: String?,
        context: ListContext?,
        requestID: Int? = nil
    ) {
        #if DEBUG
        let requestDescription: String = requestID.map { " requestID=\($0)" } ?? ""
        print(
            "[BrowseCraftLibraryData] origin=\(origin) " +
            "source=\(sourceID ?? "nil") " +
            "\(requestDescription) " +
            "items=\(self.items.count) " +
            "firstItem=\(self.items.first?.id ?? "nil") " +
            "context=\(self.contextDescription(context))"
        )
        #endif
    }

    private func favoriteKind(for item: ContentItem) -> FavoriteContentKind {
        switch item.type {
        case .article:
            return .rss
        case .comic:
            return .comic
        case .video:
            return self.source(for: item.sourceId)?.favoriteVideoKind ?? .videoNative
        default:
            return .rss
        }
    }
}
