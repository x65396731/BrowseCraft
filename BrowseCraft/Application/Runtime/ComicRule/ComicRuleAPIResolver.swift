import Foundation

// 中文注释：ComicRuleAPIResolver 集中处理 API-backed comic rule 的 JSON path、模板和请求体替换。
struct ComicRuleAPIResolver {
    enum JSONArrayState: Equatable {
        case missing
        case empty
        case nonEmpty
    }

    static func request(
        from request: RequestConfig?,
        source: Source,
        item: ContentItem,
        chapterURL: String? = nil,
        page: Int? = nil,
        rootJSON: Any? = nil,
        currentJSON: Any? = nil
    ) -> RequestConfig? {
        guard var request: RequestConfig = request else {
            return nil
        }

        if let body: RequestBody = request.body {
            request.body = RequestBody(
                contentType: body.contentType,
                value: self.replacingTemplatePlaceholders(
                    in: body.value,
                    source: source,
                    item: item,
                    chapterURL: chapterURL,
                    page: page,
                    rootJSON: rootJSON,
                    currentJSON: currentJSON
                )
            )
        }
        request.headers = self.replacingTemplatePlaceholders(
            in: request.headers,
            source: source,
            item: item,
            chapterURL: chapterURL,
            page: page,
            rootJSON: rootJSON,
            currentJSON: currentJSON
        )
        request.imageHeaders = self.replacingTemplatePlaceholders(
            in: request.imageHeaders,
            source: source,
            item: item,
            chapterURL: chapterURL,
            page: page,
            rootJSON: rootJSON,
            currentJSON: currentJSON
        )
        if var imageRequest: ImageRequestConfig = request.imageRequest {
            imageRequest.headers = self.replacingTemplatePlaceholders(
                in: imageRequest.headers,
                source: source,
                item: item,
                chapterURL: chapterURL,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
            request.imageRequest = imageRequest
        }

        return request
    }

    static func replacingTemplatePlaceholders(
        in template: String,
        source: Source,
        item: ContentItem,
        chapterURL: String? = nil,
        page: Int? = nil,
        rootJSON: Any? = nil,
        currentJSON: Any? = nil
    ) -> String {
        var output: String = template
        let pattern: String = #"\{([^{}]+)\}"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return output
        }

        let matches: [NSTextCheckingResult] = regex.matches(
            in: template,
            range: NSRange(template.startIndex..<template.endIndex, in: template)
        )

        for match: NSTextCheckingResult in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let fullRange: Range<String.Index> = Range(match.range(at: 0), in: output),
                  let tokenRange: Range<String.Index> = Range(match.range(at: 1), in: template) else {
                continue
            }

            let token: String = String(template[tokenRange])
            guard self.isTemplateToken(token) else {
                continue
            }

            let replacement: String = self.templateValue(
                token: token,
                source: source,
                item: item,
                chapterURL: chapterURL,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            ) ?? ""
            output.replaceSubrange(fullRange, with: replacement)
        }

