import Foundation

// 中文注释：RSSFeedLoading 是 RSS runtime 对 feed loader 的最小依赖，便于 runtime 测试替换。
protocol RSSFeedLoading {
    func load(feedURL: URL) async throws -> RSSFeed
}

/// 中文注释：支持来源上下文的 RSS loader 会把 L3 会话带入 feed 请求；旧测试替身仍可只实现基础协议。
protocol ContextualRSSFeedLoading: RSSFeedLoading {
    func load(feedURL: URL, context: SourceRequestContext) async throws -> RSSFeed
}

// 中文注释：RSSFeedLoader 负责 RSS feed 的原始 XML 加载与映射；会话合并由带来源上下文的底层 loader 统一处理。
struct RSSFeedLoader: ContextualRSSFeedLoading {
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
        return try await self.load(feedURL: feedURL, context: nil)
    }

    func load(feedURL: URL, context: SourceRequestContext) async throws -> RSSFeed {
        return try await self.load(feedURL: feedURL, context: Optional(context))
    }

    private func load(feedURL: URL, context: SourceRequestContext?) async throws -> RSSFeed {
        let requestConfig: RequestConfig = RequestConfig(
            mergePolicy: .override,
            headers: APIRequestHeaders.rssFeedHeaders()
        )

        if let dataLoader: PageDataLoader = self.pageContentLoader as? PageDataLoader {
            let data: Data = try await dataLoader.getData(
                from: feedURL,
                request: requestConfig,
                context: context
            )
            try Self.validateFeedData(data, feedURL: feedURL)
            return try self.mapper.map(data)
        }

        let xml: String = try await self.pageContentLoader.getString(
            from: feedURL,
            request: requestConfig,
            context: context
        )
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
