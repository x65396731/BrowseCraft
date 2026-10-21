import Observation
import Foundation
import UIKit
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog
import BrowseCraftRuntime

// 中文注释：ReaderViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：从历史页恢复 Reader 时携带最近阅读到的页码；具体图片仍由 Reader 按章节 URL 加载。
struct ReaderHistoryRestoreContext: Hashable {
    var lastPageIndex: Int?
    var lastPageImageURLString: String?
}

/// 中文注释：换话方向。底部上拉是下一话、顶部下拉是上一话（docs/design/Comic-Reader-Chapter-Swipe-Design.md）。
enum ReaderChapterNavigationDirection {
    case previous
    case next
}

/// 中文注释：某个方向能不能换话，决定拉动时的提示：能换带目标话名；目录里到头了是「已经是第一话 / 最后一话」；
/// 从历史进来既没目录、规则也没给前后链接，就是「这里不能切换」。
enum ReaderChapterSwitchAvailability: Equatable {
    case available(title: String?)
    case boundary
    case unavailable
}

struct ReaderSourceLoginPrompt: Identifiable, Hashable {
    let state: LibrarySourceLoginState

    var id: String {
        return state.id
    }
}

/// 中文注释：漫画阅读器的视图模型：加载章节页面、记录阅读历史与广告积分、处理受限章节的登录流。
@MainActor
@Observable
final class ReaderViewModel {
    private(set) var chapter: ReaderChapter?
    private(set) var isLoading: Bool = false
    private var currentPageIndex: Int?
    private var currentPageImageURL: URL?
    private(set) var pendingRestorePageIndex: Int?
    private(set) var shouldPlayAd: Bool = false
    /// 中文注释：最近一次换话的方向，只给 `chapter_opened` 埋点用；新的一话换上之后清掉。
    private(set) var pendingChapterNavigationDirection: ReaderChapterNavigationDirection?
    /// 中文注释：正在换话的方向；非空时 View 显示贴边等待浮层、两个换话手势不响应。
    private(set) var chapterSwitchDirection: ReaderChapterNavigationDirection?
    /// 中文注释：已经取到、还没换上的新一话。View 等滚动静止再调 `showLoadedChapter()`，
    /// 避免用户正在滑时手指下的页面突然换掉。
    private(set) var chapterAwaitingDisplay: ReaderChapter?
    @ObservationIgnored private var chapterSwitchTask: Task<Void, Never>?
    private(set) var sourceLoginPrompt: ReaderSourceLoginPrompt?
    private(set) var requestedSourceLogin: LibrarySourceLoginState?
    var errorMessage: String?

    let item: ContentItem
    private let source: Source
    private let selectedChapter: ChapterLink?
    private let navigationChapterURLs: [String]
    private let navigationChapterTitles: [String?]
    private let navigationOrder: ChapterNavigationOrder
    private let restoreContext: ReaderHistoryRestoreContext?
    private let loadReaderChapterUseCase: LoadReaderChapterUseCase
    private let protectedResourceLoader: ReaderProtectedResourceLoader?
    private let sourceCredentialProvider: any SourceCredentialProviding
    private let sourceCredentialStore: (any SourceCredentialStoring)?
    private let resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase
    /// 中文注释：规则声明的阅读页图片请求，按 source 在 init 算一次；此前是计算属性，每页 cell 渲染都跑一遍
    /// 整张规则校验（2026-10-20 审计 C-1）。
    private let readerRuleRequestConfig: RequestConfig?
    private let persistenceCoordinator: ReadingActivityPersistenceCoordinator
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let now: () -> Date
    private var savedChapterHistoryKeys: Set<String> = []
    /// 中文注释：同一阅读器实例里同一章只计一次积分（30.8）；退出再进是新实例、算新会话。
    private var adPointAwardedChapterKeys: Set<String> = []
    private var pendingAccessChapterURLString: String?
    private var pendingAccessShouldRestoreInitialPage: Bool = false
    /// 中文注释：埋点会话。`openEntry` 由 `ReaderView` 在首次加载前写入；`reader_opened` 只在第一次加载成功时报，
    /// 之后每次换章报 `chapter_opened`；离开时报 `reader_closed`（章节数为本次进入过的不同章节）。
    var openEntry: ReaderOpenEntry = .chapterList
    private var openedAt: Date?
    private var visitedChapterURLs: Set<String> = []
    private var didReportClose: Bool = false

