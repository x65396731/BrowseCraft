import Foundation

struct ChapterDetailContent: Hashable {
    var chapters: [ChapterLink]
    var description: String?
}

// 中文注释：Reader Feature 仍通过 App use case 入口调用；rule-only 执行实现已收进 RuleSourceRuntime 边界。
struct LoadChaptersUseCase {
    private let ruleSourceLoader: RuleSourceChapterLoader

    init(
        pageContentLoader: PageContentLoader,
        ruleSourceParser: RuleSourceParsingService
    ) {
        self.ruleSourceLoader = RuleSourceChapterLoader(
            pageContentLoader: pageContentLoader,
            ruleSourceParser: ruleSourceParser
        )
    }

    init(
        httpClient: HTTPClient,
        ruleSourceParser: RuleSourceParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleSourceParser: ruleSourceParser
        )
    }

    func execute(source: Source, item: ContentItem) async throws -> ChapterDetailContent {
        return try await self.ruleSourceLoader.execute(source: source, item: item)
    }
}

// 中文注释：Reader Feature 仍通过 App use case 入口调用；rule-only 执行实现已收进 RuleSourceRuntime 边界。
struct LoadReaderChapterUseCase {
    private let ruleSourceLoader: RuleSourceReaderLoader

    init(
        pageContentLoader: PageContentLoader,
        ruleSourceParser: RuleSourceParsingService
    ) {
        self.ruleSourceLoader = RuleSourceReaderLoader(
            pageContentLoader: pageContentLoader,
            ruleSourceParser: ruleSourceParser
        )
    }

    init(
        httpClient: HTTPClient,
        ruleSourceParser: RuleSourceParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleSourceParser: ruleSourceParser
        )
    }

    func execute(
        source: Source,
        item: ContentItem,
        chapterURLString: String? = nil
    ) async throws -> ReaderChapter {
        return try await self.ruleSourceLoader.execute(
            source: source,
            item: item,
            chapterURLString: chapterURLString
        )
    }
}
