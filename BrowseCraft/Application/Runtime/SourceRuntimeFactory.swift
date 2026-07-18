import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeFactory 集中装配各 runtime；comic 入口使用 ComicRuleSourceRuntime。
struct SourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let comicRuleSourceRuntimeFactory: ComicRuleSourceRuntimeFactory
    private let videoContentMapperRegistry: VideoContentMapperRegistry

    init(
        pageContentLoader: PageContentLoader,
        comicRuleSourceRuntimeFactory: ComicRuleSourceRuntimeFactory,
        videoContentMapperRegistry: VideoContentMapperRegistry = VideoContentMapperRegistry()
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleSourceRuntimeFactory = comicRuleSourceRuntimeFactory
        self.videoContentMapperRegistry = videoContentMapperRegistry
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
            feedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader),
            pageContentLoader: self.pageContentLoader
        )
    }

    func makeVideoSourceRuntime(definition: SourceDefinition) -> VideoSourceRuntime {
        let mapper: any VideoContentMapper = self.makeVideoContentMapper(definition: definition)
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

    private func makeVideoContentMapper(definition: SourceDefinition) -> any VideoContentMapper {
        return self.videoContentMapperRegistry.mapper(for: definition)
    }

    func makeComicSourceRuntime(source: Source) -> ComicRuleSourceRuntime {
        return self.comicRuleSourceRuntimeFactory.makeRuntime(source: source)
    }
}
