import BrowseCraftCore
import BrowseCraftDomain
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
        guard let parsedURL: URL = URL(string: urlString) else {
            return nil
        }
        // 中文注释：图片地址是 http:// 时升成 https://，与页面请求同一纪律（ATS 拒绝明文 http，不开全局例外）。
        let url: URL = HTTPSUpgrade.upgraded(parsedURL) ?? parsedURL

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

    /// 中文注释：`BC-CATALOG-022`——图片加载失败必须留下**可区分**的结构化错误。
    /// 在此之前三处 `LazyImage` 的 `state.error` 分支都只换占位图、把 Nuke 的错误整个丢掉，
    /// 于是「请求失败 / 被取消 / 调度问题 / 解码失败」在链路上长得一模一样（都是图片空白），
    /// 2026-08-27 排查 jable 缩略图缺失时就卡在这一格。
    ///
    /// 记的是 `BC-CATALOG-022` 要的那几样：脱敏 host/path、Nuke 的错误 case 名、
    /// 底层 URLSession 错误的 domain/code，以及是否为取消。
    /// 不记 Nuke 错误自身桥接出的 `NSError` domain/code——那是 Swift enum 的合成值、没有诊断价值。
    /// **不记 query**（可能带签名或 token）、不记请求头、不记 Cookie。
    ///
    /// 分类器 `RuleExecutionErrorClassifier` 住在 Application 层，而本文件在 Shared、
    /// 不得反向引用（见该文件头注释），因此这里不经它——而 `BC-CATALOG-022` 要的本来就是
    /// **Nuke/URLSession 的**类别与错误码，不是 `RuleExecutionError` 的类别。
    ///
    /// 已知边界：`RuleExecutionLogger` 是 `#if DEBUG`，本事件在 Release 构建下不产生输出；
    /// 这是既有诊断通路的性质，本条未改动它。合同里的「缓存来源」一格不在失败事件里
    /// （失败时没有 `ImageResponse.cacheType`），留在本条未做的那一半。
    static func logFailure(urlString: String?, error: Error, event: String) {
        let url: URL? = urlString.flatMap(URL.init(string:))
        let underlyingError: NSError? = Self.underlyingError(of: error).map { $0 as NSError }

        RuleExecutionLogger.log(
            stage: .image,
            event: event,
            fields: [
                "urlHost": url?.host ?? "nil",
                "urlPath": url?.path ?? "nil",
                "errorCase": Self.errorCaseName(error),
                "underlyingDomain": underlyingError?.domain,
                "underlyingCode": underlyingError?.code,
                "isCancelled": underlyingError.map(Self.isCancellation) ?? false
            ]
        )
    }

    /// 中文注释：case 名只能显式映射，**不能用 `String(describing:)`**——`ImagePipeline.Error`
    /// 实现了 `CustomStringConvertible`，`String(describing:)` 拿到的是「Failed to load image data.
    /// Underlying error: …」这种整句，既不是 case 名，还可能把底层错误里的地址带进日志，
    /// 而 `BC-CATALOG-022` 明确禁止记录凭据与完整请求内容。
    /// 非 Nuke 错误退回**类型名**（同样不含关联值）。
    private static func errorCaseName(_ error: Error) -> String {
        guard let pipelineError: ImagePipeline.Error = error as? ImagePipeline.Error else {
            return String(describing: type(of: error))
        }

        switch pipelineError {
        case .dataMissingInCache:
            return "dataMissingInCache"
        case .dataLoadingFailed:
            return "dataLoadingFailed"
        case .dataIsEmpty:
            return "dataIsEmpty"
        case .decoderNotRegistered:
            return "decoderNotRegistered"
        case .decodingFailed:
            return "decodingFailed"
        case .processingFailed:
            return "processingFailed"
        case .imageRequestMissing:
            return "imageRequestMissing"
        case .pipelineInvalidated:
            return "pipelineInvalidated"
        @unknown default:
            return "unknown"
        }
    }

    /// 中文注释：底层错误走 Nuke 公开的 `dataLoadingError`，不走 `NSUnderlyingErrorKey`——
    /// Swift enum 桥接成 `NSError` 时 userInfo 里没有它，那条路取到的恒为 nil。
    /// 取到的通常是 `URLError`，`BC-CATALOG-022` 要的 URLSession 错误码即在此。
    private static func underlyingError(of error: Error) -> Error? {
        guard let pipelineError: ImagePipeline.Error = error as? ImagePipeline.Error else {
            return error
        }

        return pipelineError.dataLoadingError
    }

    private static func isCancellation(_ nsError: NSError) -> Bool {
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
