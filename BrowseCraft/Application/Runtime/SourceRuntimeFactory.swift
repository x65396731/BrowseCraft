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
            return self.makeRuleSourceRuntimeAdapter(source: source)
        }
    }

    func makeRuleSourceRuntimeAdapter(source: Source) -> RuleSourceRuntimeAdapter {
        return RuleSourceRuntimeAdapter(
            source: source,
            refreshSourceUseCase: self.makeRefreshSourceUseCase(),
            searchSourceUseCase: self.makeSearchSourceUseCase(),
            loadChaptersUseCase: self.makeLoadChaptersUseCase(),
            loadReaderChapterUseCase: self.makeLoadReaderChapterUseCase()
        )
    }

    private func makeRefreshSourceUseCase() -> RefreshSourceUseCase {
        return RefreshSourceUseCase(
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

    private func makeLoadChaptersUseCase() -> LoadChaptersUseCase {
        return LoadChaptersUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
    }

    private func makeLoadReaderChapterUseCase() -> LoadReaderChapterUseCase {
        return LoadReaderChapterUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
    }
}
