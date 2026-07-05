import Foundation
import BrowseCraftCore

struct SourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let urlResolver: URLResolvingService

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.urlResolver = urlResolver
    }

    func makeRuntimeResolver() -> SourceRuntimeResolver {
        return SourceRuntimeResolver(
            rssRuntimeFactory: { definition in
                return self.makeRSSSourceRuntime(definition: definition)
            },
            ruleRuntimeFactory: { source in
                return self.makeRuleSourceRuntime(source: source)
            }
        )
    }

    func makeRSSSourceRuntime(definition: SourceDefinition) -> RSSSourceRuntime {
        return RSSSourceRuntime(
            definition: definition,
            feedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader)
        )
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
            urlResolver: self.urlResolver
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
