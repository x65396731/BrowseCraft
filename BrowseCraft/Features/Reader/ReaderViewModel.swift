import Combine
import Foundation

// 中文注释：ReaderViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ReaderViewModel 是 final class，负责本模块中的对应职责。
final class ReaderViewModel: ObservableObject {
    @Published private(set) var chapter: ReaderChapter?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    let item: ContentItem
    private let source: Source
    private let selectedChapter: ChapterLink?
    private let loadReaderChapterUseCase: LoadReaderChapterUseCase

    init(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        loadReaderChapterUseCase: LoadReaderChapterUseCase
    ) {
        self.item = item
        self.source = source
        self.selectedChapter = selectedChapter
        self.loadReaderChapterUseCase = loadReaderChapterUseCase

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

        do {
            let loadedChapter: ReaderChapter = try await self.loadReaderChapterUseCase.execute(
                source: self.source,
                item: self.item,
                chapterURLString: self.selectedChapter?.url
            )
            self.chapter = loadedChapter

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
        return RuleResolver().resolve(self.source.rule).primaryGalleryRequest
    }
}

/// 中文注释：ChapterListViewModel 是 final class，负责本模块中的对应职责。
final class ChapterListViewModel: ObservableObject {
    @Published private(set) var chapters: [ChapterLink] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    let item: ContentItem
    let source: Source
    private let loadChaptersUseCase: LoadChaptersUseCase

    init(
        item: ContentItem,
        source: Source,
        loadChaptersUseCase: LoadChaptersUseCase
    ) {
        self.item = item
        self.source = source
        self.loadChaptersUseCase = loadChaptersUseCase

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

        do {
            let loadedChapters: [ChapterLink] = try await self.loadChaptersUseCase.execute(
                source: self.source,
                item: self.item
            )
            // 中文注释：章节解析器已经按源站分组顺序返回结果；这里不再按标题全局排序，避免单话/单行本/番外篇混排。
            self.chapters = loadedChapters

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

}
