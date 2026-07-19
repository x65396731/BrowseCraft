import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceRuntime 只执行 VideoSiteRule V2；详情、播放和搜索在后续正式合同接入。
struct VideoRuleSourceRuntime: SourceRuntime {
    let source: Source
    let resolvedRule: ResolvedVideoSiteRule

    private let listLoader: VideoRuleSourceListLoader
    private let definitionMapper: SourceDefinitionMapper

    init(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        listLoader: VideoRuleSourceListLoader,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper()
    ) {
        self.source = source
        self.resolvedRule = resolvedRule
        self.listLoader = listLoader
        self.definitionMapper = definitionMapper
    }

    var definition: SourceDefinition {
        return self.definitionMapper.definition(from: self.source)
    }

    var capabilities: SourceRuntimeCapabilities {
        let supportsPagination: Bool = self.supportsPagination
        var limitations: [SourceRuntimeCapabilityLimitation] = [
            self.limitation(.search, "Video V2 search is not part of the P0 contract."),
            self.limitation(.detail, "Video V2 detail rules are added in P1."),
            self.limitation(.reader, "Video V2 playback rules are added after the detail/episode contract."),
            self.limitation(.debug, "Video V2 debug output is not connected."),
            self.limitation(.candidateAnalysis, "Video V2 candidate analysis is not connected.")
        ]
        if supportsPagination == false {
            limitations.append(
                SourceRuntimeCapabilityLimitation(
                    capability: .pagination,
                    reason: .unsupportedBySource,
                    message: "This Video V2 source does not declare numeric placeholder pagination."
                )
            )
        }

        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: supportsPagination,
            supportsDetail: false,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: self.resolvedRule.listEntries.contains { entry in
                return entry.effectiveRequest?.needsWebView == true
            },
            requiresCookieStore: self.resolvedRule.listEntries.contains { entry in
                return entry.effectiveRequest?.cookiePolicy != nil
            },
            requiresAccount: false,
            limitations: limitations
        )
    }

    private var supportsPagination: Bool {
        return self.resolvedRule.listEntries.contains { entry in
            return self.resolvedRule.listRule(for: entry).pagination != nil
        }
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        return try await self.listLoader.execute(
            source: self.source,
            resolvedRule: self.resolvedRule,
            input: input
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        throw SourceRuntimeError.unsupported(.custom("Video V2 search is not part of the P0 contract."))
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        try self.validateSource(input.context)
        throw SourceRuntimeError.unsupported(.custom("Video V2 detail runtime is not connected until P1."))
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        try self.validateSource(input.context)
        throw SourceRuntimeError.unsupported(.custom("Video V2 does not produce comic reader output."))
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "Video V2 debug output is not connected.",
                context: SourceRuntimeDiagnosticContext(runtimeContext: input)
            )
        )
    }

    private func validateSource(_ context: SourceRuntimeContext) throws {
        guard context.sourceID == self.source.id else {
            throw SourceRuntimeError.sourceMismatch(
                expected: self.source.id,
                actual: context.sourceID
            )
        }
    }

    private func limitation(
        _ capability: SourceRuntimeCapability,
        _ message: String
    ) -> SourceRuntimeCapabilityLimitation {
        return SourceRuntimeCapabilityLimitation(
            capability: capability,
            reason: .notConnected,
            message: message
        )
    }
}
