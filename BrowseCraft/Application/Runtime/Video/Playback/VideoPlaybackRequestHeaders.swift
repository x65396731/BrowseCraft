import Foundation
import BrowseCraftCore

// 中文注释：BC-EVIDENCE-079.4——媒体请求头组合的唯一定义点：浏览器默认头 → catalog 覆盖 →
// Referer / User-Agent / Origin 补齐。原生播放器（KSPlayer options）与显式 audit 的有界探针
// 都只消费这一处，保证探针请求与播放器等价。
enum VideoPlaybackRequestHeaders {
    static func compose(
        mediaURL: URL,
        requestConfig: SourcePlaybackRequestConfig?,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    ) -> [String: String] {
        var headers: [String: String] = browserRequestHeaderProvider.defaultHeaders(
            for: mediaURL,
            referer: requestConfig?.referer,
            includeOrigin: true
        )
        guard let requestConfig: SourcePlaybackRequestConfig else {
            return headers
        }
        headers = RequestHeaderFields.applyingOverrides(requestConfig.headers, to: headers)
        if let referer: URL = requestConfig.referer,
           RequestHeaderFields.containsHeader("Referer", in: headers) == false {
            headers["Referer"] = referer.absoluteString
        }
        if let userAgent: String = requestConfig.userAgent,
           RequestHeaderFields.containsHeader("User-Agent", in: headers) == false {
            headers["User-Agent"] = userAgent
        }
        if RequestHeaderFields.containsHeader("Origin", in: headers) == false,
           let origin: String = RequestHeaderFields.originHeader(from: requestConfig.referer) {
            headers["Origin"] = origin
        }
        return headers
    }
}
