import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：RSSFeedLoading 是 RSS runtime 对 feed loader 的最小依赖，便于 runtime 测试替换。
protocol RSSFeedLoading: Sendable {
    func load(feedURL: URL) async throws -> RSSFeed
}

/// 中文注释：支持来源上下文的 RSS loader 会把 L3 会话带入 feed 请求。
protocol ContextualRSSFeedLoading: RSSFeedLoading, Sendable {
    func load(feedURL: URL, context: SourceRequestContext) async throws -> RSSFeed
}

// 中文注释：RSSFeedLoader 只负责加载与响应校验，最终 XML 交给 BrowseCraftCore 解释。
struct RSSFeedLoader: ContextualRSSFeedLoading {
    private let pageDataLoader: PageDataLoader
    private let parser: any BrowseCraftCore.RSSFeedParsing

    init(
        pageDataLoader: PageDataLoader,
        parser: any BrowseCraftCore.RSSFeedParsing = BrowseCraftCore.DefaultRSSFeedParser()
    ) {
        self.pageDataLoader = pageDataLoader
        self.parser = parser
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
            headers: SourceAPIRequestHeaders.rssFeedHeaders()
        )

        let response: PageDataResponse = try await self.pageDataLoader.loadData(
            PageLoadRequest(
                url: feedURL,
                requestConfig: requestConfig,
                sourceContext: context
            )
        )
        try Self.validateFeedData(response.data, feedURL: response.finalURL)
        return try self.parser.parseFeed(
            BrowseCraftCore.RSSFeedParsingInput(
                document: BrowseCraftCore.SourceContentDocument(
                    data: response.data,
                    finalURL: response.finalURL,
                    format: .xml,
                    mediaType: "application/xml"
                ),
                runtimeContext: Self.runtimeContext(
                    feedURL: response.finalURL,
                    context: context
                )
            )
        )
    }

    private static func runtimeContext(
        feedURL: URL,
        context: SourceRequestContext?
    ) -> BrowseCraftCore.SourceRuntimeContext {
        return BrowseCraftCore.SourceRuntimeContext(
            sourceID: context?.sourceID ?? feedURL.host ?? feedURL.absoluteString,
            pageID: nil,
            tabID: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false,
            operation: .list
        )
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

    // 中文注释：Cloudflare 一类挑战页判据只消费 `HTMLChallengeInterstitialDetector`
    // （`BC-EVIDENCE-081`）；下面保留的是 RSS 源站自定义的拦截文案与 cf 错误页。
    private static func isAntiBotHTML(_ html: String) -> Bool {
        return HTMLChallengeInterstitialDetector.isChallengeInterstitial(html)
            || html.localizedCaseInsensitiveContains("Attention Required")
            || html.localizedCaseInsensitiveContains("Just a moment")
            || html.localizedCaseInsensitiveContains("cf-error-details")
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
