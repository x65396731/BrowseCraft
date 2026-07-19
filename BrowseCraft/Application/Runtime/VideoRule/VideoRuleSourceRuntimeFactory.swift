import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceRuntimeFactory 只装配 VideoSiteRule V2，不持有或推断站点 adapter。
struct VideoRuleSourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService
    private let credentialProvider: any SourceCredentialProviding

    init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
        self.credentialProvider = credentialProvider
    }

    func makeRuntime(source: Source) throws -> VideoRuleSourceRuntime {
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

        return VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
                pageContentLoader: self.pageContentLoader,
                parser: self.parser,
                credentialProvider: self.credentialProvider
            ),
            detailLoader: VideoRuleSourceDetailLoader(
                pageContentLoader: self.pageContentLoader,
                parser: self.parser,
                credentialProvider: self.credentialProvider
            ),
            playbackLoader: VideoRuleSourcePlaybackLoader(
                pageContentLoader: self.pageContentLoader,
                parser: self.parser,
                credentialProvider: self.credentialProvider
            )
        )
    }
}