    var diagnosticSource: Source {
        return self.source
    }

    init(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        restoreContext: ReaderHistoryRestoreContext? = nil,
        loadReaderChapterUseCase: LoadReaderChapterUseCase,
        protectedResourceLoader: ReaderProtectedResourceLoader? = nil,
        sourceCredentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        sourceCredentialStore: (any SourceCredentialStoring)? = nil,
        resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase,
        persistenceCoordinator: ReadingActivityPersistenceCoordinator,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.selectedChapter = selectedChapter
        self.navigationChapterURLs = selectedChapter?.navigationChapterURLs ?? []
        self.navigationChapterTitles = selectedChapter?.navigationChapterTitles ?? []
        self.navigationOrder = selectedChapter?.navigationOrder ?? .descending
        self.restoreContext = restoreContext
        self.loadReaderChapterUseCase = loadReaderChapterUseCase
        self.protectedResourceLoader = protectedResourceLoader
        self.sourceCredentialProvider = sourceCredentialProvider
        self.sourceCredentialStore = sourceCredentialStore
        self.resolveReaderSourcePresentationUseCase = resolveReaderSourcePresentationUseCase
        self.readerRuleRequestConfig = resolveReaderSourcePresentationUseCase.readerRuleRequestConfig(for: source)
        self.persistenceCoordinator = persistenceCoordinator
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
        self.now = now
        self.currentPageIndex = restoreContext?.lastPageIndex
        self.currentPageImageURL = restoreContext?.lastPageImageURLString.flatMap(URL.init(string:))
        self.pendingRestorePageIndex = restoreContext?.lastPageIndex

        #if DEBUG
        AppLog.debug(.app, "navigation-init-reader-view-model", [
            "itemId": .text("\(item.id)"),
            "title": .text("\(item.title)"),
            "detailURL": .text("\(item.detailURL)"),
            "selectedChapterURL": .text("\(selectedChapter?.url ?? "nil")")
        ])
        #endif
    }

    @MainActor
    /// 中文注释：加载当前章节；已有章节内容时直接复用，不重取。
    func load() async {
        if self.chapter != nil {
            #if DEBUG
            AppLog.debug(.app, "navigation-reader-load-skipped-chapter-exists", [
                "itemId": .text("\(self.item.id)"),
                "chapterURL": .text("\(self.chapter?.chapterURL ?? "nil")")
            ])
            #endif
            return
        }

        #if DEBUG
        AppLog.debug(.app, "navigation-load-reader", [
            "itemId": .text("\(self.item.id)"),
            "title": .text("\(self.item.title)"),
            "detailURL": .text("\(self.item.detailURL)"),
            "selectedChapterURL": .text("\(self.selectedChapter?.url ?? "nil")")
        ])
        #endif

        self.isLoading = true
        self.errorMessage = nil

        await self.loadChapter(
            chapterURLString: self.selectedChapter?.url,
            shouldRestoreInitialPage: true
        )
    }

    /// 中文注释：开始换话：先存当前这一话的进度，再在后台取新的一话；取到后挂起等 View 换上。
    /// 换话进行中、首次加载中或这个方向没有地址时什么都不做。
    @MainActor
    func startChapterSwitch(_ direction: ReaderChapterNavigationDirection) {
        guard self.chapterSwitchDirection == nil,
              self.isLoading == false,
              let chapterURL: String = self.neighborChapterURL(direction) else {
            return
        }

        self.saveCurrentChapterProgress(reason: direction == .next ? "before-next-chapter" : "before-previous-chapter")
        self.pendingChapterNavigationDirection = direction
        self.chapterSwitchDirection = direction
        self.chapterSwitchTask = Task { [weak self] in
            await self?.loadChapter(
                chapterURLString: chapterURL,
                shouldRestoreInitialPage: false,
                holdsUntilShown: true
            )
        }
    }

