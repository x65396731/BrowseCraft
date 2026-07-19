import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleAPITemplateResolver 只处理视频 API 请求模板、上下文和请求字段替换。

enum VideoRuleAPITemplateResolverError: LocalizedError {
    case unsupportedTemplateToken(String)
    case unresolvedTemplateToken(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedTemplateToken(let token):
            return "Video V2 API template contains unsupported token: {\(token)}."
        case .unresolvedTemplateToken(let token):
            return "Video V2 API template token has no runtime value: {\(token)}."
        }
    }
}

struct VideoRuleAPITemplateContext {
    let source: Source
    let rule: VideoSiteRule
    let itemReference: SourceItemReference?
    let detailURL: URL?
    let rootJSON: Any?
    let currentJSON: Any?
    let groupJSON: Any?
    let credentialProvider: any SourceCredentialProviding

    init(
        source: Source,
        rule: VideoSiteRule,
        itemReference: SourceItemReference? = nil,
        detailURL: URL? = nil,
        rootJSON: Any? = nil,
        currentJSON: Any? = nil,
        groupJSON: Any? = nil,
        credentialProvider: any SourceCredentialProviding
    ) {
        self.source = source
        self.rule = rule
        self.itemReference = itemReference
        self.detailURL = detailURL
        self.rootJSON = rootJSON
        self.currentJSON = currentJSON
        self.groupJSON = groupJSON
        self.credentialProvider = credentialProvider
    }
}

struct VideoRuleAPITemplateResolver {
    static func resolvedContextValues(
        source: Source,
        rule: VideoSiteRule,
        credentialProvider: any SourceCredentialProviding
    ) -> [String: String] {
        let templateContext = VideoRuleAPITemplateContext(
            source: source,
            rule: rule,
            credentialProvider: credentialProvider
        )
        var values: [String: String] = [:]
        for key: String in (rule.context ?? [:]).keys.sorted() {
            if let value: String = self.contextValue(key, context: templateContext) {
                values[key] = value
            }
        }
        return values
    }

    static func resolvedRequest(
        _ request: RequestConfig?,
        context: VideoRuleAPITemplateContext
    ) throws -> RequestConfig? {
        guard var request: RequestConfig = request else {
            return nil
        }
        if let body: RequestBody = request.body {
            request.body = RequestBody(
                contentType: body.contentType,
                value: try self.resolveTemplate(body.value, context: context)
            )
        }
        request.headers = try self.resolvedHeaders(request.headers, context: context)
        request.imageHeaders = try self.resolvedHeaders(request.imageHeaders, context: context)
        if var imageRequest: ImageRequestConfig = request.imageRequest {
            imageRequest.headers = try self.resolvedHeaders(
                imageRequest.headers,
                context: context
            )
            request.imageRequest = imageRequest
        }
        return request
    }

