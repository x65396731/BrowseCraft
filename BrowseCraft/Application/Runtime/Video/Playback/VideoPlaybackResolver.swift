import Foundation
import BrowseCraftCore

// 中文注释：VideoPlaybackResolver 只规范化播放候选，不负责列表/详情资料抽取。
struct VideoPlaybackCandidate {
    var url: URL?
    var kind: SourceVideoMediaKind
}

struct VideoPlaybackResolution {
    var candidateMediaURL: URL?
    var candidateMediaKind: SourceVideoMediaKind
    var playbackRequestConfig: SourcePlaybackRequestConfig?
    var status: SourceVideoPlaybackStatus
}

protocol VideoPlaybackResolving {
    func resolve(
        candidate: VideoPlaybackCandidate,
        playPageURL: URL,
        html: String
    ) -> VideoPlaybackResolution?
}

