import Foundation

// 中文注释：ComicRuleSourceRuntimeFactory 只组装漫画 SiteRule-backed source 的 runtime 和 loader。
struct ComicRuleSourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let urlResolver: URLResolvingService

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        urlResolver: URLResolvingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.urlResolver = urlResolver
    }

    func makeRuntime(source: Source) -> ComicRuleSourceRuntime {
        return ComicRuleSourceRuntime(
            source: source,
            listLoader: self.makeListLoader(),
            searchLoader: self.makeSearchLoader(),
            chapterLoader: self.makeChapterLoader(),
            readerLoader: self.makeReaderLoader()
        )
    }

    private func makeListLoader() -> ComicRuleSourceListLoader {
        return ComicRuleSourceListLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeSearchLoader() -> ComicRuleSourceSearchLoader {
        return ComicRuleSourceSearchLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser,
            urlResolver: self.urlResolver
        )
    }

    private func makeChapterLoader() -> ComicRuleSourceChapterLoader {
        return ComicRuleSourceChapterLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser
        )
    }

    private func makeReaderLoader() -> ComicRuleSourceReaderLoader {
        return ComicRuleSourceReaderLoader(
            pageContentLoader: self.pageContentLoader,
            comicRuleParser: self.comicRuleParser
        )
    }
}