    /// 中文注释：View 在滚动静止时调用，把挂起的新一话换上；当前页码与续读页码一并清掉，新的一话从第一页算起。
    @MainActor
    func showLoadedChapter() {
        guard let loadedChapter: ReaderChapter = self.chapterAwaitingDisplay else {
            return
        }

        // 中文注释：等待期间用户可能还在当前这一话里滑动，换走之前再存一次停在哪一页。
        self.saveCurrentChapterProgress(reason: "before-chapter-shown")
        self.chapterAwaitingDisplay = nil
        self.chapterSwitchDirection = nil
        self.chapterSwitchTask = nil
        self.currentPageIndex = nil
        self.currentPageImageURL = nil
        self.pendingRestorePageIndex = nil
        self.display(loadedChapter)
    }

    /// 中文注释：离开阅读器时取消正在进行的换话，离开后不会再跳到新的一话。
    @MainActor
    func cancelChapterSwitch() {
        guard self.chapterSwitchDirection != nil else {
            return
        }

        self.chapterSwitchTask?.cancel()
        self.chapterSwitchTask = nil
        self.chapterSwitchDirection = nil
        self.chapterAwaitingDisplay = nil
        self.pendingChapterNavigationDirection = nil
        self.isLoading = false
        AppLog.info(.reader, "comic-chapter-switch-cancelled", ["source": .id(self.source.id), "item": .id(self.item.id)])
    }

    /// 中文注释：本话加载失败或没有页面时，顶部下拉重试本话；没有当前话时按进入时的那一话重取。
    @MainActor
    func retryCurrentChapter() async {
        guard self.chapterSwitchDirection == nil,
              self.isLoading == false else {
            return
        }

        let chapterURLString: String? = self.nonEmptyURLString(self.chapter?.chapterURL) ?? self.selectedChapter?.url
        await self.loadChapter(
            chapterURLString: chapterURLString,
            shouldRestoreInitialPage: self.chapter == nil
        )
    }

    /// 中文注释：某个方向能不能换话。前后地址来自章节页自己给的链接，没有再用详情页目录推出来的。
    func chapterSwitchAvailability(_ direction: ReaderChapterNavigationDirection) -> ReaderChapterSwitchAvailability {
        guard let chapter: ReaderChapter = self.chapter else {
            return .unavailable
        }

        if let chapterURL: String = self.neighborChapterURL(direction) {
            return .available(title: self.navigationTitle(for: chapterURL))
        }

        // 中文注释：带着目录进来，或者规则给了另一个方向的链接，说明只是到头了。
        let oppositeURL: String? = direction == .next ? chapter.previousChapterURL : chapter.nextChapterURL
        if self.navigationChapterURLs.isEmpty == false || self.nonEmptyURLString(oppositeURL) != nil {
            return .boundary
        }

        return .unavailable
    }

    private func neighborChapterURL(_ direction: ReaderChapterNavigationDirection) -> String? {
        switch direction {
        case .previous:
            return self.nonEmptyURLString(self.chapter?.previousChapterURL)
        case .next:
            return self.nonEmptyURLString(self.chapter?.nextChapterURL)
        }
    }

    @MainActor
    func updateVisiblePage(index: Int, imageURLString: String) {
        guard index >= 0,
              self.currentPageIndex != index else {
            return
        }

        self.currentPageIndex = index
        self.currentPageImageURL = URL(string: imageURLString)

        #if DEBUG
        AppLog.debug(.reader, "comic-history-visible-page", [
            "sourceID": .text("\(self.source.id)"),
            "comicItemID": .text("\(self.item.id)"),
            "pageIndex": .text("\(index)")
        ])
        #endif
    }

