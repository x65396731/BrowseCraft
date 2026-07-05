import Foundation
import BrowseCraftCore

// 中文注释：VideoSourceRuntime 是 video source 的 MVP runtime；播放 UI 和历史保存由后续小节接入。
struct VideoSourceRuntime: SourceRuntime {
    let definition: SourceDefinition

    private let pageContentLoader: PageContentLoader
    private let parser: any VideoHTMLParsing

    init(
        definition: SourceDefinition,
        pageContentLoader: PageContentLoader,
        parser: any VideoHTMLParsing
    ) {
        self.definition = definition
        self.pageContentLoader = pageContentLoader
        self.parser = parser
    }

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: true,
            supportsDetail: true,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: self.definition.video?.requiresAccount ?? false,
            limitations: [
                self.limitation(.search, "Video MVP does not support search yet."),
                self.limitation(.reader, "Video sources use VideoPlayerHostView instead of reader output."),
                self.limitation(.debug, "Video debug runtime is not connected yet."),
                self.limitation(.candidateAnalysis, "Video MVP uses a MacCMS template parser, not selector candidate analysis.")
            ]
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        let url: URL = try self.listURL(for: input)
        let html: String = try await self.pageContentLoader.getString(from: url)
        let items: [SourceContentItem] = try self.parser.parseList(
            html: html,
            definition: self.definition,
            pageURL: url
        )

        return SourceListOutput(
            items: items,
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: url
                )
            )
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        throw SourceRuntimeError.unsupported(.custom("Video MVP does not support search yet."))
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        try self.validateSource(input.context)
        let html: String = try await self.pageContentLoader.getString(from: input.detailURL)
        let chapters: [SourceChapter] = try self.parser.parseDetail(
            html: html,
            definition: self.definition,
            detailURL: input.detailURL
        )

        return SourceDetailOutput(
            chapters: chapters,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.detailURL
                )
            )
        )
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        throw SourceRuntimeError.unsupported(.custom("Video sources do not produce reader output."))
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "Video debug runtime is not connected yet.",
                context: SourceRuntimeDiagnosticContext(runtimeContext: input)
            )
        )
    }

    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput {
        try self.validateSource(input.context)
        let html: String = try await self.pageContentLoader.getString(from: input.playPageURL)
        let reference: SourceVideoPlaybackReference = try self.parser.parsePlayback(
            html: html,
            definition: self.definition,
            playPageURL: input.playPageURL
        )

        return SourceVideoPlaybackOutput(
            reference: reference,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.playPageURL
                )
            )
        )
    }

    private func entryURL() throws -> URL {
        guard let definition: VideoSourceDefinition = self.definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        return definition.entryURL
    }

    private func listURL(for input: SourceListInput) throws -> URL {
        if let urlOverride: URL = input.urlOverride {
            return urlOverride
        }

        if let requestOverrideURL: URL = input.context.requestOverride?.url {
            return requestOverrideURL
        }

        return try self.entryURL()
    }

    private func validateSource(_ context: SourceRuntimeContext) throws {
        guard context.sourceID == self.definition.id else {
            throw SourceRuntimeError.sourceMismatch(
                expected: self.definition.id,
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
            reason: .notImplemented,
            message: message
        )
    }
}
