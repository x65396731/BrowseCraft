import Foundation
import BrowseCraftCore

// 中文注释：IframePlayerPlaybackResolver 只接住 iframe/embed 播放入口，不做内容 frame、解密或 WebView 抓包。
struct IframePlayerPlaybackResolver: VideoPlaybackResolving {
    private static let playbackUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func resolve(
        candidate: VideoPlaybackCandidate,
        playPageURL: URL,
        html: String
    ) -> VideoPlaybackResolution? {
        guard candidate.kind == .iframePlayer,
              let url: URL = candidate.url else {
            return nil
        }

        return VideoPlaybackResolution(
            candidateMediaURL: url,
            candidateMediaKind: .iframePlayer,
            playbackRequestConfig: SourcePlaybackRequestConfig(
                headers: [
                    "Referer": playPageURL.absoluteString,
                    "User-Agent": Self.playbackUserAgent
                ],
                referer: playPageURL,
                userAgent: Self.playbackUserAgent
            ),
            status: .pageOnly
        )
    }
}
