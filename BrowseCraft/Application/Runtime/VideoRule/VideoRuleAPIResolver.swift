import CoreFoundation
import Foundation
import BrowseCraftCore

// 中文注释：Video V2 API 只使用显式 responsePolicy，不共享漫画 legacy code/error 推断。
enum VideoRuleJSONPathState: String, Equatable {
    case missing
    case null
    case typeMismatch
    case empty
    case nonEmpty
}

struct VideoRuleJSONArrayResolution {
    let state: VideoRuleJSONPathState
    let values: [Any]
}

struct VideoRuleJSONObjectResolution {
    let state: VideoRuleJSONPathState
    let value: [String: Any]?
}

enum VideoRuleAPIResponseEvaluation: Equatable {
    case allowParsing
    case businessFailure(message: String)
}

enum VideoRuleAPIResolverError: LocalizedError {
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

struct VideoRuleAPIResolver {
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
                throw VideoRuleAPIResolverError.unsupportedTemplateToken(token)
            }
            guard let replacement: String = self.templateValue(token, context: context) else {
                throw VideoRuleAPIResolverError.unresolvedTemplateToken(token)
            }
            output.replaceSubrange(outputRange, with: replacement)
        }
        return output
    }

    static func arrayResolution(
        at path: String,
        in object: Any
    ) -> VideoRuleJSONArrayResolution {
        if path == "$[]" {
            return self.rootArrayResolution(object)
        }
        if path == "$" {
            return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
        }

        let segments: [(key: String, expandsArray: Bool)] = self.pathSegments(path)
        guard segments.isEmpty == false else {
            return VideoRuleJSONArrayResolution(state: .missing, values: [])
        }
        var values: [Any] = [object]
        var expandedArray: Bool = false

        for segment in segments {
            var nextValues: [Any] = []
            var encounteredEmptyArray: Bool = false
            for value in values {
                if value is NSNull {
                    return VideoRuleJSONArrayResolution(state: .null, values: [])
                }
                guard let dictionary: [String: Any] = value as? [String: Any] else {
                    return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
                }
                guard let child: Any = dictionary[segment.key] else {
                    return VideoRuleJSONArrayResolution(state: .missing, values: [])
                }
                if child is NSNull {
                    return VideoRuleJSONArrayResolution(state: .null, values: [])
                }
                if segment.expandsArray {
                    guard let array: [Any] = child as? [Any] else {
                        return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
                    }
                    expandedArray = true
                    encounteredEmptyArray = encounteredEmptyArray || array.isEmpty
                    nextValues.append(contentsOf: array)
                } else {
                    nextValues.append(child)
                }
            }
            if nextValues.isEmpty, encounteredEmptyArray {
                return VideoRuleJSONArrayResolution(state: .empty, values: [])
            }
            values = nextValues
        }

        guard expandedArray else {
            return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
        }
        return VideoRuleJSONArrayResolution(
            state: values.isEmpty ? .empty : .nonEmpty,
            values: values
        )
    }

    static func objectResolution(
        at path: String,
        in object: Any
    ) -> VideoRuleJSONObjectResolution {
        if path == "$" {
            return self.objectResolution(value: object)
        }
        if path == "$[]" {
            return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
        }

        let values: [Any] = self.jsonValues(at: path, in: object)
        if values.isEmpty {
            return self.missingObjectResolution(at: path, in: object)
        }
        guard values.count == 1 else {
            return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
        }
        return self.objectResolution(value: values[0])
    }

    static func firstJSONValue(at path: String, in object: Any) -> Any? {
        return self.jsonValues(at: path, in: object).first
    }

    static func jsonValues(at path: String, in object: Any) -> [Any] {
        if path == "$" {
            return [object]
        }
        if path == "$[]" {
            return object as? [Any] ?? []
        }
        let segments: [(key: String, expandsArray: Bool)] = self.pathSegments(path)
        guard segments.isEmpty == false else {
            return []
        }
        return segments.reduce([object]) { values, segment in
            return values.flatMap { value -> [Any] in
                guard let dictionary: [String: Any] = value as? [String: Any],
                      let child: Any = dictionary[segment.key],
                      (child is NSNull) == false else {
                    return []
                }
                if segment.expandsArray {
                    return child as? [Any] ?? []
                }
                return [child]
            }
        }
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    static func responseScalar(_ value: Any?) -> APIResponseScalar? {
        if let string: String = value as? String {
            return .string(string)
        }
        if let number: NSNumber = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        return nil
    }

    static func absoluteHTTPURL(_ value: String?, relativeTo baseURL: URL) -> URL? {
        guard let value: String = self.nonEmpty(value),
              let url: URL = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    static func canonicalURLKey(_ url: URL) -> String {
        guard var components: URLComponents = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    static func sorted<T>(
        _ values: [(offset: Int, value: T, order: Double?)],
        sort: VideoEpisodeSort?
    ) -> [T] {
        guard let sort: VideoEpisodeSort, sort != .source else {
            return values.map(\.value)
        }
        return values.sorted { lhs, rhs in
            switch (lhs.order, rhs.order) {
            case let (left?, right?):
                if left == right {
                    return lhs.offset < rhs.offset
                }
                return sort == .ascending ? left < right : left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.value)
    }

    static func evaluateResponse(
        json: Any,
        policy: APIResponsePolicy
    ) -> VideoRuleAPIResponseEvaluation {
        switch policy.mode {
        case .transportOnly:
            return .allowParsing
        case .envelope:
            if let failurePath: String = self.firstMatchedFailurePath(
                policy.failurePaths ?? [],
                object: json
            ) {
                let message: String = self.declaredMessage(
                    in: json,
                    paths: policy.messagePaths
                ) ?? "API response matched failure path \(failurePath)"
                return .businessFailure(message: message)
            }
            guard let statusPath: String = self.nonEmpty(policy.businessStatusPath) else {
                return .allowParsing
            }
            guard let status: APIResponseScalar = self.responseScalar(
                self.firstJSONValue(at: statusPath, in: json)
            ) else {
                let message: String = self.declaredMessage(
                    in: json,
                    paths: policy.messagePaths
                ) ?? "API response is missing business status at \(statusPath)"
                return .businessFailure(message: message)
            }
            guard (policy.successValues ?? []).contains(status) else {
                let message: String = self.declaredMessage(
                    in: json,
                    paths: policy.messagePaths
                ) ?? "API response rejected business status at \(statusPath)"
                return .businessFailure(message: message)
            }
            return .allowParsing
        }
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

    private static func rootArrayResolution(_ object: Any) -> VideoRuleJSONArrayResolution {
        if object is NSNull {
            return VideoRuleJSONArrayResolution(state: .null, values: [])
        }
        guard let array: [Any] = object as? [Any] else {
            return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
        }
        return VideoRuleJSONArrayResolution(
            state: array.isEmpty ? .empty : .nonEmpty,
            values: array
        )
    }

    private static func objectResolution(value: Any) -> VideoRuleJSONObjectResolution {
        if value is NSNull {
            return VideoRuleJSONObjectResolution(state: .null, value: nil)
        }
        guard let dictionary: [String: Any] = value as? [String: Any] else {
            return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
        }
        return VideoRuleJSONObjectResolution(
            state: dictionary.isEmpty ? .empty : .nonEmpty,
            value: dictionary
        )
    }

    private static func missingObjectResolution(
        at path: String,
        in object: Any
    ) -> VideoRuleJSONObjectResolution {
        var current: Any = object
        for segment in self.pathSegments(path) {
            if current is NSNull {
                return VideoRuleJSONObjectResolution(state: .null, value: nil)
            }
            guard segment.expandsArray == false,
                  let dictionary: [String: Any] = current as? [String: Any] else {
                return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
            }
            guard let child: Any = dictionary[segment.key] else {
                return VideoRuleJSONObjectResolution(state: .missing, value: nil)
            }
            current = child
        }
        return self.objectResolution(value: current)
    }

    private static func pathSegments(_ path: String) -> [(key: String, expandsArray: Bool)] {
        return path.split(separator: ".", omittingEmptySubsequences: false).compactMap { raw in
            let segment: String = String(raw)
            guard segment.isEmpty == false else {
                return nil
            }
            if segment.hasSuffix("[]") {
                return (String(segment.dropLast(2)), true)
            }
            return (segment, false)
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
                return self.stringValue(
                    self.firstJSONValue(
                        at: String(token.dropFirst("root.".count)),
                        in: rootJSON
                    )
                )
            }
            if token.hasPrefix("current."), let currentJSON: Any = context.currentJSON {
                return self.stringValue(
                    self.firstJSONValue(
                        at: String(token.dropFirst("current.".count)),
                        in: currentJSON
                    )
                )
            }
            if token.hasPrefix("group."), let groupJSON: Any = context.groupJSON {
                return self.stringValue(
                    self.firstJSONValue(
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

    private static func firstMatchedFailurePath(
        _ paths: [String],
        object: Any
    ) -> String? {
        for rawPath: String in paths {
            guard let path: String = self.nonEmpty(rawPath) else {
                continue
            }
            if self.jsonValues(at: path, in: object).contains(where: self.hasFailureMeaning) {
                return path
            }
        }
        return nil
    }

    private static func hasFailureMeaning(_ value: Any) -> Bool {
        if value is NSNull {
            return false
        }
        if let string: String = value as? String {
            return self.nonEmpty(string) != nil
        }
        if let array: [Any] = value as? [Any] {
            return array.isEmpty == false
        }
        if let dictionary: [String: Any] = value as? [String: Any] {
            return dictionary.isEmpty == false
        }
        if let number: NSNumber = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return number.doubleValue != 0
        }
        return true
    }

    private static func declaredMessage(
        in object: Any,
        paths: [String]?
    ) -> String? {
        for rawPath: String in paths ?? [] {
            guard let path: String = self.nonEmpty(rawPath) else {
                continue
            }
            let messages: [String] = self.jsonValues(at: path, in: object).compactMap { value in
                return self.nonEmpty(self.stringValue(value))
            }
            if messages.isEmpty == false {
                return messages.joined(separator: "; ")
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized: String? = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
