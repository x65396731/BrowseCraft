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
        ruleParser: RuleParsingService
    ) {
        self.ruleSourceLoader = RuleSourceChapterLoader(
            pageContentLoader: pageContentLoader,
            ruleParser: ruleParser
        )
    }

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser
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
        ruleParser: RuleParsingService
    ) {
        self.ruleSourceLoader = RuleSourceReaderLoader(
            pageContentLoader: pageContentLoader,
            ruleParser: ruleParser
        )
    }

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser
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
