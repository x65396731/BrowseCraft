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
    private let httpClient: HTTPClient
    private let ruleParser: RuleParsingService

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService
    ) {
        self.httpClient = httpClient
        self.ruleParser = ruleParser
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, item: ContentItem) async throws -> [ChapterLink] {
        if item.detailURL.contains("/chapters/") {
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

        let detailHTML: String = try await self.httpClient.getString(from: detailURL)
        let chapters: [ChapterLink] = try self.ruleParser.parseDetailChapters(
            html: detailHTML,
            source: source,
            pageURL: item.detailURL
        )

        if chapters.isEmpty {
            throw LoadChaptersError.noChaptersFound(detailURLString: item.detailURL)
        }

        return chapters
    }
}

/// 中文注释：加载一个阅读章节页面，并解析出所有分页图片地址。
/// 中文注释：网络请求留在应用层，具体 HTML 解析通过 RuleParsingService 隔离。
struct LoadReaderChapterUseCase {
    private let httpClient: HTTPClient
    private let ruleParser: RuleParsingService

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService
    ) {
        self.httpClient = httpClient
        self.ruleParser = ruleParser
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(
        source: Source,
        item: ContentItem,
        chapterURLString: String? = nil
    ) async throws -> ReaderChapter {
        let chapterURLString: String = try await self.resolveChapterURLString(
            source: source,
            item: item,
            preferredChapterURLString: chapterURLString
        )

        guard let chapterURL: URL = URL(string: chapterURLString) else {
            throw URLResolvingError.invalidURL(chapterURLString)
        }

        let html: String = try await self.httpClient.getString(from: chapterURL)

        let chapter: ReaderChapter = try self.ruleParser.parseReader(
            html: html,
            source: source,
            pageURL: chapterURLString
        )

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
            return preferredChapterURLString
        }

        if item.detailURL.contains("/chapters/") {
            return item.detailURL
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw URLResolvingError.invalidURL(item.detailURL)
        }

        let detailHTML: String = try await self.httpClient.getString(from: detailURL)
        let chapters: [ChapterLink] = try self.ruleParser.parseDetailChapters(
            html: detailHTML,
            source: source,
            pageURL: item.detailURL
        )

        if let latestText: String = item.latestText,
           let matchedChapter: ChapterLink = self.chapter(
            matchingLatestText: latestText,
            chapters: chapters
           ) {
            return matchedChapter.url
        }

        if let firstChapter: ChapterLink = chapters.first {
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
