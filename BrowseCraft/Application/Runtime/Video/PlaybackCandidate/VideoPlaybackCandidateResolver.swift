import Foundation
import BrowseCraftCore

// 中文注释：播放候选 resolver 只规范化播放入口，不负责列表/详情资料抽取。
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

// 中文注释：过滤已知广告/诱导播放媒体域，避免把广告 m3u8 当正片交给 native player。
enum VideoPlaybackAdMediaFilter {
    private static let blockedHosts: Set<String> = [
        "vv.jisuzyv.com"
    ]

    static func isBlocked(_ url: URL?) -> Bool {
        guard let host: String = url?.host?.lowercased() else {
            return false
        }

        return self.blockedHosts.contains(host)
    }
}

protocol VideoPlaybackResolving {
    func resolve(
        candidate: VideoPlaybackCandidate,
        playPageURL: URL,
        html: String
    ) -> VideoPlaybackResolution?
}