        return output
    }

    static func replacingTemplatePlaceholders(
        in headers: [String: String]?,
        source: Source,
        item: ContentItem,
        chapterURL: String? = nil,
        page: Int? = nil,
        rootJSON: Any? = nil,
        currentJSON: Any? = nil
    ) -> [String: String]? {
        guard let headers: [String: String] else {
            return nil
        }

        var resolvedHeaders: [String: String] = [:]
        headers.forEach { key, value in
            resolvedHeaders[key] = self.replacingTemplatePlaceholders(
                in: value,
                source: source,
                item: item,
                chapterURL: chapterURL,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
        }
        return resolvedHeaders
    }

    private static func isTemplateToken(_ token: String) -> Bool {
        guard token.isEmpty == false else {
            return false
        }

        let allowedCharacters: CharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")
        return token.unicodeScalars.allSatisfy { scalar in
            return allowedCharacters.contains(scalar)
        }
    }

    static func firstJSONValue(at path: String, in object: Any) -> Any? {
        return self.jsonValues(at: path, in: object).first
    }

    static func jsonValues(at path: String, in object: Any) -> [Any] {
        let segments: [String] = path
            .split(separator: ".")
            .map(String.init)
            .filter { segment in segment.isEmpty == false }

        return segments.reduce([object]) { values, segment in
            let shouldFlattenArray: Bool = segment.hasSuffix("[]")
            let key: String = shouldFlattenArray ? String(segment.dropLast(2)) : segment
            var nextValues: [Any] = []

            for value: Any in values {
                if key.isEmpty {
                    nextValues.append(value)
                } else if let dictionary: [String: Any] = value as? [String: Any],
                          let child: Any = dictionary[key] {
                    nextValues.append(child)
                }
            }

            if shouldFlattenArray {
                return nextValues.flatMap { value in
                    return value as? [Any] ?? []
                }
            }

            return nextValues
        }
    }

    /// 中文注释：区分“规则路径不存在”和“源站确实返回空数组”，账号限制只能由后者触发。
    static func jsonArrayState(at path: String, in object: Any) -> JSONArrayState {
        let segments: [String] = path
            .split(separator: ".")
            .map(String.init)
            .filter { segment in segment.isEmpty == false }
        guard segments.isEmpty == false,
              segments.contains(where: { $0.hasSuffix("[]") }) else {
            return .missing
        }

        var values: [Any] = [object]
        var encounteredArray: Bool = false

        for segment: String in segments {
            let shouldFlattenArray: Bool = segment.hasSuffix("[]")
            let key: String = shouldFlattenArray ? String(segment.dropLast(2)) : segment
            var nextValues: [Any] = []
            var resolvedValueCount: Int = 0

            for value: Any in values {
                let child: Any?
                if key.isEmpty {
                    child = value
                } else {
                    child = (value as? [String: Any])?[key]
                }

                guard let child: Any else {
                    continue
                }
                resolvedValueCount += 1

                if shouldFlattenArray {
                    guard let array: [Any] = child as? [Any] else {
                        return .missing
                    }
                    encounteredArray = true
                    nextValues.append(contentsOf: array)
                } else {
                    nextValues.append(child)
                }
            }

            guard resolvedValueCount > 0 else {
                return encounteredArray && values.isEmpty ? .empty : .missing
            }
            if shouldFlattenArray,
               nextValues.isEmpty {
                return .empty
            }
            values = nextValues
        }

        guard encounteredArray else {
            return .missing
        }
        return values.isEmpty ? .empty : .nonEmpty
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

    static func sortedValues(_ values: [(value: Any, order: Double?)], sort: ChapterSort?) -> [Any] {
        guard let sort: ChapterSort = sort,
              sort != .none,
              values.contains(where: { pair in pair.order != nil }) else {
            return []
        }

        return values.sorted { lhs, rhs in
            let lhsOrder: Double = lhs.order ?? 0
            let rhsOrder: Double = rhs.order ?? 0

            switch sort {
            case .ascending:
                return lhsOrder < rhsOrder
            case .descending:
                return lhsOrder > rhsOrder
            case .none:
                return false
            }
        }
        .map(\.value)
    }

    static func apiErrorMessage(in object: Any) -> String? {
        guard let dictionary: [String: Any] = object as? [String: Any] else {
            return nil
        }

        if let errors: [Any] = dictionary["errors"] as? [Any],
           errors.isEmpty == false {
            let messages: [String] = errors.compactMap { error in
                return self.apiErrorMessage(from: error)
            }
            if messages.isEmpty == false {
                return messages.joined(separator: "; ")
            }

            return "API returned errors"
        }

        if let error: Any = dictionary["error"] {
            return self.apiErrorMessage(from: error) ?? "API returned error"
        }

        if let code: String = self.stringValue(dictionary["code"]),
           code != "0" {
            let message: String? = self.stringValue(dictionary["message"])
            var details: [String] = []
            if let message: String, message.isEmpty == false {
                details.append(message)
            }
            details.append("code=\(code)")
            return details.joined(separator: " ")
        }

        return nil
    }

    static func detailSlug(from detailURL: String) -> String? {
        guard let url: URL = URL(string: detailURL) else {
            return nil
        }

        let components: [String] = url.pathComponents.filter { component in
            return component != "/"
        }
        guard var lastPathComponent: String = components.last else {
            return nil
        }

        if ["content", "detail", "info"].contains(lastPathComponent.lowercased()),
           components.count >= 2 {
            lastPathComponent = components[components.count - 2]
        }

        if let extensionRange: Range<String.Index> = lastPathComponent.range(of: ".", options: .backwards) {
            return String(lastPathComponent[..<extensionRange.lowerBound])
        }

        return lastPathComponent.isEmpty ? nil : lastPathComponent
    }

    static func pathComponent(after marker: String, in urlString: String) -> String? {
        guard let url: URL = URL(string: urlString) else {
            return nil
        }

        let components: [String] = url.pathComponents.filter { component in
            return component != "/"
        }

        guard let markerIndex: Array<String>.Index = components.firstIndex(of: marker) else {
            return nil
        }

        let valueIndex: Array<String>.Index = components.index(after: markerIndex)
        guard valueIndex < components.endIndex else {
            return nil
        }

        return components[valueIndex]
    }

    private static func apiErrorMessage(from object: Any) -> String? {
        if let message: String = self.stringValue(object) {
            return message
        }

        guard let dictionary: [String: Any] = object as? [String: Any] else {
            return nil
        }

        let message: String? = self.stringValue(dictionary["message"])
        let code: String? = self.stringValue(dictionary["code"])
            ?? ((dictionary["extensions"] as? [String: Any]).flatMap { extensions in
                return self.stringValue(extensions["code"])
            })

        var details: [String] = []
        if let message: String, message.isEmpty == false {
            details.append(message)
        }
        if let code: String, code.isEmpty == false {
            details.append("code=\(code)")
        }

        if let extensions: [String: Any] = dictionary["extensions"] as? [String: Any] {
            for key: String in ["current", "limit", "requested"] {
                if let value: String = self.stringValue(extensions[key]) {
                    details.append("\(key)=\(value)")
                }
            }
        }

        return details.isEmpty ? nil : details.joined(separator: " ")
    }

    private static func templateValue(
        token: String,
        source: Source,
        item: ContentItem,
        chapterURL: String?,
        page: Int?,
        rootJSON: Any?,
        currentJSON: Any?
    ) -> String? {
        switch token {
        case "source.id":
            return source.id
        case "source.baseURL", "source.baseUrl":
            return source.baseURL
        case "context.userAgent":
            return self.ruleContextValue("userAgent", source: source)
                ?? BrowserRequestHeaders.Chrome.chromeUserAgent
        case "context.device":
            return self.ruleContextValue("device", source: source) ?? "server"
        case "context.deviceUUID":
            return self.ruleContextValue("deviceUUID", source: source)
                ?? self.ruleContextValue("uuid", source: source)
                ?? self.contextDeviceUUID(source: source)
        case "context.uuid":
            return self.ruleContextValue("uuid", source: source)
                ?? self.ruleContextValue("deviceUUID", source: source)
                ?? self.contextDeviceUUID(source: source)
        case "context.readerAccessToken":
            return self.ruleContextValue("readerAccessToken", source: source)
        case "item.id":
            return item.id
        case "item.title":
            return item.title
        case "detailURL", "item.detailURL":
            return item.detailURL
        case "detailSlug", "item.detailSlug":
            return self.detailSlug(from: item.detailURL)
        case "chapterURL", "reader.chapterURL":
            return chapterURL
        case "chapterId", "reader.chapterId":
            guard let chapterURL: String else {
                return nil
            }
            return self.pathComponent(after: "chapter", in: chapterURL)
                ?? self.detailSlug(from: chapterURL)
        case "comicId", "reader.comicId":
            if let chapterURL: String,
               let comicID: String = self.pathComponent(after: "comic", in: chapterURL) {
                return comicID
            }
            return self.detailSlug(from: item.detailURL)
        case "timestamp":
            return String(Int(Date().timeIntervalSince1970))
        case "page":
            return page.map(String.init)
        default:
            if token.hasPrefix("context.") {
                let contextKey: String = String(token.dropFirst("context.".count))
                if let value: String = self.ruleContextValue(contextKey, source: source) {
                    return value
                }
            }

            if let currentJSON: Any = currentJSON,
               let value: String = self.stringValue(self.firstJSONValue(at: token, in: currentJSON)) {
                return value
            }

            if let rootJSON: Any = rootJSON,
               let value: String = self.stringValue(self.firstJSONValue(at: token, in: rootJSON)) {
                return value
            }

            return nil
        }
    }

    private static func contextDeviceUUID(source: Source) -> String {
        let rawID: String = "BrowseCraft:\(source.id):\(source.baseURL)"
        let data: Data? = rawID.data(using: .utf8)
        let encoded: String = data?.base64EncodedString() ?? source.id
        let sanitized: String = encoded
            .filter { character in
                character.isLetter || character.isNumber
            }
            .lowercased()
        let padded: String = sanitized.padding(toLength: 32, withPad: "0", startingAt: 0)
        return String(padded.prefix(32))
    }

    static func ruleContextValues(
        source: Source,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) -> [String: String] {
        guard let context: [String: SiteRuleContextValue] = source.rule.context else {
            return [:]
        }

        var values: [String: String] = [:]
        context.forEach { key, value in
            if let resolvedValue: String = self.credentialValue(
                value.userValue,
                sourceID: source.id,
                credentialProvider: credentialProvider
            ) ?? self.ruleContextValue(value) {
                values[key] = resolvedValue
            }
        }
        if values["uuid"] == nil,
           let deviceUUID: String = values["deviceUUID"] {
            values["uuid"] = deviceUUID
        }
        if values["deviceUUID"] == nil,
           let uuid: String = values["uuid"] {
            values["deviceUUID"] = uuid
        }
        return values
    }

    private static func credentialValue(
        _ userValue: String?,
        sourceID: String,
        credentialProvider: any SourceCredentialProviding
    ) -> String? {
        guard var reference: String = userValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              reference.isEmpty == false else {
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
            return credentialProvider.token(for: sourceID, key: keyPath)
        }
        if keyPath.hasPrefix("localStorage.") {
            return credentialProvider.storageValue(
                for: sourceID,
                storage: .localStorage,
                key: String(keyPath.dropFirst("localStorage.".count))
            )
        }
        if keyPath.hasPrefix("sessionStorage.") {
            return credentialProvider.storageValue(
                for: sourceID,
                storage: .sessionStorage,
                key: String(keyPath.dropFirst("sessionStorage.".count))
            )
        }
        return nil
    }

    private static func ruleContextValue(_ key: String, source: Source) -> String? {
        guard let value: SiteRuleContextValue = source.rule.context?[key] else {
            return nil
        }
        return self.ruleContextValue(value)
    }

    private static func ruleContextValue(_ value: SiteRuleContextValue) -> String? {
        for candidate: String? in [value.value, value.anonymousValue, value.`default`] {
            if let candidate: String = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               candidate.isEmpty == false {
                return candidate
            }
        }
        return nil
    }
}
