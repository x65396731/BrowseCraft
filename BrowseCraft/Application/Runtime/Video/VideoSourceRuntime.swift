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
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: self.definition.video?.requiresAccount ?? false,
            limitations: [
                self.limitation(.search, "Video MVP does not support search yet."),
                self.limitation(.reader, "Video sources use VideoPlayerHostView instead of reader output."),
                self.limitation(.debug, "Video debug runtime is not connected yet."),
                self.limitation(.candidateAnalysis, "Video MVP uses a MacCMS template mapper, not selector candidate analysis."),
                SourceRuntimeCapabilityLimitation(
                    capability: .webView,
                    reason: .notConnected,
                    message: "WebView video rendering is not connected yet."
                )
            ]
        )
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

        return SourceDetailOutput(
            chapters: content.episodes.map { episode in
                return SourceChapter(
                    id: episode.id,
                    title: episode.title,
                    url: episode.playPageURL
                )
            },
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                requestLogs: [
                    VideoRequestConfigResolver().requestLog(
                        url: input.detailURL,
                        request: request
                    )
                ],
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.detailURL
                )
            )
        )
    }

    func loadVideoDetailContent(_ input: SourceDetailInput) async throws -> VideoDetailContent {
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
                message: "Video debug runtime is not connected yet.",
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

// 中文注释：P5.1.12 的渲染层门闩；WebView 视频渲染接入前，避免静态 mapper 把 JS 壳页误报为普通解析失败。
struct VideoSourceRenderingGuard {
    private let detector: any VideoSourceDetecting

    init(detector: any VideoSourceDetecting = VideoSourceDetector()) {
        self.detector = detector
    }

    func validateStaticHTML(
        url: URL,
        html: String,
        headers: [String: String] = [:]
    ) throws {
        let detection: VideoSourceDetection = self.detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: html,
                headers: headers
            )
        )

        guard detection.renderMode == .staticHTML else {
            throw SourceRuntimeError.unsupported(
                .custom(self.unsupportedWebViewMessage(detection: detection))
            )
        }
    }

    private func unsupportedWebViewMessage(detection: VideoSourceDetection) -> String {
        var details: [String] = [
            "Video source requires WebView rendering, but WebView video rendering is not connected yet.",
            "Render mode: \(detection.renderMode.rawValue).",
            "Adapter: \(detection.adapter.rawValue).",
            "Playback mode: \(detection.playbackMode.rawValue)."
        ]

        if detection.warnings.isEmpty == false {
            details.append("Warnings: \(detection.warnings.joined(separator: " "))")
        }

        return details.joined(separator: " ")
    }
}
