import Foundation

struct DiscoverComicResourcesInput: Hashable {
    var siteURLString: String
    var keyword: String
}

struct DiscoverComicResourcesUseCase {
    private static let maxResultCount: Int = 100

    private enum ItemRejectionReason: String {
        case emptyTitle
        case emptyHref
        case invalidURL
        case nonResourceURL
        case lowScore
        case duplicate

        #if DEBUG
        static func allCasesDescription(counts: [Self: Int]) -> String {
            let reasons: [Self] = [
                .emptyTitle,
                .emptyHref,
                .invalidURL,
                .nonResourceURL,
                .lowScore,
                .duplicate
            ]

            return reasons
                .map { reason in "\(reason.rawValue)=\(counts[reason, default: 0])" }
                .joined(separator: ",")
        }
        #endif
    }

    private enum ItemParseOutcome {
        case accepted(TransientComicDiscoveryItem, score: Int)
        case rejected(ItemRejectionReason)
    }

    private struct ParseItemsResult {
        var items: [TransientComicDiscoveryItem]
        var anchorCount: Int
        var embeddedCoverCount: Int
        var rejectionCounts: [ItemRejectionReason: Int]
    }

    static let defaultKeywords: [String] = [
        "漫画",
        "最近更新",
        "热门漫画",
        "连载",
        "完结"
    ]

    private let pageContentLoader: PageContentLoader
    private let urlResolver: URLResolvingService
    private let htmlScanner: HTMLDiscoveryScanner
    private let htmlParser: HTMLDiscoveryParsingService

    init(
        pageContentLoader: PageContentLoader,
        htmlParser: HTMLDiscoveryParsingService,
        urlResolver: URLResolvingService = URLResolvingService()
    ) {
        self.pageContentLoader = pageContentLoader
        self.urlResolver = urlResolver
        self.htmlScanner = HTMLDiscoveryScanner(urlResolver: urlResolver)
        self.htmlParser = htmlParser
    }

    func execute(_ input: DiscoverComicResourcesInput) async throws -> [TransientComicDiscoveryItem] {
        let siteURL: URL = try self.htmlScanner.siteURL(from: input.siteURLString)
        let keyword: String = input.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateURLs: [URL] = self.candidateSearchURLs(siteURL: siteURL, keyword: keyword)
        let request: RequestConfig = RequestConfig(needsWebView: true, autoScroll: true)
        var items: [TransientComicDiscoveryItem] = []
        var seenDetailURLs: Set<String> = Set<String>()

        #if DEBUG
        self.log(
            "start site=\(siteURL.absoluteString) keyword=\(keyword) candidates=\(candidateURLs.count)"
        )
        #endif

        for url: URL in candidateURLs {
            let html: String
            do {
                html = try await self.pageContentLoader.loadContent(
                    PageLoadRequest(url: url, requestConfig: request, sourceContext: nil)
                ).content
            } catch {
                #if DEBUG
                self.log("fetch-failed url=\(url.absoluteString) error=\(error.localizedDescription)")
                #endif
                continue
            }

            let parseResult: ParseItemsResult = try self.parseItems(
                html: html,
                pageURL: url,
                keyword: keyword
            )

            #if DEBUG
            self.logParseResult(parseResult, url: url, html: html)
            #endif

            for item: TransientComicDiscoveryItem in parseResult.items where seenDetailURLs.contains(item.detailURL) == false {
                seenDetailURLs.insert(item.detailURL)
                items.append(item)
            }

            if items.count >= Self.maxResultCount {
                break
            }
        }

        #if DEBUG
        self.log("finished resultCount=\(min(items.count, Self.maxResultCount))")
        for (index, item) in Array(items.prefix(Self.maxResultCount)).enumerated() {
            self.log("result[\(index)] title=\(item.title) url=\(item.detailURL) cover=\(item.coverURL ?? "nil")")
        }
        #endif

        return Array(items.prefix(Self.maxResultCount))
    }

