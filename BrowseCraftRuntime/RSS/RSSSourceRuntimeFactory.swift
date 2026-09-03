import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：RSSSourceRuntimeFactory 只装配 RSS/Atom runtime，不依赖漫画规则或 SwiftSoup。
// 中文注释：public 类型不再由编译器推断 Sendable；成员均为不可变值或 Sendable 端口，显式声明。
public struct RSSSourceRuntimeFactory: Sendable {
    private let pageContentLoader: PageContentLoader
    private let pageDataLoader: PageDataLoader
    private let definitionMapper: SourceDefinitionMapper

    public init(
        pageContentLoader: PageContentLoader,
        pageDataLoader: PageDataLoader,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper()
    ) {
        self.pageContentLoader = pageContentLoader
        self.pageDataLoader = pageDataLoader
        self.definitionMapper = definitionMapper
    }

    public func makeRuntime(source: Source) throws -> RSSSourceRuntime {
        guard case .rss = source.configuration else {
            throw SourceRuntimeError.invalidInput("RSS runtime requires an RSS source configuration.")
        }

        return RSSSourceRuntime(
            definition: self.definitionMapper.definition(from: source),
            feedLoader: RSSFeedLoader(pageDataLoader: self.pageDataLoader),
            pageContentLoader: self.pageContentLoader
        )
    }
}
