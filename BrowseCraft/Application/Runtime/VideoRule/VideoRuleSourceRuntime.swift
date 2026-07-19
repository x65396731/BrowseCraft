import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceRuntime 只执行 VideoSiteRule V2；P1-5 已接通 DOM/API 与显式空结果 fallback。
struct VideoRuleSourceRuntime: SourceRuntime {
    let source: Source
    let resolvedRule: ResolvedVideoSiteRule

    private let listLoader: VideoRuleSourceListLoader
    private let detailLoader: VideoRuleSourceDetailLoader?
    private let definitionMapper: SourceDefinitionMapper

    init(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        listLoader: VideoRuleSourceListLoader,
        detailLoader: VideoRuleSourceDetailLoader? = nil,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper()
    ) {
        self.source = source
        self.resolvedRule = resolvedRule
        self.listLoader = listLoader
        self.detailLoader = detailLoader
        self.definitionMapper = definitionMapper
    }

    var definition: SourceDefinition {
        return self.definitionMapper.definition(from: self.source)
    }

    var capabilities: SourceRuntimeCapabilities {
        let supportsPagination: Bool = self.supportsPagination
        let supportsDetail: Bool = self.supportsDetail
        var limitations: [SourceRuntimeCapabilityLimitation] = [
            self.limitation(.search, "Video V2 search is not part of the P0 contract."),
            self.limitation(.reader, "Video V2 playback rules are added after the detail/episode contract."),
            self.limitation(.debug, "Video V2 debug output is not connected."),
            self.limitation(.candidateAnalysis, "Video V2 candidate analysis is not connected.")
        ]
        if supportsDetail == false {
            limitations.append(self.detailLimitation)
        }
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
            supportsDetail: supportsDetail,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: self.requiresWebView,
            requiresCookieStore: self.requiresCookieStore,
            requiresAccount: false,
            limitations: limitations
        )
    }

    private var supportsPagination: Bool {
        return self.resolvedRule.listEntries.contains { entry in
            let rule: VideoListRule = self.resolvedRule.listRule(for: entry)
            return rule.pagination != nil && rule.effectiveSourceStrategy != .apiOnly
        }
    }

    private var supportsDetail: Bool {
        return self.detailLoader != nil && self.resolvedRule.detailEntries.isEmpty == false
    }

    private var requiresWebView: Bool {
        return self.effectiveExecutionRequests.contains { $0.needsWebView == true }
    }

    private var requiresCookieStore: Bool {
        return self.effectiveExecutionRequests.contains { $0.cookiePolicy != nil }
    }

    private var effectiveExecutionRequests: [RequestConfig] {
        var requests: [RequestConfig] = []
        for entry: ResolvedVideoListEntry in self.resolvedRule.listEntries {
            let strategy: VideoRuleDataSourceStrategy = self.resolvedRule
                .listRule(for: entry)
                .effectiveSourceStrategy
            if strategy != .apiOnly, let request: RequestConfig = entry.effectiveListRequest {
                requests.append(request)
            }
            if strategy != .domOnly, let request: RequestConfig = entry.effectiveListAPIRequest {
                requests.append(request)
            }
        }
        for entry: ResolvedVideoDetailEntry in self.resolvedRule.detailEntries {
            let detailStrategy: VideoRuleDataSourceStrategy = self.resolvedRule
                .detailRule(for: entry)
                .effectiveSourceStrategy
            if detailStrategy != .apiOnly, let request: RequestConfig = entry.effectiveDetailRequest {
                requests.append(request)
            }
            if detailStrategy != .domOnly, let request: RequestConfig = entry.effectiveDetailAPIRequest {
                requests.append(request)
            }
            let episodeStrategy: VideoRuleDataSourceStrategy = self.resolvedRule
                .episodeRule(for: entry)
                .effectiveSourceStrategy
            if episodeStrategy != .apiOnly, let request: RequestConfig = entry.effectiveEpisodeRequest {
                requests.append(request)
            }
            if episodeStrategy != .domOnly, let request: RequestConfig = entry.effectiveEpisodeAPIRequest {
                requests.append(request)
            }
        }
        return requests
    }

    private var detailLimitation: SourceRuntimeCapabilityLimitation {
        if self.detailLoader == nil {
            return SourceRuntimeCapabilityLimitation(
                capability: .detail,
                reason: .notConnected,
                message: "Video V2 detail loader is not assembled."
            )
        }
        if self.resolvedRule.detailEntries.isEmpty {
            return SourceRuntimeCapabilityLimitation(
                capability: .detail,
                reason: .unsupportedBySource,
                message: "This Video V2 source does not declare a detail/episode rule chain."
            )
        }
        return SourceRuntimeCapabilityLimitation(
            capability: .detail,
            reason: .unsupportedBySource,
            message: "This Video V2 source does not expose an executable detail/episode rule chain."
        )
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
        if let reference: SourceItemReference = input.itemReference,
           reference.sourceID != self.source.id {
            throw SourceRuntimeError.sourceMismatch(
                expected: self.source.id,
                actual: reference.sourceID
            )
        }
        guard let detailLoader: VideoRuleSourceDetailLoader = self.detailLoader else {
            throw SourceRuntimeError.notConnected("Video V2 detail loader is not assembled.")
        }
        return try await detailLoader.execute(
            source: self.source,
            resolvedRule: self.resolvedRule,
            input: input
        )
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
