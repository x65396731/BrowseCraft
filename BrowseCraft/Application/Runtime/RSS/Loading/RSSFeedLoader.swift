import Foundation

// 中文注释：RSSFeedLoading 是 RSS runtime 对 feed loader 的最小依赖，便于 runtime 测试替换。
protocol RSSFeedLoading {
    func load(feedURL: URL) async throws -> RSSFeed
}

// 中文注释：RSSFeedLoader 负责公开 RSS feed 的原始 XML 加载与映射，不处理登录、Cookie 或 Token。
struct RSSFeedLoader: RSSFeedLoading {
    private let pageContentLoader: PageContentLoader
    private let mapper: RSSFeedMapper

    init(
        pageContentLoader: PageContentLoader,
        mapper: RSSFeedMapper = RSSFeedMapper()
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
    }

    func load(feedURL: URL) async throws -> RSSFeed {
        let requestConfig: RequestConfig = RequestConfig(
            mergePolicy: .override,
            headers: APIRequestHeaders.rssFeedHeaders()
        )

        if let dataLoader: PageDataLoader = self.pageContentLoader as? PageDataLoader {
            let data: Data = try await dataLoader.getData(from: feedURL, request: requestConfig)
            try Self.validateFeedData(data, feedURL: feedURL)
            return try self.mapper.map(data)
        }

        let xml: String = try await self.pageContentLoader.getString(from: feedURL, request: requestConfig)
        try Self.validateFeedText(xml, feedURL: feedURL)
        return try self.mapper.map(xml)
    }

    private static func validateFeedData(_ data: Data, feedURL: URL) throws {
        let text: String
        if let string: String = String(data: data.prefix(8_192), encoding: .utf8) {
            text = string
        } else {
            text = String(decoding: data.prefix(8_192), as: UTF8.self)
        }

        try Self.validateFeedText(text, feedURL: feedURL)
    }

    private static func validateFeedText(_ text: String, feedURL: URL) throws {
        let trimmedPrefix: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrefix.hasPrefix("<!DOCTYPE html")
            || trimmedPrefix.hasPrefix("<!doctype html")
            || trimmedPrefix.hasPrefix("<html")
            || trimmedPrefix.hasPrefix("<HTML") else {
            return
        }

        if Self.isAntiBotHTML(trimmedPrefix) {
            throw RuleExecutionError.antiBot(url: feedURL.absoluteString)
        }

        throw RSSFeedLoaderError.nonFeedResponse(Self.preview(from: trimmedPrefix))
    }

    private static func isAntiBotHTML(_ html: String) -> Bool {
        return html.localizedCaseInsensitiveContains("Attention Required")
            || html.localizedCaseInsensitiveContains("Just a moment")
            || html.localizedCaseInsensitiveContains("cf-error-details")
            || html.localizedCaseInsensitiveContains("challenge-platform")
            || html.localizedCaseInsensitiveContains("cdn-cgi/challenge-platform")
            || html.localizedCaseInsensitiveContains("访问被拒绝")
            || html.localizedCaseInsensitiveContains("安全策略拦截")
            || html.localizedCaseInsensitiveContains("客官您被拦下")
            || html.localizedCaseInsensitiveContains("403")
    }

    private static func preview(from text: String) -> String {
        return String(text.prefix(180))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RSSFeedLoaderError: LocalizedError, Equatable {
    case nonFeedResponse(String)

    var errorDescription: String? {
        switch self {
        case .nonFeedResponse(let preview):
            return "The feed URL returned a non-RSS page: \(preview)"
        }
    }
}
