import Foundation
import BrowseCraftCore

// 中文注释：正常播放与显式 runtime audit 共用这一份已解析执行输入，不再各自重选规则或合并请求。
struct VideoPreparedPlaybackExecutionSession {
    let source: Source
    let input: SourceVideoPlaybackInput
    let siteRule: VideoSiteRule
    let handoff: SourceVideoPlaybackHandoff
    let entry: ResolvedVideoPlaybackEntry
    let playbackRule: VideoPlaybackRule
    let detailReadyDeclared: Bool
    let requestURL: URL
    let request: RequestConfig?

    var declaredRoutes: [VideoPreparedPlaybackDeclaredRoute] {
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

struct VideoPreparedPlaybackDeclaredRoute: Hashable, Sendable {
    let routeSlot: VideoRuntimeEvidenceRouteSlot
    let executionMode: VideoRuntimeEvidenceExecutionMode
}

// 中文注释：这些事实只描述送入播放器前的路线决策，不能冒充最终媒体响应、owner binding 或 HLS 验收。
struct VideoPreparedPlaybackRouteFact: Hashable, Sendable {
    let routeSlot: VideoRuntimeEvidenceRouteSlot
    let executionMode: VideoRuntimeEvidenceExecutionMode
    let disposition: VideoPreparedPlaybackRouteDisposition
    let routeActivationURL: URL?
    let candidateMediaURL: URL?
    let candidateMediaKind: VideoRuntimeEvidenceMediaKind
    let reason: VideoPreparedPlaybackRouteReason?
}

enum VideoPreparedPlaybackRouteDisposition: Hashable, Sendable {
    case selectedForPlayer
    case rejectedBeforePlayer
    case skipped
}

enum VideoPreparedPlaybackRouteReason: Hashable, Sendable {
    case noCandidate
    case encryptedHLS
    case knownEncryptedMedia
    case finalMediaObservationUnavailable
    case iframeDepthExceeded
    case iframeLoopDetected
    case priorRouteSelected
}

struct VideoPreparedPlaybackExecutionResult {
    let output: SourceVideoPlaybackOutput
    let routeFacts: [VideoPreparedPlaybackRouteFact]
}
