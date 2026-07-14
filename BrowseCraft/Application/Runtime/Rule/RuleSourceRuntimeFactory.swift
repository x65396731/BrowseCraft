import Foundation

// 中文注释：RuleSourceRuntimeFactory 只组装 SiteRule-backed source 的 runtime 和 loader。
struct RuleSourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let ruleSourceParser: RuleSourceParsingService
    private let urlResolver: URLResolvingService

    init(
        pageContentLoader: PageContentLoader,
        ruleSourceParser: RuleSourceParsingService,
        urlResolver: URLResolvingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleSourceParser = ruleSourceParser
        self.urlResolver = urlResolver
    }

    func makeRuntime(source: Source) -> RuleSourceRuntime {
        return RuleSourceRuntime(
            source: source,
            listLoader: self.makeListLoader(),
            searchLoader: self.makeSearchLoader(),
            chapterLoader: self.makeChapterLoader(),
            readerLoader: self.makeReaderLoader()
        )
    }

    private func makeListLoader() -> RuleSourceListLoader {
        return RuleSourceListLoader(
            pageContentLoader: self.pageContentLoader,
            ruleSourceParser: self.ruleSourceParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeSearchLoader() -> RuleSourceSearchLoader {
        return RuleSourceSearchLoader(
            pageContentLoader: self.pageContentLoader,
            ruleSourceParser: self.ruleSourceParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeChapterLoader() -> RuleSourceChapterLoader {
        return RuleSourceChapterLoader(
            pageContentLoader: self.pageContentLoader,
            ruleSourceParser: self.ruleSourceParser
        )
    }

    private func makeReaderLoader() -> RuleSourceReaderLoader {
        return RuleSourceReaderLoader(
            pageContentLoader: self.pageContentLoader,
            ruleSourceParser: self.ruleSourceParser
        )
    }
}
