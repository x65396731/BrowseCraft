import Foundation

// 中文注释：API 请求会叠加站点/页面请求和 API 专属请求，避免固定头被局部 request 覆盖丢失。
enum ComicRuleAPIRequestResolver {
    static func request(
        base baseRequest: RequestConfig?,
        override overrideRequest: RequestConfig?,
        source: Source,
        item: ContentItem,
        page: Int? = nil,
        chapterURL: String? = nil
    ) -> RequestConfig? {
        guard let mergedRequest: RequestConfig = self.merged(base: baseRequest, override: overrideRequest) else {
            return nil
        }

        return ComicRuleAPIResolver.request(
            from: mergedRequest,
            source: source,
            item: item,
            chapterURL: chapterURL,
            page: page
        )
    }

    private static func merged(base baseRequest: RequestConfig?, override overrideRequest: RequestConfig?) -> RequestConfig? {
        guard let overrideRequest: RequestConfig else {
            return baseRequest
        }
        guard let baseRequest: RequestConfig else {
            return overrideRequest
        }
        if overrideRequest.mergePolicy == .override {
            return overrideRequest
        }

        return RequestConfig(
            scope: overrideRequest.scope ?? baseRequest.scope,
            mergePolicy: overrideRequest.mergePolicy ?? baseRequest.mergePolicy,
            method: overrideRequest.method ?? baseRequest.method,
            headers: self.mergedHeaders(base: baseRequest.headers, override: overrideRequest.headers),
            body: overrideRequest.body ?? baseRequest.body,
            cookiePolicy: overrideRequest.cookiePolicy ?? baseRequest.cookiePolicy,
            cookiePriority: overrideRequest.cookiePriority ?? baseRequest.cookiePriority,
            cookieScope: overrideRequest.cookieScope ?? baseRequest.cookieScope,
            charset: overrideRequest.charset ?? baseRequest.charset,
            needsWebView: overrideRequest.needsWebView ?? baseRequest.needsWebView,
            autoScroll: overrideRequest.autoScroll ?? baseRequest.autoScroll,
            imageHeaders: self.mergedHeaders(base: baseRequest.imageHeaders, override: overrideRequest.imageHeaders),
            imageRequest: self.mergedImageRequest(base: baseRequest.imageRequest, override: overrideRequest.imageRequest)
        )
    }

    private static func mergedImageRequest(
        base baseRequest: ImageRequestConfig?,
        override overrideRequest: ImageRequestConfig?
    ) -> ImageRequestConfig? {
        guard let overrideRequest: ImageRequestConfig else {
            return baseRequest
        }
        guard let baseRequest: ImageRequestConfig else {
            return overrideRequest
        }
        if overrideRequest.mergePolicy == .override {
            return overrideRequest
        }

        return ImageRequestConfig(
            headers: self.mergedHeaders(base: baseRequest.headers, override: overrideRequest.headers),
            cookiePolicy: overrideRequest.cookiePolicy ?? baseRequest.cookiePolicy,
            cookiePriority: overrideRequest.cookiePriority ?? baseRequest.cookiePriority,
            cookieScope: overrideRequest.cookieScope ?? baseRequest.cookieScope,
            mergePolicy: overrideRequest.mergePolicy ?? baseRequest.mergePolicy
        )
    }

    private static func mergedHeaders(base baseHeaders: [String: String]?, override overrideHeaders: [String: String]?) -> [String: String]? {
        guard let overrideHeaders: [String: String], overrideHeaders.isEmpty == false else {
            return baseHeaders
        }
        guard let baseHeaders: [String: String], baseHeaders.isEmpty == false else {
            return overrideHeaders
        }

        return BrowserRequestHeaders.applyingOverrides(overrideHeaders, to: baseHeaders)
    }
}
