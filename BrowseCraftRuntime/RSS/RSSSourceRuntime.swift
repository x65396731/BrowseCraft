import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：RSSSourceRuntime 是 RSS feed 的独立 SourceRuntime，不复用 SiteRule 解析 DSL。
public struct RSSSourceRuntime: SourceRuntime, SourceDetailRuntime, Sendable {
    public let definition: SourceDefinition

    private let feedLoader: any RSSFeedLoading
    private let pageContentLoader: PageContentLoader?
    private let detailParser: any BrowseCraftCore.RSSDetailParsing
    private let mediaClassifier: RSSMediaClassifier = RSSMediaClassifier()

    public init(
        definition: SourceDefinition,
        feedLoader: any RSSFeedLoading,
        pageContentLoader: PageContentLoader? = nil,
        detailParser: any BrowseCraftCore.RSSDetailParsing = BrowseCraftCore.DefaultRSSDetailParser()
    ) {
        self.definition = definition
        self.feedLoader = feedLoader
        self.pageContentLoader = pageContentLoader
        self.detailParser = detailParser
    }

    public var capabilities: SourceRuntimeCapabilities {
        let supportsDetail: Bool = self.pageContentLoader != nil
        var limitations: [SourceRuntimeCapabilityLimitation] = [
            self.limitation(.search, "RSS MVP does not support search."),
            self.limitation(.pagination, "RSS MVP does not support pagination."),
            self.limitation(.reader, "RSS MVP does not support reader output."),
            self.limitation(.playback, "RSS runtime exposes media through rich content, not video playback output."),
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
            supportsPlayback: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: self.definition.rss?.requiresAccount ?? false,
            limitations: limitations
        )
    }

    public func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
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
        RuleRuntimeDebugLog.shared.write(
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

    public func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        try self.validateSource(input.context)
        guard let pageContentLoader: PageContentLoader = self.pageContentLoader else {
            throw SourceRuntimeError.unsupported(.custom("RSS detail page loader is not connected."))
        }
        let response: PageContentResponse = try await pageContentLoader.loadContent(
            PageLoadRequest(
                url: input.detailURL,
                requestConfig: nil,
                sourceContext: SourceRequestContext(
                    sourceID: self.definition.id,
                    baseURL: self.definition.baseURL,
                    purpose: .rss,
                    refererURL: input.detailURL
                )
            )
        )
        return try self.detailParser.parseDetail(
            BrowseCraftCore.RSSDetailParsingInput(
                document: BrowseCraftCore.SourceContentDocument(
                    text: response.content,
                    finalURL: response.finalURL,
                    format: .html,
                    mediaType: "text/html"
                ),
                runtimeContext: input.context
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
        let feedRichContent: RSSContentPayload? = item.richContent
        let media: RSSContentPayload.Media? = self.mediaClassifier.resolvedMedia(
            feedMedia: feedRichContent?.media,
            link: item.link,
            coverURL: item.coverURL
        )

        guard feedRichContent != nil || media != nil else {
            return nil
        }

        return RSSContentPayload(
            summary: feedRichContent?.summary ?? Self.plainText(from: item.summary),
            blocks: feedRichContent?.blocks ?? [],
            metadata: feedRichContent?.metadata,
            media: media
        )
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
