import Foundation

// 中文注释：URLResolvingService.swift 属于领域服务协议层，用于说明本文件承载的核心职责。

/// 中文注释：URLResolvingError 是 enum，负责本模块中的对应职责。
enum URLResolvingError: LocalizedError {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let rawURL):
            return "Invalid URL: \(rawURL)"
        }
    }
}

/// 中文注释：URL 辅助服务，集中处理相对地址转绝对地址的逻辑。
/// 中文注释：这样 SwiftUI 和解析器不需要各自重复拼接 URL。
struct URLResolvingService {
    private static let placeholderPattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "\\{([^{}]+)\\}")
    }()

    private static let queryValueAllowedCharacters: CharacterSet = {
        var characters: CharacterSet = .urlQueryAllowed
        characters.remove(charactersIn: "&+=?#")
        return characters
    }()

    /// 中文注释：listURL 方法封装当前类型的一段业务或界面行为。
    func listURL(for source: Source, page: Int) throws -> URL {
        return try self.listURL(for: source, listRule: source.rule.list, page: page)
    }

    func listURL(for source: Source, listRule: ListRule, page: Int) throws -> URL {
        let rawURL: String = self.renderURLTemplate(
            listRule.url,
            placeholders: source.rule.urlPatterns?.listTemplate?.placeholders,
            source: source,
            page: page,
            keyword: nil,
            keywordEncoding: nil
        )
        let absoluteURLString: String = self.absoluteString(rawURL, baseURLString: source.baseURL)

        guard let url: URL = URL(string: absoluteURLString) else {
            throw URLResolvingError.invalidURL(rawURL)
        }

        return url
    }

    func searchURL(for source: Source, searchRule: SearchRule, keyword: String, page: Int = 1) throws -> URL {
        let rawURL: String

        if let template: URLTemplateRule = source.rule.urlPatterns?.searchTemplate {
            rawURL = self.renderURLTemplate(
                template.template,
                placeholders: template.placeholders,
                source: source,
                page: page,
                keyword: keyword,
                keywordEncoding: searchRule.keywordEncoding
            )
        } else {
            rawURL = self.renderURLTemplate(
                searchRule.url,
                placeholders: nil,
                source: source,
                page: page,
                keyword: keyword,
                keywordEncoding: searchRule.keywordEncoding
            )
        }

        let absoluteURLString: String = self.absoluteString(rawURL, baseURLString: source.baseURL)

        guard let url: URL = URL(string: absoluteURLString) else {
            throw URLResolvingError.invalidURL(rawURL)
        }

        return url
    }

    func templateURL(
        for source: Source,
        template: URLTemplateRule,
        page: Int = 1,
        keyword: String? = nil,
        keywordEncoding: KeywordEncoding? = nil
    ) throws -> URL {
        let rawURL: String = self.renderURLTemplate(
            template.template,
            placeholders: template.placeholders,
            source: source,
            page: page,
            keyword: keyword,
            keywordEncoding: keywordEncoding
        )
        let absoluteURLString: String = self.absoluteString(rawURL, baseURLString: source.baseURL)

        guard let url: URL = URL(string: absoluteURLString) else {
            throw URLResolvingError.invalidURL(rawURL)
        }

        return url
    }

    /// 中文注释：absoluteString 方法封装当前类型的一段业务或界面行为。
    func absoluteString(_ rawURLString: String, baseURLString: String) -> String {
        if let url: URL = URL(string: rawURLString), url.scheme != nil {
            return rawURLString
        }

        guard let baseURL: URL = URL(string: baseURLString) else {
            return rawURLString
        }

        guard let resolvedURL: URL = URL(string: rawURLString, relativeTo: baseURL) else {
            return rawURLString
        }

        return resolvedURL.absoluteURL.absoluteString
    }

    private func renderURLTemplate(
        _ rawTemplate: String,
        placeholders: [URLPlaceholderRule]?,
        source: Source,
        page: Int,
        keyword: String?,
        keywordEncoding: KeywordEncoding?
    ) -> String {
        var rendered: String = ""
        var currentIndex: String.Index = rawTemplate.startIndex
        let fullRange: NSRange = NSRange(rawTemplate.startIndex..<rawTemplate.endIndex, in: rawTemplate)
        let matches: [NSTextCheckingResult] = Self.placeholderPattern.matches(
            in: rawTemplate,
            range: fullRange
        )

        for match: NSTextCheckingResult in matches {
            guard let tokenRange: Range<String.Index> = Range(match.range(at: 1), in: rawTemplate),
                  let fullTokenRange: Range<String.Index> = Range(match.range(at: 0), in: rawTemplate) else {
                continue
            }

            rendered.append(contentsOf: rawTemplate[currentIndex..<fullTokenRange.lowerBound])
            let token: String = String(rawTemplate[tokenRange])
            let value: String = self.placeholderValue(
                for: token,
                placeholders: placeholders,
                source: source,
                page: page,
                keyword: keyword,
                keywordEncoding: keywordEncoding
            )
            rendered.append(value)
            currentIndex = fullTokenRange.upperBound
        }

        rendered.append(contentsOf: rawTemplate[currentIndex..<rawTemplate.endIndex])
        return rendered
    }

    private func placeholderValue(
        for token: String,
        placeholders: [URLPlaceholderRule]?,
        source: Source,
        page: Int,
        keyword: String?,
        keywordEncoding: KeywordEncoding?
    ) -> String {
        let parts: [String] = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let kindName: String = parts.first,
              let kind: URLPlaceholderKind = URLPlaceholderKind(rawValue: kindName) else {
            return "{\(token)}"
        }

        let name: String? = parts.count > 1 && parts[1].isEmpty == false ? parts[1] : nil
        let metadata: URLPlaceholderRule? = placeholders?.first { placeholder in
            guard placeholder.kind == kind else {
                return false
            }

            if let placeholderName: String = placeholder.name {
                return placeholderName == name
            }

            return name == nil || kind == .urlQuery
        }

        switch kind {
        case .page:
            return String(self.pageValue(parts: parts, metadata: metadata, requestedPage: page))
        case .keyword:
            return self.encodedKeyword(
                keyword ?? metadata?.defaultValue ?? "",
                encoding: metadata?.encoding ?? keywordEncoding
            )
        case .url:
            return source.baseURL
        case .urlScheme:
            return URL(string: source.baseURL)?.scheme ?? metadata?.defaultValue ?? ""
        case .urlHost:
            return URL(string: source.baseURL)?.host ?? metadata?.defaultValue ?? ""
        case .urlPort:
            if let port: Int = URL(string: source.baseURL)?.port {
                return String(port)
            }

            return metadata?.defaultValue ?? ""
        case .urlQuery:
            return self.urlQueryValue(
                name: metadata?.name ?? name,
                source: source,
                defaultValue: metadata?.defaultValue
            )
        case .idCode, .cidCode, .urlPath, .custom:
            return metadata?.defaultValue ?? "{\(token)}"
        }
    }

    private func pageValue(parts: [String], metadata: URLPlaceholderRule?, requestedPage: Int) -> Int {
        let start: Int = metadata?.start ?? self.integer(parts, at: 1) ?? 1
        let step: Int = metadata?.step ?? self.integer(parts, at: 2) ?? 1
        let normalizedPage: Int = max(requestedPage, 1)
        return start + ((normalizedPage - 1) * step)
    }

    private func integer(_ parts: [String], at index: Int) -> Int? {
        guard parts.indices.contains(index) else {
            return nil
        }

        return Int(parts[index])
    }

    private func encodedKeyword(_ keyword: String, encoding: KeywordEncoding?) -> String {
        switch encoding ?? .urlQueryAllowed {
        case .raw:
            return keyword
        case .percentEncoded, .urlQueryAllowed:
            return keyword.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowedCharacters) ?? keyword
        }
    }

    private func urlQueryValue(name: String?, source: Source, defaultValue: String?) -> String {
        guard let name: String,
              let components: URLComponents = URLComponents(string: source.baseURL),
              let item: URLQueryItem = components.queryItems?.first(where: { queryItem in
                  return queryItem.name == name
              }),
              let value: String = item.value else {
            return defaultValue ?? ""
        }

        return value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowedCharacters) ?? value
    }
}
