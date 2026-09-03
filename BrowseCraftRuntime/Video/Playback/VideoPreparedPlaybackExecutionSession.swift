import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：正常播放与显式 runtime audit 共用这一份已解析执行输入，不再各自重选规则或合并请求。
public struct VideoPreparedPlaybackExecutionSession: Sendable {
    public init(
        source: Source,
        input: SourceVideoPlaybackInput,
        siteRule: VideoSiteRule,
        handoff: SourceVideoPlaybackHandoff,
        entry: ResolvedVideoPlaybackEntry,
        playbackRule: VideoPlaybackRule,
        detailReadyDeclared: Bool,
        requestURL: URL,
        request: RequestConfig?
    ) {
        self.source = source
        self.input = input
        self.siteRule = siteRule
        self.handoff = handoff
        self.entry = entry
        self.playbackRule = playbackRule
        self.detailReadyDeclared = detailReadyDeclared
        self.requestURL = requestURL
        self.request = request
    }

    public let source: Source
    public let input: SourceVideoPlaybackInput
    public let siteRule: VideoSiteRule
    public let handoff: SourceVideoPlaybackHandoff
    public let entry: ResolvedVideoPlaybackEntry
    public let playbackRule: VideoPlaybackRule
    public let detailReadyDeclared: Bool
    public let requestURL: URL
    public let request: RequestConfig?

    public var declaredRoutes: [VideoPreparedPlaybackDeclaredRoute] {
        var routes: [VideoPreparedPlaybackDeclaredRoute] = []
        if self.playbackRule.effectiveMediaCandidates.isEmpty == false {
            routes.append(
                VideoPreparedPlaybackDeclaredRoute(
                    routeSlot: .media,
                    executionMode: .directMedia
                )
            )
        }
        if let iframe = self.playbackRule.iframe {
            routes.append(
                VideoPreparedPlaybackDeclaredRoute(
                    routeSlot: .iframe,
                    executionMode: iframe.strategy == .resolve ? .iframeResolve : .webUI
                )
            )
        }
        if self.playbackRule.fallback == .webUI {
            routes.append(
                VideoPreparedPlaybackDeclaredRoute(
                    routeSlot: .fallback,
                    executionMode: .webUI
                )
            )
        }
        return routes
    }
}

public struct VideoPreparedPlaybackDeclaredRoute: Hashable, Sendable {
    public init(
        routeSlot: VideoRuntimeEvidenceRouteSlot,
        executionMode: VideoRuntimeEvidenceExecutionMode
    ) {
        self.routeSlot = routeSlot
        self.executionMode = executionMode
    }

    public let routeSlot: VideoRuntimeEvidenceRouteSlot
    public let executionMode: VideoRuntimeEvidenceExecutionMode
}

// 中文注释：这些事实只描述送入播放器前的路线决策，不能冒充最终媒体响应、owner binding 或 HLS 验收。
public struct VideoPreparedPlaybackRouteFact: Hashable, Sendable {
    public init(
        routeSlot: VideoRuntimeEvidenceRouteSlot,
        executionMode: VideoRuntimeEvidenceExecutionMode,
        disposition: VideoPreparedPlaybackRouteDisposition,
        routeActivationURL: URL?,
        candidateMediaURL: URL?,
        candidateMediaKind: VideoRuntimeEvidenceMediaKind,
        reason: VideoPreparedPlaybackRouteReason?
    ) {
        self.routeSlot = routeSlot
        self.executionMode = executionMode
        self.disposition = disposition
        self.routeActivationURL = routeActivationURL
        self.candidateMediaURL = candidateMediaURL
        self.candidateMediaKind = candidateMediaKind
        self.reason = reason
    }

    public let routeSlot: VideoRuntimeEvidenceRouteSlot
    public let executionMode: VideoRuntimeEvidenceExecutionMode
    public let disposition: VideoPreparedPlaybackRouteDisposition
    public let routeActivationURL: URL?
    public let candidateMediaURL: URL?
    public let candidateMediaKind: VideoRuntimeEvidenceMediaKind
    public let reason: VideoPreparedPlaybackRouteReason?
}

public enum VideoPreparedPlaybackRouteDisposition: Hashable, Sendable {
    case selectedForPlayer
    case rejectedBeforePlayer
    case skipped
}

public enum VideoPreparedPlaybackRouteReason: Hashable, Sendable {
    case noCandidate
    /// 中文注释：与 `noCandidate` 区分开（`BC-EVIDENCE-073`）：规则匹配到了候选，
    /// 但全部候选被运行期噪声过滤丢弃。两者的处置相同，成因不同，审计不得混为一谈。
    case allCandidatesFilteredAsNoise
    case encryptedHLS
    case knownEncryptedMedia
    case finalMediaObservationUnavailable
    case iframeDepthExceeded
    case iframeLoopDetected
    case priorRouteSelected
}

public struct VideoPreparedPlaybackExecutionResult: Sendable {
    public init(
        output: SourceVideoPlaybackOutput,
        routeFacts: [VideoPreparedPlaybackRouteFact]
    ) {
        self.output = output
        self.routeFacts = routeFacts
    }

    public let output: SourceVideoPlaybackOutput
    public let routeFacts: [VideoPreparedPlaybackRouteFact]
}
