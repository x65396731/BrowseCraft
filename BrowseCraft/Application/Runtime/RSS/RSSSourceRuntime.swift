import Foundation
import BrowseCraftCore

// 中文注释：RSSSourceRuntime 是 RSS feed 的独立 SourceRuntime，不复用 SiteRule 解析 DSL。
struct RSSSourceRuntime: SourceRuntime {
    let definition: SourceDefinition

    private let feedLoader: any RSSFeedLoading
    private let pageContentLoader: PageContentLoader?
    private let mediaClassifier: RSSMediaClassifier = RSSMediaClassifier()

    init(
        definition: SourceDefinition,
        feedLoader: any RSSFeedLoading,
        pageContentLoader: PageContentLoader? = nil
    ) {
        self.definition = definition
        self.feedLoader = feedLoader
        self.pageContentLoader = pageContentLoader
    }

    var capabilities: SourceRuntimeCapabilities {
        let supportsDetail: Bool = self.pageContentLoader != nil
        var limitations: [SourceRuntimeCapabilityLimitation] = [
            self.limitation(.search, "RSS MVP does not support search."),
            self.limitation(.pagination, "RSS MVP does not support pagination."),
            self.limitation(.reader, "RSS MVP does not support reader output."),
            self.limitation(.debug, "RSS runtime diagnostics are not available."),
            self.limitation(.candidateAnalysis, "RSS feeds use a fixed XML schema and do not run selector candidate analysis.")
        ]
        if supportsDetail == false {
            limitations.append(
                self.limitation(.detail, "RSS detail page loader is not connected.")
            )
        }

        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: false,
            supportsDetail: supportsDetail,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: self.definition.rss?.requiresAccount ?? false,
            limitations: limitations
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)

        guard let rssDefinition: RSSSourceDefinition = self.definition.rss else {
            throw SourceRuntimeError.invalidInput("RSS runtime requires an RSS source definition.")
        }

        let feed: RSSFeed
        if let contextualLoader: any ContextualRSSFeedLoading = self.feedLoader as? any ContextualRSSFeedLoading {
            feed = try await contextualLoader.load(
                feedURL: rssDefinition.feedURL,
                context: SourceRequestContext(
                    sourceID: self.definition.id,
                    baseURL: self.definition.baseURL,
                    purpose: .rss,
                    refererURL: rssDefinition.feedURL
                )
            )
        } else {
            feed = try await self.feedLoader.load(feedURL: rssDefinition.feedURL)
        }
        let items: [SourceContentItem] = self.contentItems(from: feed)
        #if DEBUG
        let latestTextLengths: [Int] = items.map { item in
            return item.latestText?.count ?? 0
        }
        let maxLatestTextLength: Int = latestTextLengths.max() ?? 0
        let firstLatestTextLength: Int = latestTextLengths.first ?? 0
        print(
            "[BrowseCraftRSS] runtime.loadList source=\(self.definition.id) " +
            "feedTitle=\(feed.title ?? "nil") " +
            "feedItems=\(feed.items.count) " +
            "outputItems=\(items.count) " +
            "firstLatestTextLength=\(firstLatestTextLength) " +
            "maxLatestTextLength=\(maxLatestTextLength) " +
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
        try self.validateSource(input.context)
        guard let pageContentLoader: PageContentLoader = self.pageContentLoader else {
            throw SourceRuntimeError.unsupported(.custom("RSS detail page loader is not connected."))
        }
        let html: String = try await pageContentLoader.getString(
            from: input.detailURL,
            request: nil,
            context: SourceRequestContext(
                sourceID: self.definition.id,
                baseURL: self.definition.baseURL,
                purpose: .rss,
                refererURL: input.detailURL
            )
        )
        let detail: RSSDetailHTMLParser.DetailContent = RSSDetailHTMLParser.detailContent(
            in: html,
            pageURL: input.detailURL
        )
        let richContent: SourceRichContent? = detail.blocks.isEmpty && detail.media == nil
            ? nil
            : SourceRichContent(
                summary: nil,
                blocks: detail.blocks,
                metadata: detail.metadata,
                media: detail.media
            )

        return SourceDetailOutput(
            metadata: SourceDetailMetadata(tags: detail.metadata.tags),
            richContent: richContent,
            chapters: [],
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.detailURL
                )
            )
        )
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        throw SourceRuntimeError.unsupported(.custom("RSS MVP does not support reader output."))
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "RSS runtime diagnostics are not available.",
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
                coverURL: item.coverURL,
                latestText: self.latestText(from: item),
                updatedAt: item.publishedAt,
                richContent: self.richContent(from: item)
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
        return Self.plainText(from: item.summary)
    }

    private func richContent(from item: RSSFeedItem) -> RSSContentPayload? {
        let media: RSSContentPayload.Media? = self.mediaClassifier.resolvedMedia(
            feedMedia: item.media,
            link: item.link,
            coverURL: item.coverURL
        )

        if item.contentBlocks.isEmpty == false || media != nil {
            let payload: RSSContentPayload = RSSContentPayload(
                summary: Self.plainText(from: item.summary),
                blocks: item.contentBlocks,
                media: media
            )
            return payload
        }

        return nil
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

private extension RSSSourceRuntime {
    static func plainText(from html: String?) -> String? {
        guard let html: String = html else {
            return nil
        }

        let withoutTags: String = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded: String = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed: String = decoded
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")

        return collapsed.trimmedNonEmpty
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
