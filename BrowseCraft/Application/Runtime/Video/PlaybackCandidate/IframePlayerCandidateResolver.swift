import Foundation
import BrowseCraftCore

// 中文注释：IframePlayerCandidateResolver 只接住 iframe/embed 播放候选，不做内容 frame、解密或 WebView 抓包。
struct IframePlayerCandidateResolver: VideoPlaybackResolving {
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
                headers: BrowserRequestHeaders.Chrome.playbackHeaders(referer: playPageURL),
                referer: playPageURL,
                userAgent: BrowserRequestHeaders.Chrome.chromeUserAgent
            ),
            status: .pageOnly
        )
    }
}
