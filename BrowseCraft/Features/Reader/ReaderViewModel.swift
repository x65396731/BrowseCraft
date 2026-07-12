import Combine
import Foundation

// 中文注释：ReaderViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：从历史页恢复 Reader 时携带最近阅读到的页码；具体图片仍由 Reader 按章节 URL 加载。
struct ReaderHistoryRestoreContext: Hashable {
    var lastPageIndex: Int?
    var lastPageImageURLString: String?
}

/// 中文注释：章节切换方向只用于阅读器滚动策略；下一章回顶部，上一章保留当前默认行为。
enum ReaderChapterNavigationDirection {
    case previous
    case next
}

/// 中文注释：ReaderViewModel 是 final class，负责本模块中的对应职责。
final class ReaderViewModel: ObservableObject {
    @Published private(set) var chapter: ReaderChapter?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentPageIndex: Int?
    @Published private(set) var currentPageImageURL: URL?
    @Published private(set) var pendingRestorePageIndex: Int?
    @Published private(set) var shouldPlayAd: Bool = false
    /// 中文注释：记录最近一次章节切换方向，让 View 在新章节加载完成后决定是否需要调整滚动位置。
    @Published private(set) var pendingChapterNavigationDirection: ReaderChapterNavigationDirection?
    @Published var errorMessage: String?

    let item: ContentItem
    private let source: Source
    private let selectedChapter: ChapterLink?
    private let restoreContext: ReaderHistoryRestoreContext?
    private let loadReaderChapterUseCase: LoadReaderChapterUseCase
    private let resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase
    private let saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase?
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase?
    private let now: () -> Date
    private var savedChapterHistoryKeys: Set<String> = []

    var diagnosticSource: Source {
        return self.source
    }

