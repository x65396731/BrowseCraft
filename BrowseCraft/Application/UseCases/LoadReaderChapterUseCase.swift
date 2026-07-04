import Foundation

// 中文注释：Reader Feature 仍通过 App use case 入口调用；rule-only 执行实现已收进 RuleSourceRuntime 边界。
struct LoadChaptersUseCase {
    private let ruleSourceUseCase: RuleSourceLoadChaptersUseCase

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService
    ) {
        self.ruleSourceUseCase = RuleSourceLoadChaptersUseCase(
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

    func execute(source: Source, item: ContentItem) async throws -> [ChapterLink] {
        return try await self.ruleSourceUseCase.execute(source: source, item: item)
    }
}

// 中文注释：Reader Feature 仍通过 App use case 入口调用；rule-only 执行实现已收进 RuleSourceRuntime 边界。
struct LoadReaderChapterUseCase {
    private let ruleSourceUseCase: RuleSourceLoadReaderChapterUseCase

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService
    ) {
        self.ruleSourceUseCase = RuleSourceLoadReaderChapterUseCase(
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
        return try await self.ruleSourceUseCase.execute(
            source: source,
            item: item,
            chapterURLString: chapterURLString
        )
    }
}