    func saveCurrentChapterProgress(reason: String) {
        guard let chapter: ReaderChapter = self.chapter else {
            return
        }

        self.saveComicChapterHistory(
            chapter: chapter,
            chapterKey: self.chapterKey(for: chapter),
            reason: reason,
            shouldSkipIfSaved: false,
            shouldAccumulateAdPoints: false
        )
    }

    @MainActor
    func markRestorePageApplied() {
        self.pendingRestorePageIndex = nil
    }

    /// 中文注释：广告播过（看完 / 提前关闭）才清零积分；没播出来积分保留、下个计分点再试（30.8）。
    @MainActor
    func markAdPlaybackHandled(outcome: RewardedAdPlaybackOutcome) {
        #if DEBUG
        AppLog.debug(.ad, "ad-playback-comic-mark-handled", [
            "sourceID": .text("\(self.source.id)"),
            "comicItemID": .text("\(self.item.id)"),
            "previousShouldPlayAd": .text("\(self.shouldPlayAd)"),
            "consumesAdPoints": .text("\(outcome.consumesAdPoints)")
        ])
        #endif
        self.shouldPlayAd = false
        guard outcome.consumesAdPoints else {
            return
        }
        Task { [persistenceCoordinator] in
            do {
                try await persistenceCoordinator.consumeAdPoints()
            } catch {
                AppLog.error(.sync, "comic-ad-points-consume-failed", ["error": .error(error)])
            }
        }
    }

    @MainActor
    func requestSourceLogin(state: LibrarySourceLoginState) {
        self.sourceLoginPrompt = nil
        self.requestedSourceLogin = state
    }

    @MainActor
    func hideSourceLoginPrompt() {
        self.sourceLoginPrompt = nil
    }

    @MainActor
    func dismissSourceLoginPrompt() {
        self.sourceLoginPrompt = nil
        self.clearPendingAccessRetry()
    }

    @MainActor
    func dismissRequestedSourceLogin() {
        self.requestedSourceLogin = nil
        self.clearPendingAccessRetry()
    }

    @MainActor
    func completeRequestedSourceLogin(credential: SourceCredential) async {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID,
              let sourceCredentialStore: any SourceCredentialStoring = self.sourceCredentialStore else {
            return
        }

        sourceCredentialStore.save(credential)
        self.requestedSourceLogin = nil

        let chapterURLString: String? = self.pendingAccessChapterURLString
        let shouldRestoreInitialPage: Bool = self.pendingAccessShouldRestoreInitialPage
        self.clearPendingAccessRetry()
        await self.loadChapter(
            chapterURLString: chapterURLString,
            shouldRestoreInitialPage: shouldRestoreInitialPage
        )
    }