    init(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        restoreContext: ReaderHistoryRestoreContext? = nil,
        loadReaderChapterUseCase: LoadReaderChapterUseCase,
        resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase,
        saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase? = nil,
        accumulateAdPointsUseCase: AccumulateAdPointsUseCase? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.selectedChapter = selectedChapter
        self.restoreContext = restoreContext
        self.loadReaderChapterUseCase = loadReaderChapterUseCase
        self.resolveReaderSourcePresentationUseCase = resolveReaderSourcePresentationUseCase
        self.saveComicChapterHistoryUseCase = saveComicChapterHistoryUseCase
        self.accumulateAdPointsUseCase = accumulateAdPointsUseCase
        self.now = now
        self.currentPageIndex = restoreContext?.lastPageIndex
        self.currentPageImageURL = restoreContext?.lastPageImageURLString.flatMap(URL.init(string:))
        self.pendingRestorePageIndex = restoreContext?.lastPageIndex

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Init ReaderViewModel " +
            "itemId=\(item.id) " +
            "title=\(item.title) " +
            "detailURL=\(item.detailURL) " +
            "selectedChapterURL=\(selectedChapter?.url ?? "nil")"
        )
        #endif
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        if self.chapter != nil {
            #if DEBUG
            print(
                "[BrowseCraftNavigation] Skip ReaderViewModel load because chapter already exists " +
                "itemId=\(self.item.id) chapterURL=\(self.chapter?.chapterURL ?? "nil")"
            )
            #endif
            return
        }

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Load reader " +
            "itemId=\(self.item.id) " +
            "title=\(self.item.title) " +
            "detailURL=\(self.item.detailURL) " +
            "selectedChapterURL=\(self.selectedChapter?.url ?? "nil")"
        )
        #endif

        self.isLoading = true
        self.errorMessage = nil

        await self.loadChapter(
            chapterURLString: self.selectedChapter?.url,
            shouldRestoreInitialPage: true
        )
    }

    @MainActor
    func loadPreviousChapter() async {
        guard let previousChapterURL: String = self.nonEmptyURLString(self.chapter?.previousChapterURL) else {
            return
        }

        self.saveCurrentChapterProgress(reason: "before-previous-chapter")
        self.pendingChapterNavigationDirection = .previous
        await self.loadChapter(
            chapterURLString: previousChapterURL,
            shouldRestoreInitialPage: false
        )
    }

    @MainActor
    func loadNextChapter() async {
        guard let nextChapterURL: String = self.nonEmptyURLString(self.chapter?.nextChapterURL) else {
            return
        }

        self.saveCurrentChapterProgress(reason: "before-next-chapter")
        self.pendingChapterNavigationDirection = .next
        await self.loadChapter(
            chapterURLString: nextChapterURL,
            shouldRestoreInitialPage: false
        )
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
        print(
            "[BrowseCraftComicHistory] visible page " +
            "sourceID=\(self.source.id) " +
            "comicItemID=\(self.item.id) " +
            "pageIndex=\(index)"
        )
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

    @MainActor
    func markChapterNavigationScrollHandled() {
        self.pendingChapterNavigationDirection = nil
    }

    @MainActor
    func markAdPlaybackHandled() {
        #if DEBUG
        print(
            "[BrowseCraftAdPlayback] comic mark handled " +
            "sourceID=\(self.source.id) comicItemID=\(self.item.id) previousShouldPlayAd=\(self.shouldPlayAd)"
        )
        #endif
        self.shouldPlayAd = false
    }

    @MainActor
    private func loadChapter(
        chapterURLString: String?,
        shouldRestoreInitialPage: Bool
    ) async {
        CrashDiagnostics.shared.setRuleStage(.reader)
        self.isLoading = true
        self.errorMessage = nil
        if shouldRestoreInitialPage {
            self.currentPageIndex = self.restoreContext?.lastPageIndex
            self.currentPageImageURL = self.restoreContext?.lastPageImageURLString.flatMap(URL.init(string:))
        } else {
            self.currentPageIndex = nil
            self.currentPageImageURL = nil
            self.pendingRestorePageIndex = nil
        }

        do {
            let loadedChapter: ReaderChapter = try await self.loadReaderChapterUseCase.execute(
                source: self.source,
                item: self.item,
                chapterURLString: chapterURLString
            )
            self.chapter = loadedChapter
            self.saveComicChapterHistoryIfNeeded(chapter: loadedChapter)
            AppAnalytics.shared.logReaderOpened(source: self.source)
            AppAnalytics.shared.logChapterOpened(source: self.source)

            #if DEBUG
            print(
                "[BrowseCraftNavigation] Loaded reader " +
                "itemId=\(self.item.id) " +
                "chapterURL=\(loadedChapter.chapterURL) " +
                "pageCount=\(loadedChapter.pageImageURLs.count)"
            )
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .reader, event: "reader-load-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .reader, errorCode: "reader-load-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "reader-load-error",
                event: "reader-load-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            let classifiedMessage: String = RuleExecutionErrorClassifier.userMessage(for: error)

            #if DEBUG
            print(
                "[BrowseCraftNavigation] Reader error " +
                "itemId=\(self.item.id) " +
                "detailURL=\(self.item.detailURL) " +
                "selectedChapterURL=\(self.selectedChapter?.url ?? "nil") " +
                "error=\(classifiedMessage)"
            )
            #endif
        }

        self.isLoading = false
    }

    /// 中文注释：阅读页图片加载使用 GalleryRule 的图片请求配置，避免 UI 直接理解规则选择细节。
    var readerImageRequestConfig: RequestConfig? {
        return self.resolveReaderSourcePresentationUseCase.readerImageRequestConfig(for: self.source)
    }

    private func saveComicChapterHistoryIfNeeded(chapter: ReaderChapter) {
        self.saveComicChapterHistory(
            chapter: chapter,
            chapterKey: self.chapterKey(for: chapter),
            reason: "initial-chapter-load",
            shouldSkipIfSaved: false,
            shouldAccumulateAdPoints: true
        )
    }

    private func saveComicChapterHistory(
        chapter: ReaderChapter,
        chapterKey: String,
        reason: String,
        shouldSkipIfSaved: Bool,
        shouldAccumulateAdPoints: Bool
    ) {
        guard let saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase = self.saveComicChapterHistoryUseCase else {
            return
        }

        if shouldSkipIfSaved,
           self.savedChapterHistoryKeys.contains(chapterKey) {
            return
        }

        self.savedChapterHistoryKeys.insert(chapterKey)

        do {
            try saveComicChapterHistoryUseCase.execute(
                history: self.comicChapterHistory(chapter: chapter, chapterKey: chapterKey)
            )
            if shouldAccumulateAdPoints {
                self.accumulateAdPoints(points: AdPointRule.comicPoints, chapterKey: chapterKey)
            }
            #if DEBUG
            print(
                "[BrowseCraftComicHistory] saved " +
                "reason=\(reason) " +
                "userID=\(AppUser.localDefaultID) " +
                "sourceID=\(self.source.id) " +
                "comicItemID=\(self.item.id) " +
                "chapterKey=\(chapterKey)"
            )
            #endif
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftComicHistory] save failed " +
                "reason=\(reason) " +
                "sourceID=\(self.source.id) " +
                "comicItemID=\(self.item.id) " +
                "chapterKey=\(chapterKey) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func accumulateAdPoints(points: Int, chapterKey: String) {
        guard let accumulateAdPointsUseCase: AccumulateAdPointsUseCase = self.accumulateAdPointsUseCase else {
            return
        }

        do {
            let result: AdPointAccumulationResult = try accumulateAdPointsUseCase.execute(points: points)
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] comic result " +
                "sourceID=\(self.source.id) comicItemID=\(self.item.id) " +
                "chapterKey=\(chapterKey) \(result.debugDescription)"
            )
            #endif
            if result.shouldPlayAd {
                #if DEBUG
                print(
                    "[BrowseCraftAdPlayback] comic shouldPlayAd=true " +
                    "sourceID=\(self.source.id) comicItemID=\(self.item.id) chapterKey=\(chapterKey)"
                )
                #endif
                self.shouldPlayAd = true
            }
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] comic accumulate failed " +
                "sourceID=\(self.source.id) " +
                "comicItemID=\(self.item.id) " +
                "chapterKey=\(chapterKey) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func comicChapterHistory(
        chapter: ReaderChapter,
        chapterKey: String
    ) -> ComicChapterHistory {
        return ComicChapterHistory(
            userID: AppUser.localDefaultID,
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
            previousChapterURL: chapter.previousChapterURL.flatMap(URL.init(string:)),
            nextChapterURL: chapter.nextChapterURL.flatMap(URL.init(string:)),
            sourceSnapshot: SourceSnapshot(source: self.source)
        )
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
}

