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
        requestConfig: RequestConfig? = nil
    ) -> ImageRequest? {
        guard let url: URL = URL(string: urlString) else {
            return nil
        }

        var urlRequest: URLRequest = URLRequest(url: url)
        var headers: [String: String] = self.defaultImageHeaders
        requestConfig?.imageHeaders?.forEach { key, value in
            headers[key] = value
        }
        requestConfig?.imageRequest?.headers?.forEach { key, value in
            headers[key] = value
        }

        if let refererURLString: String = refererURLString,
           headers["Referer"] == nil {
            headers["Referer"] = refererURLString
        }
        headers = CookieHeaderResolver.headersByApplyingImageCookies(
            to: headers,
            url: url,
            request: requestConfig
        )

        headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        return ImageRequest(urlRequest: urlRequest)
    }

    /// 中文注释：默认图片 headers 保持旧版兼容，规则字段只在需要防盗链或特殊 Accept 时覆盖它们。
    private static var defaultImageHeaders: [String: String] {
        return [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
        ]
    }
}
