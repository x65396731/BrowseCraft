import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：VideoSourceRuntimeFactory 只装配 VideoSiteRule V2，不持有或推断站点 adapter。
// 中文注释：public 类型不再由编译器推断 Sendable；成员均为不可变值或 Sendable 端口，显式声明。
public struct VideoSourceRuntimeFactory: Sendable {
    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService
    private let credentialProvider: any SourceCredentialProviding

    public init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
        self.credentialProvider = credentialProvider
    }

    public func makeRuntime(source: Source) throws -> VideoSourceRuntime {
        guard case .video(let configuration) = source.configuration else {
            throw SourceRuntimeError.invalidInput("Video V2 runtime requires a ruleDriven source configuration.")
        }

        let resolvedRule: ResolvedVideoSiteRule
        do {
            resolvedRule = try ResolvedVideoSiteRule(validating: configuration.rule)
        } catch {
            throw SourceRuntimeError.invalidInput(
                "Video V2 rule graph cannot be resolved: \(error.localizedDescription)"
            )
        }

        return VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: self.pageContentLoader,
                parser: self.parser,
                credentialProvider: self.credentialProvider
            ),
            detailLoader: VideoSourceDetailLoader(
                pageContentLoader: self.pageContentLoader,
                parser: self.parser,
                credentialProvider: self.credentialProvider
            ),
            playbackLoader: VideoSourcePlaybackLoader(
                pageContentLoader: self.pageContentLoader,
                parser: self.parser,
                credentialProvider: self.credentialProvider
            )
        )
    }
}
