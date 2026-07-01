import Foundation
import Nuke

// 中文注释：ImageRequestFactory.swift 属于共享界面组件层，用于说明本文件承载的核心职责。

/// 中文注释：构造图片请求，处理部分站点拒绝普通图片下载的问题。
/// 中文注释：有些漫画 CDN 需要 Referer 等浏览器请求头，这里把兼容逻辑限制在 UI 层。
enum ImageRequestFactory {
    /// 中文注释：makeRequest 方法封装当前类型的一段业务或界面行为。
    static func makeRequest(urlString: String, refererURLString: String? = nil) -> ImageRequest? {
        guard let url: URL = URL(string: urlString) else {
            return nil
        }

        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        urlRequest.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        if let refererURLString: String = refererURLString {
            urlRequest.setValue(refererURLString, forHTTPHeaderField: "Referer")
        }

        return ImageRequest(urlRequest: urlRequest)
    }
}