    static func resolveTemplate(
        _ template: String,
        context: VideoRuleAPITemplateContext
    ) throws -> String {
        let pattern: String = #"\{([^{}]+)\}"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return template
        }
        var output: String = template
        let matches: [NSTextCheckingResult] = regex.matches(
            in: template,
            range: NSRange(template.startIndex..<template.endIndex, in: template)
        )
        for match: NSTextCheckingResult in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let tokenRange: Range<String.Index> = Range(match.range(at: 1), in: template),
                  let outputRange: Range<String.Index> = Range(match.range(at: 0), in: output) else {
                continue
            }
            let token: String = String(template[tokenRange])
            guard self.looksLikeTemplateToken(token) else {
                continue
            }
            guard self.supportsTemplateToken(token) else {
                throw VideoRuleAPITemplateResolverError.unsupportedTemplateToken(token)
            }
            guard let replacement: String = self.templateValue(token, context: context) else {
                throw VideoRuleAPITemplateResolverError.unresolvedTemplateToken(token)
            }
            output.replaceSubrange(outputRange, with: replacement)
        }
        return output
    }

    private static func resolvedHeaders(
        _ headers: [String: String]?,
        context: VideoRuleAPITemplateContext
    ) throws -> [String: String]? {
        guard let headers: [String: String] else {
            return nil
        }
        return try headers.reduce(into: [String: String]()) { output, pair in
            output[pair.key] = try self.resolveTemplate(pair.value, context: context)
        }
    }

    private static func looksLikeTemplateToken(_ token: String) -> Bool {
        guard token.isEmpty == false else {
            return false
        }
        let allowed: CharacterSet = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-[]"
        )
        return token.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func supportsTemplateToken(_ token: String) -> Bool {
        let exact: Set<String> = [
            "source.id", "source.baseURL", "item.idCode", "item.title",
            "item.detailURL", "item.coverURL"
        ]
        return exact.contains(token)
            || token.hasPrefix("context.")
            || token.hasPrefix("root.")
            || token.hasPrefix("current.")
            || token.hasPrefix("group.")
    }

    private static func templateValue(
        _ token: String,
        context: VideoRuleAPITemplateContext
    ) -> String? {
        switch token {
        case "source.id":
            return context.source.id
        case "source.baseURL":
            return context.source.baseURL
        case "item.idCode":
            return self.nonEmpty(context.itemReference?.idCode)
        case "item.title":
            return self.nonEmpty(context.itemReference?.title)
        case "item.detailURL":
            return context.itemReference?.detailURL?.absoluteString
                ?? context.detailURL?.absoluteString
        case "item.coverURL":
            return context.itemReference?.coverURL?.absoluteString
        default:
            if token.hasPrefix("context.") {
                return self.contextValue(
                    String(token.dropFirst("context.".count)),
                    context: context
                )
            }
            if token.hasPrefix("root."), let rootJSON: Any = context.rootJSON {
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(
                        at: String(token.dropFirst("root.".count)),
                        in: rootJSON
                    )
                )
            }
            if token.hasPrefix("current."), let currentJSON: Any = context.currentJSON {
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(
                        at: String(token.dropFirst("current.".count)),
                        in: currentJSON
                    )
                )
            }
            if token.hasPrefix("group."), let groupJSON: Any = context.groupJSON {
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(
                        at: String(token.dropFirst("group.".count)),
                        in: groupJSON
                    )
                )
            }
            return nil
        }
    }

    private static func contextValue(
        _ key: String,
        context: VideoRuleAPITemplateContext
    ) -> String? {
        guard let value: SiteRuleContextValue = context.rule.context?[key] else {
            return nil
        }
        if let credentialValue: String = self.credentialValue(
            value.userValue,
            sourceID: context.source.id,
            provider: context.credentialProvider
        ) {
            return credentialValue
        }
        for candidate: String? in [value.value, value.anonymousValue, value.`default`] {
            if let candidate: String = self.nonEmpty(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func credentialValue(
        _ rawReference: String?,
        sourceID: String,
        provider: any SourceCredentialProviding
    ) -> String? {
        guard var reference: String = self.nonEmpty(rawReference) else {
            return nil
        }
        if reference.hasPrefix("{") && reference.hasSuffix("}") {
            reference = String(reference.dropFirst().dropLast())
        }
        guard reference.hasPrefix("credentialStore.") else {
            return nil
        }
        let keyPath: String = String(reference.dropFirst("credentialStore.".count))
        if keyPath == "accessToken" || keyPath == "refreshToken" {
            return provider.token(for: sourceID, key: keyPath)
        }
        if keyPath.hasPrefix("localStorage.") {
            return provider.storageValue(
                for: sourceID,
                storage: .localStorage,
                key: String(keyPath.dropFirst("localStorage.".count))
            )
        }
        if keyPath.hasPrefix("sessionStorage.") {
            return provider.storageValue(
                for: sourceID,
                storage: .sessionStorage,
                key: String(keyPath.dropFirst("sessionStorage.".count))
            )
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized: String? = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
