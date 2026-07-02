import Alamofire
import Foundation

// 中文注释：AlamofireHTTPClient.swift 属于网络实现层，用于说明本文件承载的核心职责。

/// 中文注释：生产环境使用的 HTTP 客户端，底层由 Alamofire 实现。
final class AlamofireHTTPClient: HTTPClient {
    /// 中文注释：getString 方法封装当前类型的一段业务或界面行为。
    func getString(from url: URL) async throws -> String {
        let headers: HTTPHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9,zh;q=0.8,en;q=0.5",
            "Referer": "\(url.scheme ?? "https")://\(url.host ?? "")/"
        ]

        let html: String = try await AF.request(url, headers: headers).serializingString().value

        #if DEBUG
        print(
            "[BrowseCraftNetwork] url=\(url.absoluteString) " +
            "bytes=\(html.utf8.count) " +
            "cloudflareBlocked=\(html.contains("Attention Required") || html.contains("cf-error-details")) " +
            "hasChapterLinks=\(html.contains("/cn/chapters/"))"
        )
        #endif

        return html
    }
}