    private func candidateSearchURLs(siteURL: URL, keyword: String) -> [URL] {
        let host: String = siteURL.host?.lowercased() ?? ""
        return self.htmlScanner.candidateSearchURLs(
            siteURL: siteURL,
            keyword: keyword,
            preferredPathBuilders: [
                { encodedKeyword in
                    return host.contains("komiic.com") || host.contains("komiic.cc")
                        ? ["/search/\(encodedKeyword)"]
                        : []
                }
            ],
            additionalRawCandidates: []
        )
    }

    private func parseItems(
        html: String,
        pageURL: URL,
        keyword: String
    ) throws -> ParseItemsResult {
        let anchors: [HTMLDiscoveryAnchorSnapshot] = try self.htmlParser.parseAnchors(
            html: html,
            pageURL: pageURL
        )
        let embeddedCoverURLMap: [String: String] = self.embeddedCoverURLMap(html: html, pageURL: pageURL)
        var items: [TransientComicDiscoveryItem] = []
        var seenURLs: Set<String> = Set<String>()
        var rejectionCounts: [ItemRejectionReason: Int] = [:]

        for anchor: HTMLDiscoveryAnchorSnapshot in anchors {
            let outcome: ItemParseOutcome = try self.item(
                from: anchor,
                pageURL: pageURL,
                keyword: keyword,
                embeddedCoverURLMap: embeddedCoverURLMap
            )

            switch outcome {
            case .accepted(let item, let score):
                guard seenURLs.contains(item.detailURL) == false else {
                    rejectionCounts[.duplicate, default: 0] += 1
                    continue
                }

                seenURLs.insert(item.detailURL)
                items.append(item)

                #if DEBUG
                self.log("accepted score=\(score) title=\(item.title) url=\(item.detailURL)")
                #endif
            case .rejected(let reason):
                rejectionCounts[reason, default: 0] += 1
                continue
            }
        }

        return ParseItemsResult(
            items: items,
            anchorCount: anchors.count,
            embeddedCoverCount: embeddedCoverURLMap.count,
            rejectionCounts: rejectionCounts
        )
    }

    private func item(
        from anchor: HTMLDiscoveryAnchorSnapshot,
        pageURL: URL,
        keyword: String,
        embeddedCoverURLMap: [String: String]
    ) throws -> ItemParseOutcome {
        let rawTitle: String = self.normalizedText(anchor.text)
        let title: String = self.cleanedTitle(self.htmlScanner.bestTitle(anchor: anchor, fallback: rawTitle))
        guard title.count >= 2 else {
            return .rejected(.emptyTitle)
        }

        let href: String = anchor.href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard href.isEmpty == false else {
            return .rejected(.emptyHref)
        }

        let detailURL: String = self.urlResolver.absoluteString(href, baseURLString: pageURL.absoluteString)
        guard detailURL.hasPrefix("http://") || detailURL.hasPrefix("https://") else {
            return .rejected(.invalidURL)
        }

        guard self.isLikelyComicResourceURL(detailURL, pageURL: pageURL) else {
            return .rejected(.nonResourceURL)
        }

        let score: Int = try self.comicScore(anchor: anchor, title: title, detailURL: detailURL, keyword: keyword)
        guard score >= 2 else {
            return .rejected(.lowScore)
        }

        return .accepted(
            TransientComicDiscoveryItem(
                id: detailURL,
                title: title,
                detailURL: detailURL,
                coverURL: try self.coverURL(anchor: anchor, detailURL: detailURL, pageURL: pageURL, embeddedCoverURLMap: embeddedCoverURLMap),
                latestText: try self.latestText(anchor: anchor),
                matchedKeyword: keyword,
                sourcePageURL: pageURL.absoluteString
            ),
            score: score
        )
    }

