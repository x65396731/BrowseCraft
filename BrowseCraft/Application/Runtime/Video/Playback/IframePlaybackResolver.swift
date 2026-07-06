import Foundation
import BrowseCraftCore

// 中文注释：IframePlaybackResolver 的 MVP 只接住 iframe/embed 播放入口，不做多跳、解密或 WebView 抓包。
struct IframePlaybackResolver: VideoPlaybackResolving {
    func resolve(
        candidate: VideoPlaybackCandidate,
        playPageURL: URL,
        html: String
    ) -> VideoPlaybackResolution? {
        guard candidate.kind == .iframe,
              let url: URL = candidate.url else {
            return nil
        }

        return VideoPlaybackResolution(
            candidateMediaURL: url,
            candidateMediaKind: .iframe,
            playbackRequestConfig: SourcePlaybackRequestConfig(
                headers: [
                    "Referer": playPageURL.absoluteString
                ],
                referer: playPageURL,
                userAgent: nil
            ),
            status: .pageOnly
        )
    }
}

