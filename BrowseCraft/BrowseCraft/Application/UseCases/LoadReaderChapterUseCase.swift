import Foundation

// 中文注释：LoadReaderChapterUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：LoadReaderChapterError 是 enum，负责本模块中的对应职责。
enum LoadReaderChapterError: LocalizedError {
    case noChapterFound(detailURLString: String)
    case noPageImagesFound(chapterURLString: String)

    var errorDescription: String? {
        switch self {
        case .noChapterFound(let detailURLString):
            return "No chapter link was found on detail page: \(detailURLString)"
        case .noPageImagesFound(let chapterURLString):
            return "No page image was found on chapter page: \(chapterURLString)"
        }
    }
}

/// 中文注释：LoadChaptersError 是 enum，负责本模块中的对应职责。
enum LoadChaptersError: LocalizedError {
    case noChaptersFound(detailURLString: String)

    var errorDescription: String? {
        switch self {
        case .noChaptersFound(let detailURLString):
            return "No chapter link was found on detail page: \(detailURLString)"
        }
    }
}

/// 中文注释：加载单个 Library 条目的章节目录。
struct LoadChaptersUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
    }

    /// 中文注释：兼容旧测试和旧装配入口；普通 HTTP 客户端继续可直接作为页面内容加载器使用。
    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser
        )
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, item: ContentItem) async throws -> [ChapterLink] {
        #if DEBUG
        print(
            "[BrowseCraftRequest] LoadChapters execute " +
            "sourceId=\(source.id) " +
            "itemId=\(item.id) " +
            "title=\(item.title) " +
            "detailURL=\(item.detailURL) " +
            "latestText=\(item.latestText ?? "nil")"
        )
        #endif

        if shouldTreatDetailURLAsChapter(source: source, item: item) {
            return [
                ChapterLink(
                    title: item.latestText ?? item.title,
                    url: item.detailURL
                )
            ]
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw URLResolvingError.invalidURL(item.detailURL)
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: source.rule.primaryDetailRequest
        )
        let chapters: [ChapterLink] = try self.ruleParser.parseDetailChapters(
            html: detailHTML,
            source: source,
            pageURL: item.detailURL
        )

        #if DEBUG
        print(
            "[BrowseCraftRequest] LoadChapters parsed " +
            "itemId=\(item.id) " +
            "detailURL=\(item.detailURL) " +
            "count=\(chapters.count) " +
            "firstURL=\(chapters.first?.url ?? "nil")"
        )
        #endif

        if chapters.isEmpty {
            throw LoadChaptersError.noChaptersFound(detailURLString: item.detailURL)
        }

        return chapters
    }
}