    private func isLikelyComicResourceURL(_ absoluteString: String, pageURL: URL) -> Bool {
        guard let url: URL = URL(string: absoluteString),
              let host: String = url.host?.lowercased() else {
            return false
        }

        let path: String = url.path.lowercased()
        guard path.isEmpty == false, path != "/" else {
            return false
        }

        if host.contains("komiic.com") || host.contains("komiic.cc") {
            return path.hasPrefix("/comic/")
        }

        if self.isWebtoonsTitleURL(url) {
            return true
        }

        let blockedPrefixes: [String] = [
            "/search",
            "/recent",
            "/updates",
            "/hot",
            "/recommendations",
            "/about",
            "/login",
            "/register",
            "/profile",
            "/settings",
            "/favorite",
            "/folder",
            "/bookmarks",
            "/authors",
            "/mobile",
            "/donate",
            "/rss",
            "/assets",
            "/cdn-cgi"
        ]
        if blockedPrefixes.contains(where: { prefix in path == prefix || path.hasPrefix("\(prefix)/") }) {
            return false
        }

        let resourceMarkers: [String] = [
            "/comic/",
            "/comics/",
            "/manga/",
            "/manhua/",
            "/book/",
            "/series/",
            "/title/"
        ]
        if resourceMarkers.contains(where: { marker in path.contains(marker) }) {
            return true
        }

        return pageURL.host?.lowercased() == host
    }

    private func comicScore(anchor: HTMLDiscoveryAnchorSnapshot, title: String, detailURL: String, keyword: String) throws -> Int {
        let parent: HTMLDiscoveryAncestorSnapshot? = anchor.ancestors.first
        let grandparent: HTMLDiscoveryAncestorSnapshot? = anchor.ancestors.dropFirst().first
        let parentText: String = parent?.text ?? ""
        let anchorClassName: String = anchor.className
        let parentClassName: String = parent?.className ?? ""
        let grandparentClassName: String = grandparent?.className ?? ""
        let classNames: String = [
            anchorClassName,
            parentClassName,
            grandparentClassName
        ].joined(separator: " ")
        let haystack: String = "\(title) \(detailURL) \(parentText) \(classNames)".lowercased()
        let comicMarkers: [String] = [
            "漫画", "manhua", "manga", "comic", "chapter", "章节", "最新", "更新", "连载", "完结", "话", "卷"
        ]
        var score: Int = 0

        if keyword.isEmpty == false && haystack.contains(keyword.lowercased()) {
            score += 2
        }

        for marker: String in comicMarkers where haystack.contains(marker.lowercased()) {
            score += 1
        }

        if anchor.hasImage {
            score += 1
        }

        if let url: URL = URL(string: detailURL), self.isWebtoonsTitleURL(url) {
            score += 2
        }

        return score
    }

    private func isWebtoonsTitleURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased(),
              host.contains("webtoons.com") else {
            return false
        }

        let path: String = url.path.lowercased()
        guard path.hasSuffix("/list") || path.contains("/list/") else {
            return false
        }

