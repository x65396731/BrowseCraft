import Foundation
import BrowseCraftCore

// 中文注释：VideoSourceRuntime 是 video source 的 SourceRuntime 门面；页面加载和 HTML 映射下沉到 Loading/Mapping。
struct VideoSourceRuntime: SourceRuntime {
    let definition: SourceDefinition

    private let listLoader: any VideoSourceListLoading
    private let detailLoader: any VideoSourceDetailLoading
    private let playbackLoader: any VideoSourcePlaybackLoading

    init(
        definition: SourceDefinition,
        listLoader: any VideoSourceListLoading,
        detailLoader: any VideoSourceDetailLoading,
        playbackLoader: any VideoSourcePlaybackLoading
    ) {
        self.definition = definition
        self.listLoader = listLoader
        self.detailLoader = detailLoader
        self.playbackLoader = playbackLoader
    }

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: true,
            supportsDetail: true,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: self.requiresWebView,
            requiresCookieStore: false,
            requiresAccount: self.definition.video?.requiresAccount ?? false,
            limitations: [
                self.limitation(.search, "Video MVP does not support search yet."),
                self.limitation(.reader, "Video sources use VideoPlayerHostView instead of reader output."),
                self.limitation(.debug, "Video runtime diagnostics are not available."),
                self.limitation(.candidateAnalysis, "Video MVP uses template mappers, not selector candidate analysis.")
            ]
        )
    }

    private var requiresWebView: Bool {
        guard let videoDefinition: VideoSourceDefinition = self.definition.video else {
            return false
        }

        return videoDefinition.sharedRequest?.needsWebView == true
            || videoDefinition.listRequest?.needsWebView == true
            || videoDefinition.detailRequest?.needsWebView == true
            || videoDefinition.playRequest?.needsWebView == true
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        return try await self.listLoader.loadList(input, definition: self.definition)
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        throw SourceRuntimeError.unsupported(.custom("Video MVP does not support search yet."))
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        let content: VideoDetailContent = try await self.loadVideoDetailContent(input)
        let request: RequestConfig? = self.detailRequest(for: input)
        let requestLogs: [SourceRequestLog]
        if content.requestLogs.isEmpty {
            requestLogs = [
                VideoRequestConfigResolver().requestLog(
                    url: input.detailURL,
                    request: request
                )
            ]
        } else {
            requestLogs = content.requestLogs
        }

        return SourceDetailOutput(
            metadata: SourceDetailMetadata(
                description: content.synopsis,
                attributes: content.metadataRows.map { SourceDetailAttribute(value: $0) }
            ),
            chapters: content.episodes.map { episode in
                return SourceChapter(
                    id: episode.id,
                    title: episode.title,
                    url: episode.playPageURL
                )
            },
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                requestLogs: requestLogs,
                issues: content.issues,
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.detailURL
                )
            )
        )
    }

    private func loadVideoDetailContent(_ input: SourceDetailInput) async throws -> VideoDetailContent {
        try self.validateSource(input.context)
        return try await self.detailLoader.loadDetailContent(input, definition: self.definition)
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        throw SourceRuntimeError.unsupported(.custom("Video sources do not produce reader output."))
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "Video runtime diagnostics are not available.",
                context: SourceRuntimeDiagnosticContext(runtimeContext: input)
            )
        )
    }

    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput {
        try self.validateSource(input.context)
        return try await self.playbackLoader.loadPlayback(input, definition: self.definition)
    }

    private func validateSource(_ context: SourceRuntimeContext) throws {
        guard context.sourceID == self.definition.id else {
            throw SourceRuntimeError.sourceMismatch(
                expected: self.definition.id,
                actual: context.sourceID
            )
        }
    }

    private func detailRequest(for input: SourceDetailInput) -> RequestConfig? {
        guard let videoDefinition: VideoSourceDefinition = self.definition.video else {
            return nil
        }

        return VideoRequestConfigResolver().request(
            for: .detail,
            definition: videoDefinition,
            context: input.context
        )
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
