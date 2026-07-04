import Foundation
import BrowseCraftCore

struct SourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let urlResolver: URLResolvingService
    private let contentRepository: ContentRepository

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        contentRepository: ContentRepository
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.urlResolver = urlResolver
        self.contentRepository = contentRepository
    }

    func makeRuntimeResolver() -> SourceRuntimeResolver {
        return SourceRuntimeResolver { source in
            return self.makeRuleSourceRuntime(source: source)
        }
    }

    func makeRuleSourceRuntime(source: Source) -> RuleSourceRuntime {
        return RuleSourceRuntime(
            source: source,
            refreshSourceUseCase: self.makeRefreshSourceUseCase(),
            searchSourceUseCase: self.makeSearchSourceUseCase(),
            loadChaptersUseCase: self.makeLoadChaptersUseCase(),
            loadReaderChapterUseCase: self.makeLoadReaderChapterUseCase()
        )
    }

    private func makeRefreshSourceUseCase() -> RuleSourceRefreshUseCase {
        return RuleSourceRefreshUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            contentRepository: self.contentRepository
        )
    }

    private func makeSearchSourceUseCase() -> SearchSourceUseCase {
        return SearchSourceUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeLoadChaptersUseCase() -> RuleSourceLoadChaptersUseCase {
        return RuleSourceLoadChaptersUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
    }

    private func makeLoadReaderChapterUseCase() -> RuleSourceLoadReaderChapterUseCase {
        return RuleSourceLoadReaderChapterUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
    }
}
