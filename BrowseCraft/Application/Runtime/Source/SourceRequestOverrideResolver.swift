import Foundation
import BrowseCraftCore

// 中文注释：SourceRequestOverrideResolver 只负责把运行时 override 转成 RequestConfig；
// Site/Page/Rule/API 的字段合并语义继续唯一归 Core RequestConfigResolver 所有。
struct SourceRequestOverrideResolver {
    private let requestConfigResolver: RequestConfigResolver

    init(requestConfigResolver: RequestConfigResolver = RequestConfigResolver()) {
        self.requestConfigResolver = requestConfigResolver
    }

    func resolve(
        base: RequestConfig?,
        override: SourceRequestOverride?
    ) -> RequestConfig? {
        return self.requestConfigResolver.merged(
            base: base,
            override: self.requestConfig(from: override)
        )
    }

    private func requestConfig(from override: SourceRequestOverride?) -> RequestConfig? {
        guard let override: SourceRequestOverride else {
            return nil
        }

        let method: HTTPMethod? = self.httpMethod(from: override.method)
        let headers: [String: String]? = override.headers.isEmpty ? nil : override.headers
        let body: RequestBody? = override.body.map { value in
            return RequestBody(value: value)
        }
        let cookiePolicy: CookiePolicy? = self.cookiePolicy(from: override.cookiePolicy)
        let charset: Charset? = self.charset(from: override.charset)
        let hasRequestOverride: Bool = method != nil
            || headers != nil
            || body != nil
            || cookiePolicy != nil
            || override.requiresWebView != nil
            || override.autoScroll != nil
            || charset != nil
        guard hasRequestOverride else {
            return nil
        }

        return RequestConfig(
            method: method,
            headers: headers,
            body: body,
            cookiePolicy: cookiePolicy,
            charset: charset,
            needsWebView: override.requiresWebView,
            autoScroll: override.autoScroll
        )
    }

    private func httpMethod(from value: String?) -> HTTPMethod? {
        guard let normalized: String = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              normalized.isEmpty == false else {
            return nil
        }

        return HTTPMethod(rawValue: normalized)
    }

    private func charset(from value: String?) -> Charset? {
        guard let normalized: String = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              normalized.isEmpty == false else {
            return nil
        }

        return Charset(rawValue: normalized)
    }

    private func cookiePolicy(from value: SourceRequestCookiePolicy?) -> CookiePolicy? {
        switch value {
        case .some(.none):
            return .none
        case .some(.read), .some(.write), .some(.readWrite):
            return .browser
        case nil:
            return nil
        }
    }
}