/// 中文注释：ChapterListViewModel 是 final class，负责本模块中的对应职责。
final class ChapterListViewModel: ObservableObject {
    @Published private(set) var chapters: [ChapterLink] = []
    @Published private(set) var detailDescription: String?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    let item: ContentItem
    let source: Source
    private let loadChaptersUseCase: LoadChaptersUseCase
    private let resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase

    init(
        item: ContentItem,
        source: Source,
        loadChaptersUseCase: LoadChaptersUseCase,
        resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase
    ) {
        self.item = item
        self.source = source
        self.loadChaptersUseCase = loadChaptersUseCase
        self.resolveReaderSourcePresentationUseCase = resolveReaderSourcePresentationUseCase

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Init ChapterListViewModel " +
            "itemId=\(item.id) " +
            "title=\(item.title) " +
            "detailURL=\(item.detailURL) " +
            "sourceId=\(source.id)"
        )
        #endif
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        CrashDiagnostics.shared.setRuleStage(.chapter)
        if self.chapters.isEmpty == false {
            #if DEBUG
            print(
                "[BrowseCraftNavigation] Skip ChapterListViewModel load because chapters already exist " +
                "itemId=\(self.item.id) firstChapterURL=\(self.chapters.first?.url ?? "nil")"
            )
            #endif
            return
        }

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Load chapters " +
            "itemId=\(self.item.id) " +
            "title=\(self.item.title) " +
            "detailURL=\(self.item.detailURL)"
        )
        #endif

        self.isLoading = true
        self.errorMessage = nil
        self.detailDescription = nil

        do {
            let detailContent: ChapterDetailContent = try await self.loadChaptersUseCase.execute(
                source: self.source,
                item: self.item
            )
            // 中文注释：章节解析器已经按源站分组顺序返回结果；这里不再按标题全局排序，避免单话/单行本/番外篇混排。
            self.chapters = detailContent.chapters
            self.detailDescription = detailContent.description

            #if DEBUG
            print(
                "[BrowseCraftNavigation] Loaded chapters " +
                "itemId=\(self.item.id) " +
                "title=\(self.item.title) " +
                "detailURL=\(self.item.detailURL) " +
                "count=\(self.chapters.count) " +
                "firstURL=\(self.chapters.first?.url ?? "nil")"
            )

            for (index, chapter) in self.chapters.enumerated() {
                print(
                    "[BrowseCraftNavigation] Chapter item " +
                    "itemId=\(self.item.id) " +
                    "itemTitle=\(self.item.title) " +
                    "index=\(index) " +
                    "chapterTitle=\(chapter.title) " +
                    "chapterURL=\(chapter.url)"
                )
            }
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "chapters-load-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .detail, errorCode: "chapter-load-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "chapter-load-error",
                event: "chapter-load-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            let classifiedMessage: String = RuleExecutionErrorClassifier.userMessage(for: error)

            #if DEBUG
            print(
                "[BrowseCraftNavigation] Chapters error " +
                "itemId=\(self.item.id) " +
                "detailURL=\(self.item.detailURL) " +
                "error=\(classifiedMessage)"
            )
            #endif
        }

        self.isLoading = false
    }

    /// 中文注释：章节列表封面使用 DetailRule 的页面请求配置，避免 View 直接解析规则图。
    var detailCoverRequestConfig: RequestConfig? {
        return self.resolveReaderSourcePresentationUseCase.detailCoverRequestConfig(for: self.source)
    }

}
