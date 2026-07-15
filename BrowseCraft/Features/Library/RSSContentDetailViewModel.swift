import Combine
import Foundation

// 中文注释：RSSContentDetailViewModel 负责 RSS 详情页的业务行为。

/// 中文注释：RSS 阅读历史保存放在 ViewModel，View 只负责展示与触发生命周期。
@MainActor
final class RSSContentDetailViewModel: ObservableObject {
    private static let maxAcceptedDetailBlockCount: Int = 300
    private static let maxAcceptedDetailImageCount: Int = 80

    @Published private(set) var shouldPlayAd: Bool = false
    @Published private(set) var displayItem: ContentItem

    let item: ContentItem
    let source: Source

    private let saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase?
    private let pageContentLoader: PageContentLoader?
    private let now: () -> Date
    private var didSaveReadingHistory: Bool = false
    private var didLoadDetailContent: Bool = false

    init(
        item: ContentItem,
        source: Source,
        saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase,
        accumulateAdPointsUseCase: AccumulateAdPointsUseCase? = nil,
        pageContentLoader: PageContentLoader? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.displayItem = item
        self.source = source
        self.saveRSSReadingHistoryUseCase = saveRSSReadingHistoryUseCase
        self.accumulateAdPointsUseCase = accumulateAdPointsUseCase
        self.pageContentLoader = pageContentLoader
        self.now = now
    }

    var sourceName: String {
        return self.source.name
    }

