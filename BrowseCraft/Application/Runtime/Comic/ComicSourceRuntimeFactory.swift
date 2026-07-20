import Foundation
import BrowseCraftCore

// 中文注释：ComicSourceRuntimeFactory 只组装漫画 SiteRule-backed source 的 runtime 和 loader。
struct ComicSourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let urlResolver: URLResolvingService
    private let defaultUserAgent: String

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        urlResolver: URLResolvingService,
        defaultUserAgent: String = ""
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.urlResolver = urlResolver
        self.defaultUserAgent = defaultUserAgent
    }

    func makeRuntime(source: Source) throws -> ComicSourceRuntime {
        guard case .comic = source.configuration else {
            throw SourceRuntimeError.invalidInput("Comic runtime requires a comic source configuration.")
        }

        return ComicSourceRuntime(
            source: source,
            listLoader: self.makeListLoader(),
            searchLoader: self.makeSearchLoader(),
            detailLoader: self.makeDetailLoader(),
            readerLoader: self.makeReaderLoader()
        )
    }

    private func makeListLoader() -> ComicSourceListLoader {
        return ComicSourceListLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser,
            urlResolver: self.urlResolver,
            defaultUserAgent: self.defaultUserAgent
        )
    }

    private func makeSearchLoader() -> ComicSourceSearchLoader {
        return ComicSourceSearchLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeDetailLoader() -> ComicSourceDetailLoader {
        return ComicSourceDetailLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser,
            defaultUserAgent: self.defaultUserAgent
        )
    }

    private func makeReaderLoader() -> ComicSourceReaderLoader {
        return ComicSourceReaderLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser,
            defaultUserAgent: self.defaultUserAgent
        )
    }
}
