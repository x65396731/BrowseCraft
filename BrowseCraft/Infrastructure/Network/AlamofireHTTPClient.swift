import Alamofire
import Foundation

// 中文注释：AlamofireHTTPClient.swift 属于网络实现层，用于说明本文件承载的核心职责。

private struct HTTPDataResponse {
    let data: Data
    let response: HTTPURLResponse?
}

/// 中文注释：生产环境使用的 HTTP 客户端，底层由 Alamofire 实现。
final class AlamofireHTTPClient: PageContentLoader, PageDataLoader {
    private let credentialProvider: SourceCredentialProviding
    private let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let managedAPIURLMatcher: (URL) -> Bool

    init(
        credentialProvider: SourceCredentialProviding = EmptySourceCredentialProvider(),
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding = EmptyBrowserRequestHeaderProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        managedAPIURLMatcher: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.credentialProvider = credentialProvider
        self.browserRequestHeaderProvider = browserRequestHeaderProvider
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.managedAPIURLMatcher = managedAPIURLMatcher
    }

    /// 中文注释：把 V2 RequestConfig 合入默认 HTML 请求头，并通过 CookieHeaderResolver 应用 Cookie 策略。
    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        let url: URL = request.url
        let requestConfig: RequestConfig? = request.requestConfig
        let context: SourceRequestContext? = request.sourceContext
        let urlRequest: URLRequest = self.urlRequest(for: url, request: requestConfig, context: context)
        let dataResponse: HTTPDataResponse
        let html: String
        do {
            dataResponse = try await self.performDataRequest(urlRequest)
            html = self.string(from: dataResponse.data, request: requestConfig, response: dataResponse.response)
        } catch {
            throw RuleExecutionError.network(
                url: url.absoluteString,
                underlyingDescription: error.localizedDescription
            )
        }

        let cloudflareBlocked: Bool = self.isAntiBotHTML(html)

        #if DEBUG
        print(
            "[BrowseCraftNetwork] url=\(url.absoluteString) " +
            "requestScope=\(requestConfig?.scope?.rawValue ?? "default") " +
            "purpose=\(context?.purpose.rawValue ?? "none") " +
            "needsWebView=\(requestConfig?.needsWebView?.description ?? "nil") " +
            "bytes=\(dataResponse.data.count) " +
            "cloudflareBlocked=\(cloudflareBlocked) " +
            "hasChapterLinks=\(html.contains("/cn/chapters/"))"
        )
        #endif

        if cloudflareBlocked {
            throw RuleExecutionError.antiBot(url: url.absoluteString)
        }

