import Foundation
import BrowseCraftCore

// 中文注释：RSSSourceRuntime 是 RSS feed 的独立 SourceRuntime，不复用 SiteRule 解析 DSL。
struct RSSSourceRuntime: SourceRuntime {
    let definition: SourceDefinition

    private let feedLoader: any RSSFeedLoading

    init(
        definition: SourceDefinition,
        feedLoader: any RSSFeedLoading
    ) {
        self.definition = definition
        self.feedLoader = feedLoader
    }

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: false,
            supportsDetail: false,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: self.definition.rss?.requiresAccount ?? false,
            limitations: [
                self.limitation(.search, "RSS MVP does not support search."),
                self.limitation(.pagination, "RSS MVP does not support pagination."),
                self.limitation(.detail, "RSS MVP exposes feed item links but does not load detail pages."),
                self.limitation(.reader, "RSS MVP does not support reader output."),
                self.limitation(.debug, "RSS debug runtime is not connected yet."),
                self.limitation(.candidateAnalysis, "RSS feeds use a fixed XML schema and do not run selector candidate analysis.")
            ]
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)

        guard let rssDefinition: RSSSourceDefinition = self.definition.rss else {
            throw SourceRuntimeError.invalidInput("RSS runtime requires an RSS source definition.")
        }

        let feed: RSSFeed = try await self.feedLoader.load(feedURL: rssDefinition.feedURL)
        let items: [SourceContentItem] = self.contentItems(from: feed)
        #if DEBUG
        print(
            "[BrowseCraftRSS] runtime.loadList source=\(self.definition.id) " +
            "feedTitle=\(feed.title ?? "nil") " +
            "feedItems=\(feed.items.count) " +
            "outputItems=\(items.count) " +
            "url=\(rssDefinition.feedURL.absoluteString)"
        )
        #endif
        return SourceListOutput(
            items: items,
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: rssDefinition.feedURL
                )
            )
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        throw SourceRuntimeError.unsupported(.custom("RSS MVP does not support search."))
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        throw SourceRuntimeError.unsupported(.custom("RSS MVP does not support detail loading."))
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        throw SourceRuntimeError.unsupported(.custom("RSS MVP does not support reader output."))
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "RSS debug runtime is not connected yet.",
                context: SourceRuntimeDiagnosticContext(runtimeContext: input)
            )
        )
    }

    private func contentItems(from feed: RSSFeed) -> [SourceContentItem] {
        return feed.items.enumerated().map { index, item in
            return SourceContentItem(
                id: self.itemID(item: item, index: index),
                title: item.title ?? "Untitled RSS Item",
                detailURL: item.link,
                coverURL: nil,
                latestText: self.latestText(from: item),
                updatedAt: item.publishedAt
            )
        }
    }

    private func itemID(item: RSSFeedItem, index: Int) -> String {
        if let guid: String = item.guid?.trimmedNonEmpty {
            return guid
        }

        if let link: URL = item.link {
            return link.absoluteString
        }

        if let title: String = item.title?.trimmedNonEmpty {
            return "\(self.definition.id).rss.\(title)"
        }

        return "\(self.definition.id).rss.\(index)"
    }

    private func latestText(from item: RSSFeedItem) -> String? {
        return item.summary?.trimmedNonEmpty
    }

    private func validateSource(_ context: SourceRuntimeContext) throws {
        guard context.sourceID == self.definition.id else {
            throw SourceRuntimeError.sourceMismatch(
                expected: self.definition.id,
                actual: context.sourceID
            )
        }
    }

    private func limitation(
        _ capability: SourceRuntimeCapability,
        _ message: String
    ) -> SourceRuntimeCapabilityLimitation {
        return SourceRuntimeCapabilityLimitation(
            capability: capability,
            reason: .notImplemented,
            message: message
        )
    }

}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
