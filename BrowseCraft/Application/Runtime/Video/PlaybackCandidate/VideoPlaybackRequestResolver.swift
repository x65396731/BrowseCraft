import Foundation
import BrowseCraftCore

// 中文注释：播放器请求只在真正播放时读取 Cookie；SourceVideoPlaybackReference 仅持久化策略，不持久化登录态值。
struct VideoPlaybackRequestResolver {
    private let credentialProvider: any SourceCredentialProviding

    init(credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()) {
        self.credentialProvider = credentialProvider
    }

    func resolve(
        _ config: SourcePlaybackRequestConfig?,
        source: Source,
        resourceURL: URL
    ) -> SourcePlaybackRequestConfig? {
        guard let config: SourcePlaybackRequestConfig else {
            return nil
        }
        let context = SourceRequestContext(
            sourceID: source.id,
            baseURL: URL(string: source.baseURL),
            purpose: .video,
            refererURL: config.referer
        )
        let credentialCookieHeader: String? = self.credentialProvider.cookieHeader(
            for: context,
            url: resourceURL
        )
        let cookieRequest = RequestConfig(
            cookiePolicy: config.cookiePolicy,
            cookiePriority: config.cookiePriority
        )
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingPageCookies(
            to: config.headers,
            url: resourceURL,
            request: cookieRequest,
            credentialCookieHeader: credentialCookieHeader
        )
        return SourcePlaybackRequestConfig(
            headers: headers,
            referer: config.referer,
            userAgent: config.userAgent,
            cookiePolicy: config.cookiePolicy,
            cookiePriority: config.cookiePriority
        )
    }
}
