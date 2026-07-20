import Foundation
import Nuke

// 中文注释：ImageRequestFactory.swift 属于共享界面组件层，用于说明本文件承载的核心职责。

/// 中文注释：构造图片请求，处理部分站点拒绝普通图片下载的问题。
/// 中文注释：有些漫画 CDN 需要 Referer 等浏览器请求头，这里把兼容逻辑限制在 UI 层。
enum ImageRequestFactory {
    /// 中文注释：makeRequest 方法统一合并默认图片请求头、规则图片请求头和当前页面 Referer。
    static func makeRequest(
        urlString: String,
        refererURLString: String? = nil,
        requestConfig: RequestConfig? = nil,
        additionalHeaders: [String: String]? = nil,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding = EmptyBrowserRequestHeaderProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider()
    ) -> ImageRequest? {
        guard let url: URL = URL(string: urlString) else {
            return nil
        }

        var urlRequest: URLRequest = URLRequest(url: url)
        let refererURL: URL? = refererURLString.flatMap(URL.init(string:))
        var headers: [String: String] = browserRequestHeaderProvider.defaultHeaders(
            for: url,
            referer: refererURL,
            includeOrigin: false
        )
        headers = RequestHeaderFields.applyingOverrides(requestConfig?.imageHeaders, to: headers)
        headers = RequestHeaderFields.applyingOverrides(requestConfig?.imageRequest?.headers, to: headers)

        if let refererURLString: String = refererURLString,
           headers["Referer"] == nil {
            headers["Referer"] = refererURLString
        }
        headers = CookieHeaderResolver.headersByApplyingImageCookies(
            to: headers,
            url: url,
            request: requestConfig,
            browserCookieHeader: systemCookieHeaderProvider.cookieHeader(for: url)
        )
        headers = RequestHeaderFields.applyingOverrides(additionalHeaders, to: headers)

        headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        RuleExecutionLogger.log(
            stage: .image,
            event: "request",
            fields: [
                "urlHost": url.host ?? "nil",
                "urlPath": url.path,
                "scheme": url.scheme ?? "nil",
                "requestScope": requestConfig?.scope?.rawValue ?? "default",
                "headerCount": headers.count,
                "additionalHeaderCount": additionalHeaders?.count ?? 0,
                "hasReferer": headers["Referer"] != nil,
                "hasCookie": headers["Cookie"] != nil
            ]
        )

        return ImageRequest(urlRequest: urlRequest)
    }
}
