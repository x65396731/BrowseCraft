import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeFactory 集中装配各 runtime；comic 入口使用 ComicRuleSourceRuntime。
struct SourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let comicRuleSourceRuntimeFactory: ComicRuleSourceRuntimeFactory
    private let videoRuleSourceRuntimeFactory: VideoRuleSourceRuntimeFactory

    init(
        pageContentLoader: PageContentLoader,
        comicRuleSourceRuntimeFactory: ComicRuleSourceRuntimeFactory,
        videoRuleSourceRuntimeFactory: VideoRuleSourceRuntimeFactory
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleSourceRuntimeFactory = comicRuleSourceRuntimeFactory
        self.videoRuleSourceRuntimeFactory = videoRuleSourceRuntimeFactory
    }

    func makeRuntimeResolver() -> SourceRuntimeResolver {
        return SourceRuntimeResolver(
            rssRuntimeFactory: { definition in
                return self.makeRSSSourceRuntime(definition: definition)
            },
            videoRuleRuntimeFactory: { source in
                return try self.makeVideoRuleSourceRuntime(source: source)
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

    func makeVideoRuleSourceRuntime(source: Source) throws -> VideoRuleSourceRuntime {
        return try self.videoRuleSourceRuntimeFactory.makeRuntime(source: source)
    }

    func makeComicSourceRuntime(source: Source) -> ComicRuleSourceRuntime {
        return self.comicRuleSourceRuntimeFactory.makeRuntime(source: source)
    }
}
