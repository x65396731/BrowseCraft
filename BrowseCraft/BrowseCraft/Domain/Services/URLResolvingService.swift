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
    /// 中文注释：listURL 方法封装当前类型的一段业务或界面行为。
    func listURL(for source: Source, page: Int) throws -> URL {
        return try self.listURL(for: source, listRule: source.rule.list, page: page)
    }

    func listURL(for source: Source, listRule: ListRule, page: Int) throws -> URL {
        let rawURL: String = listRule.url.replacingOccurrences(of: "{page}", with: String(page))
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
}