/// 中文注释：加载一个阅读章节页面，并解析出所有分页图片地址。
/// 中文注释：网络请求留在应用层，具体 HTML 解析通过 RuleParsingService 隔离。
struct LoadReaderChapterUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
    }

    /// 中文注释：兼容旧测试和旧装配入口；后续新增 WebView 测试可改用 pageContentLoader 注入。
    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser
        )
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(
        source: Source,
        item: ContentItem,
        chapterURLString: String? = nil
    ) async throws -> ReaderChapter {
        #if DEBUG
        print(
            "[BrowseCraftRequest] LoadReader execute " +
            "sourceId=\(source.id) " +
            "itemId=\(item.id) " +
            "title=\(item.title) " +
            "detailURL=\(item.detailURL) " +
            "preferredChapterURL=\(chapterURLString ?? "nil")"
        )
        #endif

        let chapterURLString: String = try await self.resolveChapterURLString(
            source: source,
            item: item,
            preferredChapterURLString: chapterURLString
        )

        #if DEBUG
        print(
            "[BrowseCraftRequest] LoadReader resolved chapter " +
            "itemId=\(item.id) " +
            "chapterURL=\(chapterURLString)"
        )
        #endif

        guard let chapterURL: URL = URL(string: chapterURLString) else {
            throw URLResolvingError.invalidURL(chapterURLString)
        }

        let html: String = try await self.pageContentLoader.getString(
            from: chapterURL,
            request: source.rule.primaryGalleryRequest
        )

        let chapter: ReaderChapter = try self.ruleParser.parseReader(
            html: html,
            source: source,
            pageURL: chapterURLString
        )

        #if DEBUG
        print(
            "[BrowseCraftRequest] LoadReader parsed " +
            "itemId=\(item.id) " +
            "chapterURL=\(chapter.chapterURL) " +
            "pageCount=\(chapter.pageImageURLs.count)"
        )
        #endif

        if chapter.pageImageURLs.isEmpty {
            throw LoadReaderChapterError.noPageImagesFound(chapterURLString: chapterURLString)
        }

        return chapter
    }

    /// 中文注释：resolveChapterURLString 方法封装当前类型的一段业务或界面行为。
    private func resolveChapterURLString(
        source: Source,
        item: ContentItem,
        preferredChapterURLString: String?
    ) async throws -> String {
        if let preferredChapterURLString: String = preferredChapterURLString {
            #if DEBUG
            print(
                "[BrowseCraftRequest] ResolveChapter use preferred " +
                "itemId=\(item.id) preferredChapterURL=\(preferredChapterURLString)"
            )
            #endif
            return preferredChapterURLString
        }

        if shouldTreatDetailURLAsChapter(source: source, item: item) {
            #if DEBUG
            print(
                "[BrowseCraftRequest] ResolveChapter use item detail as chapter " +
                "itemId=\(item.id) detailURL=\(item.detailURL)"
            )
            #endif
            return item.detailURL
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw URLResolvingError.invalidURL(item.detailURL)
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: source.rule.primaryDetailRequest
        )
        let chapters: [ChapterLink] = try self.ruleParser.parseDetailChapters(
            html: detailHTML,
            source: source,
            pageURL: item.detailURL
        )

        #if DEBUG
        print(
            "[BrowseCraftRequest] ResolveChapter parsed candidates " +
            "itemId=\(item.id) " +
            "detailURL=\(item.detailURL) " +
            "latestText=\(item.latestText ?? "nil") " +
            "count=\(chapters.count) " +
            "firstURL=\(chapters.first?.url ?? "nil")"
        )
        #endif

        if let latestText: String = item.latestText,
           let matchedChapter: ChapterLink = self.chapter(
            matchingLatestText: latestText,
            chapters: chapters
           ) {
            #if DEBUG
            print(
                "[BrowseCraftRequest] ResolveChapter matched latest " +
                "itemId=\(item.id) latestText=\(latestText) matchedURL=\(matchedChapter.url)"
            )
            #endif
            return matchedChapter.url
        }

        if let firstChapter: ChapterLink = chapters.first {
            #if DEBUG
            print(
                "[BrowseCraftRequest] ResolveChapter fallback first " +
                "itemId=\(item.id) firstURL=\(firstChapter.url)"
            )
            #endif
            return firstChapter.url
        }

        throw LoadReaderChapterError.noChapterFound(detailURLString: item.detailURL)
    }

    /// 中文注释：chapter 方法封装当前类型的一段业务或界面行为。
    private func chapter(matchingLatestText latestText: String, chapters: [ChapterLink]) -> ChapterLink? {
        let normalizedLatestText: String = self.normalizedText(latestText)

        return chapters.first { chapter in
            let normalizedChapterTitle: String = self.normalizedText(chapter.title)

            return normalizedChapterTitle.contains(normalizedLatestText)
                || normalizedLatestText.contains(normalizedChapterTitle)
        }
    }

    /// 中文注释：normalizedText 方法封装当前类型的一段业务或界面行为。
    private func normalizedText(_ text: String) -> String {
        var normalizedText: String = text
            .replacingOccurrences(of: "話", with: "话")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while normalizedText.contains("第0") {
            normalizedText = normalizedText.replacingOccurrences(of: "第0", with: "第")
        }

        return normalizedText
    }

}

private func shouldTreatDetailURLAsChapter(source: Source, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return source.rule.primaryDetailRule?.treatDetailURLAsChapter == true
}
