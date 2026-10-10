import Alamofire
import BrowseCraftCore
import BrowseCraftDomain
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
    private let managedAPIURLMatcher: @Sendable (URL) -> Bool

    init(
        credentialProvider: SourceCredentialProviding = EmptySourceCredentialProvider(),
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding = EmptyBrowserRequestHeaderProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        managedAPIURLMatcher: @escaping @Sendable (URL) -> Bool = { _ in false }
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
        let urlRequest: URLRequest = self.urlRequest(
            for: url,
            request: requestConfig,
            context: context,
            cachePolicy: request.cachePolicy
        )
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

        let cloudflareBlocked: Bool = Self.isAntiBotHTML(html)
        let statusCode: Int? = dataResponse.response?.statusCode

        AppLog.debug(
            .network,
            event: "content-loaded",
            metadata: [
                "url": AppLog.safeURL(url),
                "requestScope": requestConfig?.scope?.rawValue ?? "default",
                "purpose": context?.purpose.rawValue ?? "none",
                "needsWebView": requestConfig?.needsWebView?.description ?? "nil",
                "bytes": String(dataResponse.data.count),
                "antiBot": cloudflareBlocked.description,
                "status": statusCode.map(String.init) ?? "nil"
            ]
        )

        if let failure: RuleExecutionError = Self.contentFailure(statusCode: statusCode, html: html, url: url) {
            throw failure
        }

        return PageContentResponse(
            content: html,
            finalURL: dataResponse.response?.url ?? url
        )
    }

    /// 中文注释：XML/JSON 等需要保留服务器原始 bytes，避免先按错误字符串编码解码造成乱码。
    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        let url: URL = request.url
        let requestConfig: RequestConfig? = request.requestConfig
        let context: SourceRequestContext? = request.sourceContext
        let urlRequest: URLRequest = self.urlRequest(
            for: url,
            request: requestConfig,
            context: context,
            cachePolicy: request.cachePolicy
        )
        let dataResponse: HTTPDataResponse
        do {
            dataResponse = try await self.performDataRequest(urlRequest)
        } catch {
            throw RuleExecutionError.network(
                url: url.absoluteString,
                underlyingDescription: error.localizedDescription
            )
        }

        AppLog.debug(
            .network,
            event: "data-loaded",
            metadata: [
                "url": AppLog.safeURL(url),
                "requestScope": requestConfig?.scope?.rawValue ?? "default",
                "purpose": context?.purpose.rawValue ?? "none",
                "headersMode": self.headersMode(for: url, request: requestConfig),
                "contentType": dataResponse.response?.value(forHTTPHeaderField: "Content-Type") ?? "nil",
                "bytes": String(dataResponse.data.count)
            ]
        )

        if self.isAntiBotData(dataResponse.data) {
            throw RuleExecutionError.antiBot(url: url.absoluteString)
        }

        return PageDataResponse(
            data: dataResponse.data,
            finalURL: dataResponse.response?.url ?? url
        )
    }

    /// 中文注释：BC-BOOK-050 模拟器逮到：sfacg 把 `https://book.sfacg.com/Novel/N/` 302 到 **http://** 的移动站再 301 回 https，
    /// URLSession 在 http 那一跳被 ATS 拒（规则生成引擎的 HTTP 客户端无 ATS、跟得过去）。与有声书 mp3 的处置同一纪律：
    /// 客户端里把跳转目标的 http 升成 https（站点本就在 https 上服务），不开全局 ATS 例外。
    static let httpsUpgradingRedirector: Redirector = Redirector(behavior: .modify { _, request, _ in
        guard let url: URL = request.url, let upgraded: URL = AlamofireHTTPClient.httpsUpgraded(url) else {
            return request
        }
        var redirected: URLRequest = request
        redirected.url = upgraded
        return redirected
    })

    /// 中文注释：`http://` 地址升成 `https://`；本来就是 https 或不是 http(s) 即 nil（原样跟随）。
    static func httpsUpgraded(_ url: URL) -> URL? {
        HTTPSUpgrade.upgraded(url)
    }

    /// 中文注释：API 等原始 bytes 请求也复用 callback bridge，继续保留 Alamofire 的请求能力。
    private func performDataRequest(_ urlRequest: URLRequest) async throws -> HTTPDataResponse {
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(urlRequest).redirect(using: Self.httpsUpgradingRedirector).responseData { response in
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
        // 中文注释：`BC-ACQ-076`——响应头编码名按与引擎、Core 同一张表归并（big5 系 → Big5-HKSCS、gbk 系 → GB18030）；
        // 规则与响应头都没给出编码时，按 BOM → `<meta charset>` 读页面自述编码（与引擎同一顺序）。
        let responseEncoding: String.Encoding? = response
            .flatMap { self.responseCharset(from: $0) }
            .flatMap { HTMLTextEncoding.encoding(forLabel: $0) }
        let sniffedEncoding: String.Encoding? = (requestedEncoding ?? responseEncoding) == nil
            ? HTMLTextEncoding.sniffedEncoding(data)
            : nil
        let primaryEncoding: String.Encoding? = requestedEncoding ?? responseEncoding ?? sniffedEncoding
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
        if let sniffedEncoding: String.Encoding,
           encodings.contains(sniffedEncoding) == false {
            encodings.append(sniffedEncoding)
        }
        for encoding: String.Encoding in fallbackEncodings where encodings.contains(encoding) == false {
            encodings.append(encoding)
        }

        for encoding: String.Encoding in encodings {
            if let string: String = String(data: data, encoding: encoding) {
                return string
            }
            // 中文注释：`BC-ACQ-075`——声明的是 UTF-8（规则字符集或响应头）却有坏字节时，按 UTF-8 宽松解码
            // （坏字节换成替换字符），与浏览器、引擎一致；不再往后落到 Latin-1 把整页中文解成乱码。
            // `BC-ACQ-076`：页面自述的其它编码（big5 / gb18030 …）有坏字节时同此，宽松解码、不往后试。
            if encoding == primaryEncoding,
               let string: String = HTMLTextEncoding.lossyDecode(data, encoding: encoding) {
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
        context: SourceRequestContext?,
        cachePolicy: URLRequest.CachePolicy
    ) -> URLRequest {
        // 中文注释：初始地址是 http:// 时同样升成 https://——跳转目标早已这样处理（`httpsUpgradingRedirector`），
        // 初始请求却原样发出、被 ATS 当场拒绝（2026-09-21 sfacg 列表页抽出的作品地址是 `http://manhua.sfacg.com/...`，
        // 站点 301 到 https；规则生成引擎的采集端同样先升级再取，两端到达同一页面）。不开全局 ATS 例外。
        let url: URL = Self.httpsUpgraded(url) ?? url
        var urlRequest: URLRequest = URLRequest(url: url, cachePolicy: cachePolicy)
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
            AppDebugLog.write(
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
        AppDebugLog.write(
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

    /// 中文注释：`BCA-RUNTIME-007`——HTML 直接请求的失败判定，与 App 预检同口径（`BC-PREFLIGHT-062` / `063`）：
    /// 挑战页先认（任何状态码都抛 `antiBot`，交 `BCA-RUNTIME-005` 回退 WebView）；其余状态码 ≥ 400 抛 `httpStatus`，
    /// 拒绝页正文不交给规则解析（xjortho 403 曾被报成「规则解析出错」）。200..<400 与拿不到状态码时返回 nil、照旧解析。
    static func contentFailure(statusCode: Int?, html: String, url: URL) -> RuleExecutionError? {
        if Self.isAntiBotHTML(html) {
            return .antiBot(url: url.absoluteString)
        }
        if let statusCode: Int, statusCode >= 400 {
            return .httpStatus(url: url.absoluteString, statusCode: statusCode)
        }
        return nil
    }

    private func isAntiBotData(_ data: Data) -> Bool {
        let text: String
        if let string: String = String(data: data.prefix(8_192), encoding: .utf8) {
            text = string
        } else {
            text = String(decoding: data.prefix(8_192), as: UTF8.self)
        }

        return Self.isAntiBotHTML(text)
    }

    private static func isAntiBotHTML(_ html: String) -> Bool {
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
