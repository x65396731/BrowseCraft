import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeFactory 集中装配各 runtime；comic 入口当前复用 RuleSourceRuntime 实现。
struct SourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let urlResolver: URLResolvingService
    private let videoAdapterRegistry: VideoAdapterRegistry

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        videoAdapterRegistry: VideoAdapterRegistry = VideoAdapterRegistry()
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.urlResolver = urlResolver
        self.videoAdapterRegistry = videoAdapterRegistry
    }

    func makeRuntimeResolver() -> SourceRuntimeResolver {
        return SourceRuntimeResolver(
            rssRuntimeFactory: { definition in
                return self.makeRSSSourceRuntime(definition: definition)
            },
            videoRuntimeFactory: { definition in
                return self.makeVideoSourceRuntime(definition: definition)
            },
            comicRuntimeFactory: { source in
                return self.makeComicSourceRuntime(source: source)
            }
        )
    }

    func makeRSSSourceRuntime(definition: SourceDefinition) -> RSSSourceRuntime {
        return RSSSourceRuntime(
            definition: definition,
            feedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader)
        )
    }

    func makeVideoSourceRuntime(definition: SourceDefinition) -> VideoSourceRuntime {
        let mapper: any VideoHTMLMapper = self.makeVideoHTMLMapper(definition: definition)
        return VideoSourceRuntime(
            definition: definition,
            listLoader: VideoSourceListLoader(
                pageContentLoader: self.pageContentLoader,
                mapper: mapper
            ),
            detailLoader: VideoSourceDetailLoader(
                pageContentLoader: self.pageContentLoader,
                mapper: mapper
            ),
            playbackLoader: VideoSourcePlaybackLoader(
                pageContentLoader: self.pageContentLoader,
                mapper: mapper
            )
        )
    }

    private func makeVideoHTMLMapper(definition: SourceDefinition) -> any VideoHTMLMapper {
        return self.videoAdapterRegistry.mapper(for: definition.video?.adapter)
    }

    func makeComicSourceRuntime(source: Source) -> RuleSourceRuntime {
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
