import Foundation
import BrowseCraftCore

// 中文注释：RSSSourceRuntimeFactory 只装配 RSS/Atom runtime，不依赖漫画规则或 SwiftSoup。
struct RSSSourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let definitionMapper: SourceDefinitionMapper

    init(
        pageContentLoader: PageContentLoader,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper()
    ) {
        self.pageContentLoader = pageContentLoader
        self.definitionMapper = definitionMapper
    }

    func makeRuntime(source: Source) throws -> RSSSourceRuntime {
        guard case .rss = source.configuration else {
            throw SourceRuntimeError.invalidInput("RSS runtime requires an RSS source configuration.")
        }

        return RSSSourceRuntime(
            definition: self.definitionMapper.definition(from: source),
            feedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader),
            pageContentLoader: self.pageContentLoader
        )
    }
}
