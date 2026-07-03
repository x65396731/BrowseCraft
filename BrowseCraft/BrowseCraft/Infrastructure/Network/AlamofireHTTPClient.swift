import Alamofire
import Foundation

// 中文注释：AlamofireHTTPClient.swift 属于网络实现层，用于说明本文件承载的核心职责。

/// 中文注释：生产环境使用的 HTTP 客户端，底层由 Alamofire 实现。
final class AlamofireHTTPClient: HTTPClient {
    /// 中文注释：getString 方法把 V2 RequestConfig 合入默认 HTML 请求头，并通过 CookieHeaderResolver 应用 Cookie 策略。
    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        let urlRequest: URLRequest = self.urlRequest(for: url, request: request)
        let html: String
        do {
            html = try await AF.request(urlRequest).serializingString().value
        } catch {
            throw RuleExecutionError.network(
                url: url.absoluteString,
                underlyingDescription: error.localizedDescription
            )
        }

        let cloudflareBlocked: Bool = html.contains("Attention Required") || html.contains("cf-error-details")

        #if DEBUG
        print(
            "[BrowseCraftNetwork] url=\(url.absoluteString) " +
            "requestScope=\(request?.scope?.rawValue ?? "default") " +
            "needsWebView=\(request?.needsWebView?.description ?? "nil") " +
            "bytes=\(html.utf8.count) " +
            "cloudflareBlocked=\(cloudflareBlocked) " +
            "hasChapterLinks=\(html.contains("/cn/chapters/"))"
        )
        #endif

        if cloudflareBlocked {
            throw RuleExecutionError.antiBot(url: url.absoluteString)
        }

        return html
    }

    /// 中文注释：集中生成 URLRequest，确保页面级 headers 覆盖默认 headers，同时旧站点仍保留浏览器 UA/Accept。
    private func urlRequest(for url: URL, request: RequestConfig?) -> URLRequest {
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = request?.method?.rawValue ?? "GET"

        var headers: [String: String] = self.defaultHeaders(for: url)
        request?.headers?.forEach { key, value in
            headers[key] = value
        }
        headers = CookieHeaderResolver.headersByApplyingPageCookies(
            to: headers,
            url: url,
            request: request
        )

        headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body: RequestBody = request?.body {
            urlRequest.httpBody = Data(body.value.utf8)
            if let contentType: String = body.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        return urlRequest
    }

    /// 中文注释：默认 headers 保持旧版抓取行为，避免没有 RequestConfig 的既存规则产生回归。
    private func defaultHeaders(for url: URL) -> [String: String] {
        return [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9,zh;q=0.8,en;q=0.5",
            "Referer": "\(url.scheme ?? "https")://\(url.host ?? "")/"
        ]
    }
}
