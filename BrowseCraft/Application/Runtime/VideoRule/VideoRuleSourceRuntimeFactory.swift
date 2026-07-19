import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceRuntimeFactory 只装配 ruleDriven 视频来源，不持有或推断 legacy adapter。
struct VideoRuleSourceRuntimeFactory {
    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService

    init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
    }

    func makeRuntime(source: Source) throws -> VideoRuleSourceRuntime {
        guard case .video(.ruleDriven(let configuration)) = source.configuration else {
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
                parser: self.parser
            )
        )
    }
}