        let components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains(where: { item in item.name == "title_no" }) == true
    }

    private func coverURL(
        anchor: HTMLDiscoveryAnchorSnapshot,
        detailURL: String,
        pageURL: URL,
        embeddedCoverURLMap: [String: String]
    ) throws -> String? {
        for rawURL: String in anchor.coverURLCandidates {
            let absoluteURL: String = self.urlResolver.absoluteString(rawURL, baseURLString: pageURL.absoluteString)
            if self.htmlScanner.isBlockedCoverURLString(absoluteURL) == false {
                return absoluteURL
            }
        }

        return embeddedCoverURLMap[self.normalizedURLKey(detailURL)]
    }

    private func embeddedCoverURLMap(html: String, pageURL: URL) -> [String: String] {
        let normalizedHTML: String = self.normalizedEmbeddedHTML(html)
        let host: String = pageURL.host?.lowercased() ?? ""
        let root: String = "\(pageURL.scheme ?? "https")://\(pageURL.host ?? "")"
        var map: [String: String] = [:]

        let idThenImagePattern: String = #""id"\s*:\s*"?(\d+)"?.{0,1600}?"(?:imageUrl|coverUrl)"\s*:\s*"([^"]+)""#
        for match: [String] in self.matches(in: normalizedHTML, pattern: idThenImagePattern) where match.count >= 3 {
            let detailURL: String = self.urlResolver.absoluteString("/comic/\(match[1])", baseURLString: root)
            if let coverURL: String = self.absoluteEmbeddedCoverURLString(match[2], pageURL: pageURL, host: host) {
                map[self.normalizedURLKey(detailURL)] = coverURL
            }
        }

        let imageThenIDPattern: String = #""(?:imageUrl|coverUrl)"\s*:\s*"([^"]+)".{0,1600}?"id"\s*:\s*"?(\d+)"?"#
        for match: [String] in self.matches(in: normalizedHTML, pattern: imageThenIDPattern) where match.count >= 3 {
            let detailURL: String = self.urlResolver.absoluteString("/comic/\(match[2])", baseURLString: root)
            if map[self.normalizedURLKey(detailURL)] == nil,
               let coverURL: String = self.absoluteEmbeddedCoverURLString(match[1], pageURL: pageURL, host: host) {
                map[self.normalizedURLKey(detailURL)] = coverURL
            }
        }

        return map
    }

    private func normalizedEmbeddedHTML(_ html: String) -> String {
        return html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
    }

    private func absoluteEmbeddedCoverURLString(_ rawValue: String, pageURL: URL, host: String) -> String? {
        let value: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.htmlScanner.isUsableCoverURLString(value) else {
            return nil
        }

        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("/") || value.hasPrefix("//") {
            return self.urlResolver.absoluteString(value, baseURLString: pageURL.absoluteString)
        }

        if host.contains("komiic.com") || host.contains("komiic.cc") {
            return self.urlResolver.absoluteString("/api/image/\(value)", baseURLString: pageURL.absoluteString)
        }

        return nil
    }

    private func normalizedURLKey(_ value: String) -> String {
        guard let components: URLComponents = URLComponents(string: value),
              let scheme: String = components.scheme?.lowercased(),
              let host: String = components.host?.lowercased() else {
            return value.lowercased()
        }

        return "\(scheme)://\(host)\(components.path)"
    }

    private func matches(in text: String, pattern: String) -> [[String]] {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            return (0..<match.numberOfRanges).compactMap { index -> String? in
                guard let range: Range<String.Index> = Range(match.range(at: index), in: text) else {
                    return nil
                }

                return String(text[range])
            }
        }
    }

    private func latestText(anchor: HTMLDiscoveryAnchorSnapshot) throws -> String? {
        let text: String = anchor.ancestors.first?.text ?? anchor.text
        let markers: [String] = ["最新", "更新", "连载", "完结", "第", "话", "卷"]
        guard markers.contains(where: { marker in text.contains(marker) }) else {
            return nil
        }

        return String(self.normalizedText(text).prefix(80))
    }

    private func normalizedText(_ text: String) -> String {
        return self.htmlScanner.normalizedText(text)
    }

    private func cleanedTitle(_ title: String) -> String {
        let markers: [String] = [
            " 连载",
            " 完结",
            " 更新",
            " 暂停",
            " 休刊"
        ]
        let numericSuffixPattern: String = #" \d+(\.\d+)?[万千]?( \d+(\.\d+)?[万千]?){0,3}$"#
        var cleaned: String = title

        for marker: String in markers {
            if let range: Range<String.Index> = cleaned.range(of: marker) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        cleaned = cleaned.replacingOccurrences(
            of: numericSuffixPattern,
            with: "",
            options: .regularExpression
        )

        return self.normalizedText(cleaned)
    }

    #if DEBUG
    private func logParseResult(_ result: ParseItemsResult, url: URL, html: String) {
        let rejectionSummary: String = ItemRejectionReason.allCasesDescription(
            counts: result.rejectionCounts
        )
        self.log(
            "parsed url=\(url.absoluteString) htmlBytes=\(html.utf8.count) anchors=\(result.anchorCount) embeddedCovers=\(result.embeddedCoverCount) accepted=\(result.items.count) rejected={\(rejectionSummary)}"
        )
    }

    private func log(_ message: String) {
        print("[BrowseCraftComicDiscovery] \(message)")
    }
    #endif
}
