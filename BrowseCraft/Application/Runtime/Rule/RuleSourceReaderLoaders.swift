import Foundation

// 中文注释：RuleSourceReaderLoaders 是 RuleSourceRuntime 内部执行边界，只处理 SiteRule-backed source。

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
struct RuleSourceChapterLoader {
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
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)

        RuleExecutionLogger.log(
            stage: .detail,
            event: "request",
            fields: [
                "source": source.id,
                "item": item.id,
                "tab": item.listContext?.tabId ?? "nil",
                "section": item.listContext?.sectionId ?? "nil",
                "listRule": item.listContext?.listRuleId ?? "nil",
                "detailURL": item.detailURL,
                "latestText": item.latestText ?? "nil"
            ]
        )

        if shouldTreatDetailURLAsChapter(resolvedRule: resolvedRule, item: item) {
            RuleExecutionLogger.log(
                stage: .detail,
                event: "direct-chapter",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL
                ]
            )

            return [
                ChapterLink(
                    title: item.latestText ?? item.title,
                    url: item.detailURL
                )
            ]
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail URL: \(item.detailURL)"
            )
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: resolvedRule.primaryDetailRequest
        )
        let chapters: [ChapterLink]
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            chapters = try self.ruleParser.parseDetailChapters(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
        } else {
            chapters = []
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "detailURL": item.detailURL,
                "count": chapters.count,
                "firstURL": chapters.first?.url ?? "nil"
            ]
        )

        if chapters.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .detail,
                sourceID: source.id,
                url: item.detailURL,
                ruleID: resolvedRule.detailEntry?.ruleID
            )
        }

        return chapters
    }
}

/// 中文注释：加载一个阅读章节页面，并解析出所有分页图片地址。
/// 中文注释：网络请求留在应用层，具体 HTML 解析通过 RuleParsingService 隔离。
struct RuleSourceReaderLoader {
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
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)

        RuleExecutionLogger.log(
            stage: .reader,
            event: "request",
            fields: [
                "source": source.id,
                "item": item.id,
                "tab": item.listContext?.tabId ?? "nil",
                "section": item.listContext?.sectionId ?? "nil",
                "listRule": item.listContext?.listRuleId ?? "nil",
                "detailURL": item.detailURL,
                "preferredChapterURL": chapterURLString ?? "nil"
            ]
        )

        let chapterURLString: String = try await self.resolveChapterURLString(
            source: source,
            resolvedRule: resolvedRule,
            item: item,
            preferredChapterURLString: chapterURLString
        )

        RuleExecutionLogger.log(
            stage: .reader,
            event: "resolved-chapter",
            fields: [
                "source": source.id,
                "item": item.id,
                "chapterURL": chapterURLString
            ]
        )

        guard let chapterURL: URL = URL(string: chapterURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .reader,
                sourceID: source.id,
                reason: "Invalid chapter URL: \(chapterURLString)"
            )
        }

        let html: String = try await self.pageContentLoader.getString(
            from: chapterURL,
            request: resolvedRule.primaryGalleryRequest
        )

        let chapter: ReaderChapter
        if let galleryRule: GalleryRule = resolvedRule.primaryGalleryRule {
            chapter = try self.ruleParser.parseReader(
                html: html,
                source: source,
                galleryRule: galleryRule,
                pageURL: chapterURLString,
                context: item.listContext
            )
        } else {
            chapter = emptyReaderChapter(source: source, pageURL: chapterURLString)
        }

        RuleExecutionLogger.log(
            stage: .reader,
            event: "parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "chapterURL": chapter.chapterURL,
                "pageCount": chapter.pageImageURLs.count,
                "firstImage": chapter.pageImageURLs.first ?? "nil"
            ]
        )

        if chapter.pageImageURLs.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .reader,
                sourceID: source.id,
                url: chapterURLString,
                ruleID: resolvedRule.galleryEntry?.ruleID
            )
        }

        return chapter
    }

    /// 中文注释：resolveChapterURLString 方法封装当前类型的一段业务或界面行为。
    private func resolveChapterURLString(
        source: Source,
        resolvedRule: ResolvedSiteRule,
        item: ContentItem,
        preferredChapterURLString: String?
    ) async throws -> String {
        if let preferredChapterURLString: String = preferredChapterURLString {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-preferred",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "preferredChapterURL": preferredChapterURLString
                ]
            )
            return preferredChapterURLString
        }

        if shouldTreatDetailURLAsChapter(resolvedRule: resolvedRule, item: item) {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-direct-chapter",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL
                ]
            )
            return item.detailURL
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail URL: \(item.detailURL)"
            )
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: resolvedRule.primaryDetailRequest
        )
        let chapters: [ChapterLink]
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            chapters = try self.ruleParser.parseDetailChapters(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
        } else {
            chapters = []
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "resolve-candidates",
            fields: [
                "source": source.id,
                "item": item.id,
                "detailURL": item.detailURL,
                "latestText": item.latestText ?? "nil",
                "count": chapters.count,
                "firstURL": chapters.first?.url ?? "nil"
            ]
        )

        if let latestText: String = item.latestText,
           let matchedChapter: ChapterLink = self.chapter(
            matchingLatestText: latestText,
            chapters: chapters
           ) {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-latest",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "latestText": latestText,
                    "matchedURL": matchedChapter.url
                ]
            )
            return matchedChapter.url
        }

        if let firstChapter: ChapterLink = chapters.first {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-first",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "firstURL": firstChapter.url
                ]
            )
            return firstChapter.url
        }

        throw RuleExecutionError.selectorEmpty(
            stage: .detail,
            sourceID: source.id,
            url: item.detailURL,
            ruleID: resolvedRule.detailEntry?.ruleID
        )
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

private func shouldTreatDetailURLAsChapter(resolvedRule: ResolvedSiteRule, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.treatsDetailURLAsChapter
}

private func emptyReaderChapter(source: Source, pageURL: String) -> ReaderChapter {
    return ReaderChapter(
        sourceId: source.id,
        comicTitle: nil,
        chapterTitle: nil,
        chapterURL: pageURL,
        catalogURL: nil,
        previousChapterURL: nil,
        nextChapterURL: nil,
        pageImageURLs: []
    )
}