    func saveReadingHistoryIfNeeded() {
        if self.didSaveReadingHistory {
            return
        }

        self.didSaveReadingHistory = true

        do {
            try self.saveRSSReadingHistoryUseCase.execute(
                history: self.readingHistory()
            )
            self.accumulateAdPoints(points: AdPointRule.rssPoints)
            AppAnalytics.shared.logReaderOpened(source: self.source)
            #if DEBUG
            print(
                "[BrowseCraftRSSHistory] saved " +
                "userID=\(AppUser.localDefaultID) " +
                "sourceID=\(self.source.id) " +
                "itemID=\(self.item.id)"
            )
            #endif
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftRSSHistory] save failed " +
                "sourceID=\(self.source.id) " +
                "itemID=\(self.item.id) " +
                "error=\(error)"
            )
            #endif
        }
    }

    func markAdPlaybackHandled() {
        #if DEBUG
        print(
            "[BrowseCraftAdPlayback] RSS mark handled " +
            "sourceID=\(self.source.id) itemID=\(self.item.id) previousShouldPlayAd=\(self.shouldPlayAd)"
        )
        #endif
        self.shouldPlayAd = false
    }

    func loadDetailContentIfNeeded() async {
        guard self.didLoadDetailContent == false else {
            return
        }

        self.didLoadDetailContent = true

        guard let pageContentLoader: PageContentLoader = self.pageContentLoader,
              let detailURL: URL = URL(string: self.item.detailURL) else {
            return
        }

        do {
            let html: String = try await pageContentLoader.getString(from: detailURL, request: nil)
            let detailContent: RSSDetailHTMLParser.DetailContent = RSSDetailHTMLParser.detailContent(
                in: html,
                pageURL: detailURL
            )
            let blocks: [RSSContentPayload.Block] = detailContent.blocks
            guard blocks.isEmpty == false else {
                self.logEmptyDetailContent(htmlLength: html.count, url: detailURL)
                return
            }

            var updatedItem: ContentItem = self.item
            let rawDetailImageCount: Int = blocks.filter { block in block.kind == .image }.count
            guard self.shouldApplyDetailContent(blocks: blocks, imageCount: rawDetailImageCount) else {
                self.logSkippedDetailContent(
                    htmlLength: html.count,
                    blocks: blocks.count,
                    images: rawDetailImageCount,
                    stage: "raw",
                    url: detailURL
                )
                return
            }

            let feedPayload: RSSContentPayload? = RSSContentPayload.decode(from: self.item.latestText)
            let mergedBlocks: [RSSContentPayload.Block] = self.mergedDetailBlocks(blocks)
            let mergedImageCount: Int = mergedBlocks.filter { block in block.kind == .image }.count
            guard self.shouldApplyDetailContent(blocks: mergedBlocks, imageCount: mergedImageCount) else {
                self.logSkippedDetailContent(
                    htmlLength: html.count,
                    blocks: mergedBlocks.count,
                    images: mergedImageCount,
                    stage: "merged",
                    url: detailURL
                )
                return
            }

            let payload: RSSContentPayload = RSSContentPayload(
                summary: RSSContentTextFormatter.sanitized(self.item.latestText),
                blocks: mergedBlocks,
                metadata: self.mergedMetadata(detailContent.metadata, feedMetadata: feedPayload?.metadata),
                media: self.mergedMedia(detailContent.media, feedMedia: feedPayload?.media, coverURL: updatedItem.coverURL)
            )
            updatedItem.latestText = payload.encodedString() ?? self.item.latestText
            if self.shouldReplaceCoverURL(updatedItem.coverURL) {
                updatedItem.coverURL = mergedBlocks.compactMap { block in
                    self.trimmedNonEmpty(block.imageURL)
                }.first
            }
            self.displayItem = updatedItem

            #if DEBUG
            print(
                "[BrowseCraftRSSDetail] loaded detail content " +
                "itemID=\(self.item.id) " +
                "htmlLength=\(html.count) " +
                "blocks=\(mergedBlocks.count) " +
                "rawImages=\(rawDetailImageCount) " +
                "images=\(mergedImageCount) " +
                "latestTextLength=\(updatedItem.latestText?.count ?? 0) " +
                "cover=\(updatedItem.coverURL ?? "nil") " +
                "tags=\(detailContent.metadata.tags) " +
                "likes=\(detailContent.metadata.likeCount.map(String.init) ?? "nil") " +
                "comments=\(detailContent.metadata.commentCount.map(String.init) ?? "nil") " +
                "url=\(detailURL.absoluteString)"
            )
            #endif
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftRSSDetail] load detail content failed " +
                "itemID=\(self.item.id) " +
                "url=\(detailURL.absoluteString) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func shouldApplyDetailContent(blocks: [RSSContentPayload.Block], imageCount: Int) -> Bool {
        return blocks.count <= Self.maxAcceptedDetailBlockCount
            && imageCount <= Self.maxAcceptedDetailImageCount
    }

    private func logEmptyDetailContent(htmlLength: Int, url: URL) {
        #if DEBUG
        print(
            "[BrowseCraftRSSDetail] empty detail content " +
            "itemID=\(self.item.id) " +
            "htmlLength=\(htmlLength) " +
            "url=\(url.absoluteString)"
        )
        #endif
    }

    private func logSkippedDetailContent(
        htmlLength: Int,
        blocks: Int,
        images: Int,
        stage: String,
        url: URL
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSDetail] skip oversized detail content " +
            "itemID=\(self.item.id) " +
            "stage=\(stage) " +
            "htmlLength=\(htmlLength) " +
            "blocks=\(blocks) " +
            "images=\(images) " +
            "maxBlocks=\(Self.maxAcceptedDetailBlockCount) " +
            "maxImages=\(Self.maxAcceptedDetailImageCount) " +
            "url=\(url.absoluteString)"
        )
        #endif
    }

    private func mergedMetadata(
        _ detailMetadata: RSSContentPayload.Metadata,
        feedMetadata: RSSContentPayload.Metadata?
    ) -> RSSContentPayload.Metadata? {
        let tags: [String] = detailMetadata.tags.isEmpty
            ? (feedMetadata?.tags ?? [])
            : detailMetadata.tags
        let likeCount: Int? = detailMetadata.likeCount ?? feedMetadata?.likeCount
        let commentCount: Int? = detailMetadata.commentCount ?? feedMetadata?.commentCount

        if tags.isEmpty, likeCount == nil, commentCount == nil {
            return nil
        }

        return RSSContentPayload.Metadata(
            tags: tags,
            likeCount: likeCount,
            commentCount: commentCount
        )
    }

    private func mergedMedia(
        _ detailMedia: RSSContentPayload.Media?,
        feedMedia: RSSContentPayload.Media?,
        coverURL: String?
    ) -> RSSContentPayload.Media? {
        guard var media: RSSContentPayload.Media = feedMedia ?? detailMedia else {
            return nil
        }

        if media.posterURL == nil {
            media.posterURL = coverURL
        }

        return media
    }

    private func mergedDetailBlocks(_ detailBlocks: [RSSContentPayload.Block]) -> [RSSContentPayload.Block] {
        var rejectedImageReasons: [String: Int] = [:]
        let detailTextBlocks: [RSSContentPayload.Block] = detailBlocks.filter { block in
            block.kind != .image
        }

        let filteredDetailImageBlocks: [RSSContentPayload.Block] = detailBlocks.filter { block in
            guard block.kind == .image else {
                return false
            }
            if let reason: String = Self.rssImageRejectionReason(block.imageURL) {
                rejectedImageReasons[reason, default: 0] += 1
                return false
            }

            return true
        }

        guard let feedPayload: RSSContentPayload = RSSContentPayload.decode(from: self.item.latestText) else {
            let filteredDetailBlocks: [RSSContentPayload.Block] = detailTextBlocks + self.deduplicatedImageBlocks(filteredDetailImageBlocks)
            self.logRSSImageFilterSummary(
                rawDetailBlocks: detailBlocks,
                feedImageCount: 0,
                rejectedImageReasons: rejectedImageReasons,
                finalBlocks: filteredDetailBlocks
            )
            return self.reindexedBlocks(filteredDetailBlocks)
        }

        var feedImageBlocks: [RSSContentPayload.Block] = []
        var seenImageDedupeKeys: Set<String> = []
        for block in feedPayload.blocks where block.kind == .image {
            guard let imageURL: String = block.imageURL else {
                rejectedImageReasons["missing-url", default: 0] += 1
                continue
            }
            guard let resolvedImageURL: String = self.resolvedImageURLString(imageURL) else {
                rejectedImageReasons["invalid-url", default: 0] += 1
                continue
            }

            if let reason: String = Self.rssImageRejectionReason(resolvedImageURL) {
                rejectedImageReasons[reason, default: 0] += 1
                continue
            }

            let dedupeKey: String = self.imageDedupeKey(for: resolvedImageURL)
            guard seenImageDedupeKeys.contains(dedupeKey) == false else {
                continue
            }

            seenImageDedupeKeys.insert(dedupeKey)
            feedImageBlocks.append(
                RSSContentPayload.Block(
                    id: "image-\(feedImageBlocks.count)",
                    kind: .image,
                    text: nil,
                    imageURL: resolvedImageURL
                )
            )
        }

        let mergedImageBlocks: [RSSContentPayload.Block] = self.deduplicatedImageBlocks(filteredDetailImageBlocks + feedImageBlocks)

        let mergedBlocks: [RSSContentPayload.Block] = detailTextBlocks + mergedImageBlocks

        let feedImageCount: Int = feedPayload.blocks.filter { block in
            block.kind == .image
        }.count
        self.logRSSImageFilterSummary(
            rawDetailBlocks: detailBlocks,
            feedImageCount: feedImageCount,
            rejectedImageReasons: rejectedImageReasons,
            finalBlocks: mergedBlocks
        )

        return self.reindexedBlocks(mergedBlocks)
    }

    private func shouldReplaceCoverURL(_ coverURL: String?) -> Bool {
        guard let coverURL: String = self.trimmedNonEmpty(coverURL) else {
            return true
        }

        guard let resolvedCoverURL: String = self.resolvedImageURLString(coverURL) else {
            return true
        }

        return Self.rssImageRejectionReason(resolvedCoverURL) != nil
    }

    private func resolvedImageURLString(_ imageURL: String) -> String? {
        guard let baseURL: URL = URL(string: self.item.detailURL),
              let url: URL = URL(string: imageURL, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        return url.absoluteString
    }

    private func reindexedBlocks(_ blocks: [RSSContentPayload.Block]) -> [RSSContentPayload.Block] {
        return blocks.enumerated().map { index, block in
            RSSContentPayload.Block(
                id: "\(block.kind.rawValue)-\(index)",
                kind: block.kind,
                text: block.text,
                imageURL: block.imageURL
            )
        }
    }

    static func rssImageRejectionReason(_ imageURL: String?) -> String? {
        guard let imageURL: String,
              let url: URL = URL(string: imageURL) else {
            return "invalid-url"
        }

        let lowercasedURL: String = imageURL.lowercased()
        let host: String = url.host?.lowercased() ?? ""

        if Self.isTemplateImageURL(lowercasedURL) {
            return "template-url"
        }

        if host.hasSuffix("gcores.com"), host != "image.gcores.com" {
            return "non-image-gcores-host"
        }

        if host == "www.beian.gov.cn" || host == "beian.gov.cn" {
            return "beian-icon"
        }

        if host == "a1.api.bbc.co.uk"
            || host == "sb.scorecardresearch.com"
            || host == "b.scorecardresearch.com"
            || lowercasedURL.contains("scorecardresearch.com") {
            return "tracking-pixel"
        }

        if Self.isUnsupportedVectorImage(url) {
            return "unsupported-vector"
        }

        if Self.isDirectoryImageURL(url) {
            return "directory-url"
        }

        let rejectedFragments: [String] = [
            "avatar",
            "favicon",
            "apple-touch-icon",
            "logo",
            "gonganbeian",
            "page_resources/misc",
            "/static/img/language",
            "/static/img/heart_",
            "footer-appdownload"
        ]
        if let fragment: String = rejectedFragments.first(where: { lowercasedURL.contains($0) }) {
            return "fragment:\(fragment)"
        }

        if let smallImageMarker: String = Self.smallImageDimensionMarker(in: lowercasedURL) {
            return "small:\(smallImageMarker)"
        }

        return nil
    }

    private static func isDirectoryImageURL(_ url: URL) -> Bool {
        guard let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let components: URLComponents = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            return false
        }

        return components.percentEncodedPath.hasSuffix("/")
            && url.query == nil
            && url.fragment == nil
    }

    private func deduplicatedImageBlocks(_ imageBlocks: [RSSContentPayload.Block]) -> [RSSContentPayload.Block] {
        var deduplicatedBlocks: [RSSContentPayload.Block] = []
        var seenDedupeKeys: Set<String> = []

        for block in imageBlocks {
            guard let imageURL: String = block.imageURL else {
                continue
            }

            let dedupeKey: String = self.imageDedupeKey(for: imageURL)
            guard seenDedupeKeys.contains(dedupeKey) == false else {
                continue
            }

            seenDedupeKeys.insert(dedupeKey)
            deduplicatedBlocks.append(block)
        }

        return deduplicatedBlocks
    }

    private func imageDedupeKey(for imageURL: String) -> String {
        guard let url: URL = URL(string: imageURL) else {
            return imageURL
        }

        if Self.hasImageTransformQuery(url) {
            var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            return components?.url?.absoluteString ?? imageURL
        }

        return imageURL
    }

    private static func hasImageTransformQuery(_ url: URL) -> Bool {
        guard let query: String = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.lowercased() else {
            return false
        }

        return query.contains("imageview2") || query.contains("imagemogr2")
    }

    private static func isTemplateImageURL(_ lowercasedURL: String) -> Bool {
        return lowercasedURL.contains("${")
            || lowercasedURL.contains("%7b")
            || lowercasedURL.contains("escapehtml(")
            || lowercasedURL.contains("imgsmallurl")
            || lowercasedURL.contains("imgbannerurl")
            || lowercasedURL.contains("imgbigurl")
    }

    private static func isUnsupportedVectorImage(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "svg"
    }

    private static func smallImageDimensionMarker(in lowercasedURL: String) -> String? {
        let pattern: String = #"((?<![a-z0-9])[wh]_(?:20|30|40|50|60|80)(?![0-9])|!/both/(?:100x60|120x80|130x88))"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range: NSRange = NSRange(lowercasedURL.startIndex..<lowercasedURL.endIndex, in: lowercasedURL)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: lowercasedURL, range: range),
              match.numberOfRanges > 1,
              let markerRange: Range<String.Index> = Range(match.range(at: 1), in: lowercasedURL) else {
            return nil
        }

        return String(lowercasedURL[markerRange])
    }

    private func logRSSImageFilterSummary(
        rawDetailBlocks: [RSSContentPayload.Block],
        feedImageCount: Int,
        rejectedImageReasons: [String: Int],
        finalBlocks: [RSSContentPayload.Block]
    ) {
        #if DEBUG
        let rawDetailImageCount: Int = rawDetailBlocks.filter { block in
            block.kind == .image
        }.count
        let finalImageCount: Int = finalBlocks.filter { block in
            block.kind == .image
        }.count
        let rejectedImageCount: Int = rejectedImageReasons.values.reduce(0, +)
        print(
            "[BrowseCraftRSSDetail] image filter " +
            "itemID=\(self.item.id) " +
            "rawDetailImages=\(rawDetailImageCount) " +
            "feedImages=\(feedImageCount) " +
            "finalImages=\(finalImageCount) " +
            "rejectedImages=\(rejectedImageCount) " +
            "rejectedReasons=\(rejectedImageReasons)"
        )
        #endif
    }

    private func readingHistory() -> RSSReadingHistory {
        let timestamp: Date = self.now()

        return RSSReadingHistory(
            userID: AppUser.localDefaultID,
            sourceID: self.source.id,
            itemID: self.item.id,
            dataType: .article,
            title: self.displayItem.title,
            dataContent: self.dataContent(),
            dataTime: self.displayItem.updatedAt ?? timestamp,
            visitedAt: timestamp,
            detailURL: URL(string: self.displayItem.detailURL),
            sourceName: self.source.name,
            originFeedURL: self.originFeedURL(),
            sourceSnapshot: SourceSnapshot(source: self.source)
        )
    }

    private func dataContent() -> String {
        if let summary: String = RSSContentTextFormatter.sanitized(self.displayItem.latestText) {
            return summary
        }

        return self.displayItem.title
    }

    private func originFeedURL() -> URL? {
        guard case .rss(let configuration) = self.source.configuration else {
            return URL(string: self.source.baseURL)
        }

        return configuration.definition.feedURL
    }

    private func accumulateAdPoints(points: Int) {
        guard let accumulateAdPointsUseCase: AccumulateAdPointsUseCase = self.accumulateAdPointsUseCase else {
            return
        }

        do {
            let result: AdPointAccumulationResult = try accumulateAdPointsUseCase.execute(points: points)
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] RSS result " +
                "sourceID=\(self.source.id) itemID=\(self.item.id) " +
                "\(result.debugDescription)"
            )
            #endif
            if result.shouldPlayAd {
                #if DEBUG
                print(
                    "[BrowseCraftAdPlayback] RSS shouldPlayAd=true " +
                    "sourceID=\(self.source.id) itemID=\(self.item.id)"
                )
                #endif
                self.shouldPlayAd = true
            }
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] RSS accumulate failed " +
                "sourceID=\(self.source.id) " +
                "itemID=\(self.item.id) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func trimmedNonEmpty(_ string: String?) -> String? {
        let trimmed: String = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