    @MainActor
    /// 中文注释：`holdsUntilShown` 为真时是换话：取到的新一话先挂在 `chapterAwaitingDisplay`，当前这一话的
    /// 页码与进度都不动，等 View 调 `showLoadedChapter()` 才换上、记历史与埋点。
    private func loadChapter(
        chapterURLString: String?,
        shouldRestoreInitialPage: Bool,
        holdsUntilShown: Bool = false
    ) async {
        CrashDiagnostics.shared.setRuleStage(.reader)
        self.isLoading = true
        self.errorMessage = nil
        if holdsUntilShown == false {
            if shouldRestoreInitialPage {
                self.currentPageIndex = self.restoreContext?.lastPageIndex
                self.currentPageImageURL = self.restoreContext?.lastPageImageURLString.flatMap(URL.init(string:))
            } else {
                self.currentPageIndex = nil
                self.currentPageImageURL = nil
                self.pendingRestorePageIndex = nil
            }
        }

        do {
            let loadedChapter: ReaderChapter = try await self.loadReaderChapterUseCase.execute(
                source: self.source,
                item: self.item,
                chapterURLString: chapterURLString
            )
            // 中文注释：离开阅读器取消了换话，取到的结果直接丢掉；首次加载与重试不受影响。
            guard holdsUntilShown == false || Task.isCancelled == false else {
                return
            }
            let displayChapter: ReaderChapter = self.chapterByPreparingPageResources(for: loadedChapter)
            let navigableChapter: ReaderChapter = self.chapterByResolvingNavigation(for: displayChapter)
            if holdsUntilShown {
                self.chapterAwaitingDisplay = navigableChapter
            } else {
                self.display(navigableChapter)
            }

            #if DEBUG
            AppLog.debug(.app, "navigation-loaded-reader", [
                "itemId": .text("\(self.item.id)"),
                "chapterURL": .text("\(loadedChapter.chapterURL)"),
                "pageCount": .text("\(navigableChapter.pageResources.count)")
            ])
            #endif
        } catch {
            // 中文注释：离开阅读器取消的换话不算失败，不报诊断也不弹提示。
            guard holdsUntilShown == false || Task.isCancelled == false else {
                return
            }
            // 中文注释：换话失败留在原话：收起等待浮层，下面照常弹分类器的短句。
            if holdsUntilShown {
                self.chapterSwitchDirection = nil
                self.chapterSwitchTask = nil
            }
            // 中文注释：阅读器状态记 info（Logging-Design.md 第 8 节）：这一话没取到，首次加载 / 重试 / 换话都算。
            AppLog.info(.reader, "comic-chapter-load-failed", [
                "source": .id(self.source.id),
                "item": .id(self.item.id),
                "chapter": .path(chapterURLString),
                "switching": .bool(holdsUntilShown),
                "error": .error(error)
            ])
            let classifiedError: RuleExecutionError = RuleExecutionErrorClassifier.classified(error)
            RuleExecutionErrorClassifier.log(error: classifiedError, stage: .reader, event: "reader-load-error")
            switch classifiedError {
            case .accessRequired:
                // 中文注释：账号访问限制是预期业务状态，不报诊断事件、也不记 Crashlytics 非致命错误。
                break
            default:
                RuleFailureDiagnostics.report(
                    error: error,
                    kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error),
                    stage: .reader,
                    point: .comicReader,
                    source: self.source
                )
            }
            self.handleReaderLoadError(
                classifiedError,
                chapterURLString: chapterURLString,
                shouldRestoreInitialPage: shouldRestoreInitialPage
            )
            let classifiedMessage: String = RuleExecutionErrorClassifier.userMessage(for: classifiedError)

            #if DEBUG
            AppLog.debug(.app, "navigation-reader-error", [
                "itemId": .text("\(self.item.id)"),
                "detailURL": .text("\(self.item.detailURL)"),
                "selectedChapterURL": .text("\(self.selectedChapter?.url ?? "nil")"),
                "error": .text("\(classifiedMessage)")
            ])
            #endif
        }

