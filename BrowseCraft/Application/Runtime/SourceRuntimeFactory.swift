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
            listLoader: self.makeRuleSourceListLoader(),
            searchLoader: self.makeRuleSourceSearchLoader(),
            chapterLoader: self.makeRuleSourceChapterLoader(),
            readerLoader: self.makeRuleSourceReaderLoader()
        )
    }

    private func makeRuleSourceListLoader() -> RuleSourceListLoader {
        return RuleSourceListLoader(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            contentRepository: self.contentRepository
        )
    }

    private func makeRuleSourceSearchLoader() -> RuleSourceSearchLoader {
        return RuleSourceSearchLoader(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeRuleSourceChapterLoader() -> RuleSourceChapterLoader {
        return RuleSourceChapterLoader(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
    }

    private func makeRuleSourceReaderLoader() -> RuleSourceReaderLoader {
        return RuleSourceReaderLoader(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
    }
}