        return PageContentResponse(
            content: html,
            finalURL: dataResponse.response?.url ?? url
        )
    }

    /// 中文注释：RSS/XML 需要保留服务器原始 bytes，避免先按错误字符串编码解码造成乱码。
    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        let url: URL = request.url
        let requestConfig: RequestConfig? = request.requestConfig
        let context: SourceRequestContext? = request.sourceContext
        let urlRequest: URLRequest = self.urlRequest(for: url, request: requestConfig, context: context)
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
            "requestScope=\(requestConfig?.scope?.rawValue ?? "default") " +
            "purpose=\(context?.purpose.rawValue ?? "none") " +
            "headersMode=\(self.headersMode(for: url, request: requestConfig)) " +
            "accept=\(urlRequest.value(forHTTPHeaderField: "Accept") ?? "nil") " +
            "contentType=\(dataResponse.response?.value(forHTTPHeaderField: "Content-Type") ?? "nil") " +
            "bytes=\(dataResponse.data.count) " +
            "preview=\(Self.debugPreview(from: dataResponse.data, url: url, purpose: context?.purpose))"
        )
        #endif

        if self.isAntiBotData(dataResponse.data) {
            throw RuleExecutionError.antiBot(url: url.absoluteString)
        }

        return PageDataResponse(
            data: dataResponse.data,
            finalURL: dataResponse.response?.url ?? url
        )
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
    private func urlRequest(
        for url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) -> URLRequest {
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = request?.method?.rawValue ?? "GET"

        let explicitHeadersOnly: Bool = self.usesExplicitHeadersOnly(url: url, request: request)
        var headers: [String: String] = explicitHeadersOnly
            ? request?.headers ?? [:]
            : self.browserRequestHeaderProvider.defaultHeaders(for: url)
        if explicitHeadersOnly == false {
            headers = RequestHeaderFields.applyingOverrides(request?.headers, to: headers)
        }
        if let context: SourceRequestContext {
            headers = self.headersByFillingMissingCredentialHeaders(
                to: headers,
                url: url,
                context: context
            )
            headers = RequestHeaderFields.applyingOverrides(context.additionalHeaders, to: headers)
        }
        let credentialCookieHeader: String? = context.flatMap {
            self.credentialProvider.cookieHeader(for: $0, url: url)
        }
        let hadCustomCookieHeader: Bool = RequestHeaderFields.containsHeader("Cookie", in: headers)
        headers = CookieHeaderResolver.headersByApplyingPageCookies(
            to: headers,
            url: url,
            request: request,
            browserCookieHeader: self.systemCookieHeaderProvider.cookieHeader(for: url),
            credentialCookieHeader: credentialCookieHeader
        )
        if let context: SourceRequestContext {
            #if DEBUG
            print(
                "[BrowseCraftCredential] request context " +
                "sourceID=\(context.sourceID ?? "nil") " +
                "purpose=\(context.purpose.rawValue) " +
                "host=\(url.host ?? "nil") " +
                "credentialCookie=\((credentialCookieHeader != nil).description) " +
                "customCookie=\(hadCustomCookieHeader.description) " +
                "finalCookie=\(RequestHeaderFields.containsHeader("Cookie", in: headers).description) " +
                "headerCount=\(headers.count)"
            )
            #endif
        }

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

    /// 中文注释：凭证 header 只补缺，不覆盖规则 RequestConfig 或默认浏览器模拟 header。
    private func headersByFillingMissingCredentialHeaders(
        to headers: [String: String],
        url: URL,
        context: SourceRequestContext
    ) -> [String: String] {
        let credentialHeaders: [String: String] = self.credentialProvider.headerOverrides(for: context, url: url)
        guard credentialHeaders.isEmpty == false else {
            return headers
        }

        var resolvedHeaders: [String: String] = headers
        var filledHeaderNames: [String] = []
        var skippedHeaderNames: [String] = []
        credentialHeaders.forEach { key, value in
            guard RequestHeaderFields.containsHeader(key, in: resolvedHeaders) == false else {
                skippedHeaderNames.append(key)
                return
            }
            resolvedHeaders[key] = value
            filledHeaderNames.append(key)
        }

        #if DEBUG
        print(
            "[BrowseCraftCredential] fill headers " +
            "sourceID=\(context.sourceID ?? "nil") " +
            "purpose=\(context.purpose.rawValue) " +
            "host=\(url.host ?? "nil") " +
            "filled=\(filledHeaderNames.joined(separator: ",")) " +
            "skippedExisting=\(skippedHeaderNames.joined(separator: ","))"
        )
        #endif

        return resolvedHeaders
    }

    private func usesExplicitHeadersOnly(url: URL, request: RequestConfig?) -> Bool {
        return self.managedAPIURLMatcher(url)
            || request?.mergePolicy == .override
    }

    private func headersMode(for url: URL, request: RequestConfig?) -> String {
        return self.usesExplicitHeadersOnly(url: url, request: request) ? "explicit" : "browser"
    }

    static func debugPreview(
        from data: Data,
        url: URL,
        purpose: SourceRequestPurpose?
    ) -> String {
        if purpose == .protectedResource {
            return "redacted-protected-resource"
        }

        if Self.shouldRedactDebugPreview(for: url) {
            return "redacted-catalog-api"
        }

        let raw: String
        if let string: String = String(data: data.prefix(160), encoding: .utf8) {
            raw = string
        } else {
            raw = String(decoding: data.prefix(160), as: UTF8.self)
        }

        return raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldRedactDebugPreview(for url: URL) -> Bool {
        return PortalAPIConfiguration.isManagedAPIURL(url)
            && url.path == "/catalog/sources"
    }

    private func isAntiBotData(_ data: Data) -> Bool {
        let text: String
        if let string: String = String(data: data.prefix(8_192), encoding: .utf8) {
            text = string
        } else {
            text = String(decoding: data.prefix(8_192), as: UTF8.self)
        }

        return self.isAntiBotHTML(text)
    }

    private func isAntiBotHTML(_ html: String) -> Bool {
        let blockingMarkers: [String] = [
            "Attention Required",
            "Just a moment",
            "cf-error-details"
        ]
        if blockingMarkers.contains(where: html.localizedCaseInsensitiveContains) {
            return true
        }

        let hasChallengePlatform: Bool = html.localizedCaseInsensitiveContains("challenge-platform")
        guard hasChallengePlatform else {
            return false
        }

        // Cloudflare may inject its challenge-platform script into an otherwise complete page.
        // Require an actual challenge state or prompt before classifying the response as blocked.
        let challengeEvidence: [String] = [
            "_cf_chl_opt",
            "cf-chl-widget",
            "challenge-form",
            "cf-turnstile",
            "Checking your browser",
            "Verify you are human",
            "Enable JavaScript and cookies to continue"
        ]
        return challengeEvidence.contains(where: html.localizedCaseInsensitiveContains)
    }
}