        self.isLoading = false
    }

    /// 中文注释：把一话换上屏幕：记历史（含按话积分）与 `reader_opened` / `chapter_opened` 埋点。
    @MainActor
    private func display(_ chapter: ReaderChapter) {
        let previousChapterURL: String? = self.chapter?.chapterURL
        self.chapter = chapter
        self.saveComicChapterHistoryIfNeeded(chapter: chapter)
        self.reportChapterLoaded(chapter, previousChapterURL: previousChapterURL)
        self.pendingChapterNavigationDirection = nil
    }

    @MainActor
    private func reportChapterLoaded(_ chapter: ReaderChapter, previousChapterURL: String?) {
        self.visitedChapterURLs.insert(chapter.chapterURL)
        guard self.openedAt != nil else {
            self.openedAt = self.now()
            // 中文注释：阅读器状态记 info（Logging-Design.md 第 8 节）：打开、换话、关闭；翻页不记。
            AppLog.info(.reader, "comic-reader-opened", [
                "source": .id(self.source.id),
                "item": .id(self.item.id),
                "chapter": .path(chapter.chapterURL),
                "pages": .int(chapter.pageResources.count),
                "entry": .enumValue(self.openEntry)
            ])
            AppAnalytics.shared.logReaderOpened(source: self.source, kind: .comic, entry: self.openEntry)
            return
        }
        // 中文注释：登录后重载同一章不算换章。
        guard chapter.chapterURL != previousChapterURL else {
            return
        }
        let navigation: ChapterNavigation = self.pendingChapterNavigationDirection == .previous ? .previous : .next
        AppLog.info(.reader, "comic-chapter-changed", [
            "source": .id(self.source.id),
            "item": .id(self.item.id),
            "chapter": .path(chapter.chapterURL),
            "pages": .int(chapter.pageResources.count),
            "navigation": .enumValue(navigation)
        ])
        AppAnalytics.shared.logChapterOpened(source: self.source, kind: .comic, navigation: navigation)
    }

    /// 中文注释：离开阅读器时报一次 `reader_closed`；弹登录页或激励广告盖住阅读器时视图也会消失，那不算离开。
    @MainActor
    func reportReaderClosedIfNeeded() {
        guard self.didReportClose == false,
              self.requestedSourceLogin == nil,
              self.shouldPlayAd == false,
              let openedAt: Date = self.openedAt else {
            return
        }
        self.didReportClose = true
        AppLog.info(.reader, "comic-reader-closed", [
            "source": .id(self.source.id),
            "item": .id(self.item.id),
            "ms": .duration(self.now().timeIntervalSince(openedAt)),
            "chapters": .int(self.visitedChapterURLs.count)
        ])
        AppAnalytics.shared.logReaderClosed(
            kind: .comic,
            duration: self.now().timeIntervalSince(openedAt),
            chapterCount: self.visitedChapterURLs.count
        )
    }

    @MainActor
    private func handleReaderLoadError(
        _ error: RuleExecutionError,
        chapterURLString: String?,
        shouldRestoreInitialPage: Bool
    ) {
        guard case .accessRequired = error else {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return
        }

        guard let sourceCredentialStore: any SourceCredentialStoring = self.sourceCredentialStore,
              let loginState: LibrarySourceLoginState = LibrarySourceLoginStateResolver(
                credentialStore: sourceCredentialStore,
                now: self.now
              ).resolve(source: self.source) else {
            self.errorMessage = NSLocalizedString("comic_detail_access_no_login_page", comment: "")
            return
        }

        guard loginState.status == .guest else {
            self.errorMessage = NSLocalizedString("comic_detail_access_denied", comment: "")
            return
        }

        self.pendingAccessChapterURLString = chapterURLString
        self.pendingAccessShouldRestoreInitialPage = shouldRestoreInitialPage
        self.sourceLoginPrompt = ReaderSourceLoginPrompt(state: loginState)
    }

    private func clearPendingAccessRetry() {
        self.pendingAccessChapterURLString = nil
        self.pendingAccessShouldRestoreInitialPage = false
    }

    /// 中文注释：阅读页图片加载使用 GalleryRule 的图片请求配置，避免 UI 直接理解规则选择细节。
    var readerImageRequestConfig: RequestConfig? {
        return self.resolveReaderSourcePresentationUseCase.imageRequestConfig(
            for: self.source,
            ruleRequestConfig: self.readerRuleRequestConfig
        )
    }

    func loadProtectedImage(
        reference: ProtectedReaderImageReference,
        targetPixelWidth: CGFloat
    ) async throws -> UIImage {
        guard let protectedResourceLoader: ReaderProtectedResourceLoader = self.protectedResourceLoader else {
            throw RuleExecutionError.protectedResource(
                stage: .image,
                sourceID: reference.sourceID,
                reason: "Protected resource loader is not configured"
            )
        }

        let data: Data = try await protectedResourceLoader.load(
            reference,
            context: SourceRequestContext(
                sourceID: reference.sourceID,
                baseURL: reference.baseURL ?? URL(string: self.source.baseURL),
                purpose: .image,
                refererURL: (self.chapter?.chapterURL).flatMap { chapterURL in
                    URL(string: chapterURL)
                },
                contextValues: ComicRuleAPITemplateResolver.ruleContextValues(
                    source: self.source,
                    credentialProvider: self.sourceCredentialProvider
                )
            )
        )

        guard let image: UIImage = DownsampledImageDecoder.decode(
            data: data,
            targetPixelWidth: targetPixelWidth
        ) else {
            throw RuleExecutionError.protectedResource(
                stage: .image,
                sourceID: reference.sourceID,
                reason: "Decrypted protected resource is not a valid image"
            )
        }

        return image
    }

    private func chapterByPreparingPageResources(for chapter: ReaderChapter) -> ReaderChapter {
        guard chapter.pageResources.isEmpty else {
            return chapter
        }

        var preparedChapter: ReaderChapter = chapter
        preparedChapter.pageResources = chapter.pageImageURLs.map(ReaderPageResource.remoteImageURL)
        return preparedChapter
    }

    private func saveComicChapterHistoryIfNeeded(chapter: ReaderChapter) {
        let chapterKey: String = self.chapterKey(for: chapter)
        self.saveComicChapterHistory(
            chapter: chapter,
            chapterKey: chapterKey,
            reason: "initial-chapter-load",
            shouldSkipIfSaved: false,
            shouldAccumulateAdPoints: self.adPointAwardedChapterKeys.insert(chapterKey).inserted
        )
    }

    private func saveComicChapterHistory(
        chapter: ReaderChapter,
        chapterKey: String,
        reason: String,
        shouldSkipIfSaved: Bool,
        shouldAccumulateAdPoints: Bool
    ) {
        if shouldSkipIfSaved,
           self.savedChapterHistoryKeys.contains(chapterKey) {
            return
        }

        self.savedChapterHistoryKeys.insert(chapterKey)

        let history: ComicChapterHistoryTransfer = ComicChapterHistoryTransfer(
            value: self.comicChapterHistory(chapter: chapter, chapterKey: chapterKey)
        )
        Task { [persistenceCoordinator] in
            do {
                let result: AdPointAccumulationResult? = try await persistenceCoordinator.saveComicHistory(
                    history,
                    adPoints: shouldAccumulateAdPoints ? AdPointRule.comicPoints : nil
                )
                if result?.shouldPlayAd == true {
                    AppAnalytics.shared.logAdPointsThreshold(trigger: .comic)
                    self.shouldPlayAd = true
                }
                AppLog.debug(.sync, "comic-history-saved", ["reason": .code(reason), "chapterKey": .code(chapterKey)])
            } catch {
                AppLog.error(.sync, "comic-history-save-failed", ["error": .error(error)])
            }
        }
    }

    private func comicChapterHistory(
        chapter: ReaderChapter,
        chapterKey: String
    ) -> ComicChapterHistory {
        return ComicChapterHistory(
            userID: self.currentUserID,
            sourceID: self.source.id,
            comicItemID: self.item.id,
            comicTitle: chapter.comicTitle ?? self.item.title,
            chapterID: nil,
            chapterKey: chapterKey,
            chapterURL: URL(string: chapter.chapterURL),
            chapterTitle: self.chapterTitle(for: chapter),
            visitedAt: self.now(),
            coverURL: self.item.coverURL.flatMap(URL.init(string:)),
            lastReaderPageURL: URL(string: chapter.chapterURL),
            lastPageImageURL: self.currentPageImageURL ?? chapter.pageImageURLs.first.flatMap(URL.init(string:)),
            lastPageImageCacheKey: nil,
            lastPageIndex: self.currentPageIndex ?? (chapter.pageImageURLs.isEmpty ? nil : 0),
            // 中文注释：这一章一共几页——pipeline 站走 pageResources，普通站走 pageImageURLs；没解析出页面时不写。
            pageCount: Self.pageCount(of: chapter),
            previousChapterURL: chapter.previousChapterURL.flatMap(URL.init(string:)),
            nextChapterURL: chapter.nextChapterURL.flatMap(URL.init(string:)),
            previousChapterTitle: self.navigationTitle(for: chapter.previousChapterURL),
            nextChapterTitle: self.navigationTitle(for: chapter.nextChapterURL),
            sourceSnapshot: SourceSnapshot(source: self.source)
        )
    }

    private static func pageCount(of chapter: ReaderChapter) -> Int? {
        let count: Int = max(chapter.pageResources.count, chapter.pageImageURLs.count)
        return count > 0 ? count : nil
    }

    private func navigationTitle(for chapterURL: String?) -> String? {
        guard let chapterURL: String = self.nonEmptyURLString(chapterURL),
              let chapterIndex: Int = self.navigationIndex(for: chapterURL),
              self.navigationChapterTitles.indices.contains(chapterIndex) else {
            return nil
        }

        return self.nonEmptyURLString(self.navigationChapterTitles[chapterIndex])
    }

    private func chapterKey(for chapter: ReaderChapter) -> String {
        if chapter.chapterURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return chapter.chapterURL
        }

        if let selectedChapterURL: String = self.selectedChapter?.url,
           selectedChapterURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return selectedChapterURL
        }

        return self.chapterTitle(for: chapter)
    }

    private func chapterTitle(for chapter: ReaderChapter) -> String {
        if let chapterTitle: String = chapter.chapterTitle,
           chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return chapterTitle
        }

        if let selectedChapterTitle: String = self.selectedChapter?.title,
           selectedChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return selectedChapterTitle
        }

        return self.item.latestText ?? self.item.title
    }

    private func nonEmptyURLString(_ urlString: String?) -> String? {
        guard let urlString: String = urlString,
              urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return urlString
    }

    /// 中文注释：优先保留 reader 页面自身解析出的导航；imageAPI 等无导航结果再使用详情页章节顺序补齐。
    private func chapterByResolvingNavigation(for chapter: ReaderChapter) -> ReaderChapter {
        guard let currentIndex: Int = self.navigationIndex(for: chapter.chapterURL) else {
            return chapter
        }

        var resolvedChapter: ReaderChapter = chapter
        if self.nonEmptyURLString(resolvedChapter.chapterTitle) == nil,
           self.navigationChapterTitles.indices.contains(currentIndex),
           let navigationTitle: String = self.nonEmptyURLString(self.navigationChapterTitles[currentIndex]) {
            resolvedChapter.chapterTitle = navigationTitle
        }
        let previousIndex: Int
        let nextIndex: Int
        switch self.navigationOrder {
        case .ascending:
            previousIndex = currentIndex - 1
            nextIndex = currentIndex + 1
        case .descending:
            previousIndex = currentIndex + 1
            nextIndex = currentIndex - 1
        }

        if self.nonEmptyURLString(resolvedChapter.previousChapterURL) == nil,
           self.navigationChapterURLs.indices.contains(previousIndex) {
            resolvedChapter.previousChapterURL = self.navigationChapterURLs[previousIndex]
        }
        if self.nonEmptyURLString(resolvedChapter.nextChapterURL) == nil,
           self.navigationChapterURLs.indices.contains(nextIndex) {
            resolvedChapter.nextChapterURL = self.navigationChapterURLs[nextIndex]
        }
        return resolvedChapter
    }

    private func navigationIndex(for chapterURL: String) -> Int? {
        if let exactIndex: Int = self.navigationChapterURLs.firstIndex(of: chapterURL) {
            return exactIndex
        }

        let normalizedChapterURL: String = self.normalizedNavigationURL(chapterURL)
        return self.navigationChapterURLs.firstIndex { candidateURL in
            return self.normalizedNavigationURL(candidateURL) == normalizedChapterURL
        }
    }

    private func normalizedNavigationURL(_ urlString: String) -> String {
        var normalizedURL: String = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedURL.count > 1 && normalizedURL.hasSuffix("/") {
            normalizedURL.removeLast()
        }
        return normalizedURL
    }

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }
}
