import Alamofire
import Foundation

// 中文注释：AlamofireHTTPClient.swift 属于网络实现层，用于说明本文件承载的核心职责。

private struct HTTPDataResponse {
    let data: Data
    let response: HTTPURLResponse?
}

/// 中文注释：生产环境使用的 HTTP 客户端，底层由 Alamofire 实现。
final class AlamofireHTTPClient: HTTPClient {
    /// 中文注释：getString 方法把 V2 RequestConfig 合入默认 HTML 请求头，并通过 CookieHeaderResolver 应用 Cookie 策略。
    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        let urlRequest: URLRequest = self.urlRequest(for: url, request: request)
        let dataResponse: HTTPDataResponse
        let html: String
        do {
            dataResponse = try await self.performDataRequest(urlRequest)
            html = self.string(from: dataResponse.data, request: request, response: dataResponse.response)
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
            "bytes=\(dataResponse.data.count) " +
            "cloudflareBlocked=\(cloudflareBlocked) " +
            "hasChapterLinks=\(html.contains("/cn/chapters/"))"
        )
        #endif

        if cloudflareBlocked {
            throw RuleExecutionError.antiBot(url: url.absoluteString)
        }

        return html
    }

    /// 中文注释：RSS/XML 需要保留服务器原始 bytes，避免先按错误字符串编码解码造成乱码。
    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        let urlRequest: URLRequest = self.urlRequest(for: url, request: request)
        let dataResponse: HTTPDataResponse
        do {
            dataResponse = try await self.performDataRequest(urlRequest)
        } catch {
            throw RuleExecutionError.network(
                url: url.absoluteString,
                underlyingDescription: error.localizedDescription
            )
        }

        #if DEBUG
        print(
            "[BrowseCraftNetwork] data url=\(url.absoluteString) " +
            "requestScope=\(request?.scope?.rawValue ?? "default") " +
            "bytes=\(dataResponse.data.count)"
        )
        #endif

        return dataResponse.data
    }

    /// 中文注释：RSS/API 等原始 bytes 请求也复用 callback bridge，继续保留 Alamofire 的请求能力。
    private func performDataRequest(_ urlRequest: URLRequest) async throws -> HTTPDataResponse {
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(urlRequest).responseData { response in
                switch response.result {
                case .success(let data):
                    continuation.resume(
                        returning: HTTPDataResponse(
                            data: data,
                            response: response.response
                        )
                    )
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func string(
        from data: Data,
        request: RequestConfig?,
        response: HTTPURLResponse?
    ) -> String {
        let charset: String = request?.charset?.rawValue ?? "auto"
        let requestedEncoding: String.Encoding? = self.stringEncoding(for: charset)
        let responseEncoding: String.Encoding? = response
            .flatMap { self.responseCharset(from: $0) }
            .flatMap { self.stringEncoding(for: $0) }
        let fallbackEncodings: [String.Encoding] = [
            .utf8,
            .shiftJIS,
            .isoLatin1
        ]

        var encodings: [String.Encoding] = []
        if let requestedEncoding: String.Encoding {
            encodings.append(requestedEncoding)
        }
        if let responseEncoding: String.Encoding,
           encodings.contains(responseEncoding) == false {
            encodings.append(responseEncoding)
        }
        for encoding: String.Encoding in fallbackEncodings where encodings.contains(encoding) == false {
            encodings.append(encoding)
        }

        for encoding: String.Encoding in encodings {
            if let string: String = String(data: data, encoding: encoding) {
                return string
            }
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func stringEncoding(for charset: String) -> String.Encoding? {
        let normalizedCharset: String = charset.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedCharset.lowercased() {
        case "utf8", "utf-8":
            return .utf8
        case "shiftjis", "shift-jis", "shift_jis", "sjis":
            return .shiftJIS
        default:
            let encoding: CFStringEncoding = CFStringConvertIANACharSetNameToEncoding(normalizedCharset as CFString)
            guard encoding != kCFStringEncodingInvalidId else {
                return nil
            }

            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        }
    }

    private func responseCharset(from response: HTTPURLResponse) -> String? {
        if let textEncodingName: String = response.textEncodingName?.trimmingCharacters(in: .whitespacesAndNewlines),
           textEncodingName.isEmpty == false {
            return textEncodingName
        }

        guard let contentType: String = response.value(forHTTPHeaderField: "Content-Type") else {
            return nil
        }

        return contentType
            .split(separator: ";")
            .map { part in String(part).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { part in part.lowercased().hasPrefix("charset=") }?
            .dropFirst("charset=".count)
            .description
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
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
