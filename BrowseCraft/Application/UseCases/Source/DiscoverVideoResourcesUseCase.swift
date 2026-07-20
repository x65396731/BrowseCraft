import Foundation

struct DiscoverVideoResourcesInput: Hashable {
    var siteURLString: String
    var keyword: String
}

struct DiscoverVideoResourcesUseCase {
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
        case accepted(TransientVideoDiscoveryItem, score: Int)
        case rejected(ItemRejectionReason)
    }

    private struct ParseItemsResult {
        var items: [TransientVideoDiscoveryItem]
        var anchorCount: Int
        var rejectionCounts: [ItemRejectionReason: Int]
    }

    static let defaultKeywords: [String] = [
        "电影",
        "电视剧",
        "动漫",
        "最新",
        "热门"
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

    func execute(_ input: DiscoverVideoResourcesInput) async throws -> [TransientVideoDiscoveryItem] {
        let siteURL: URL = try self.htmlScanner.siteURL(from: input.siteURLString)
        let keyword: String = input.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateURLs: [URL] = self.candidateSearchURLs(siteURL: siteURL, keyword: keyword)
        let request: RequestConfig = RequestConfig(needsWebView: true, autoScroll: true)
        var items: [TransientVideoDiscoveryItem] = []
        var seenDetailURLs: Set<String> = Set<String>()

        #if DEBUG
        self.log("start site=\(siteURL.absoluteString) keyword=\(keyword) candidates=\(candidateURLs.count)")
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

            for item: TransientVideoDiscoveryItem in parseResult.items where seenDetailURLs.contains(item.detailURL) == false {
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
            self.log("result[\(index)] title=\(item.title) url=\(item.detailURL) cover=\(item.coverURL ?? "nil") playback=\(item.playbackKind)")
        }
        #endif

        return Array(items.prefix(Self.maxResultCount))
    }

    private func candidateSearchURLs(siteURL: URL, keyword: String) -> [URL] {
        let sitePath: String = siteURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return self.htmlScanner.candidateSearchURLs(
            siteURL: siteURL,
            keyword: keyword,
            preferredPathBuilders: [
                { encodedKeyword in
                    guard sitePath.isEmpty == false else {
                        return []
                    }

                    return ["/\(sitePath)/vodsearch/\(encodedKeyword)----------.html"]
                }
            ],
            additionalRawCandidates: [
                "/vodsearch/{keyword}----------.html"
            ].map { candidate in
                guard let encodedKeyword: String = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    return candidate
                }

                return candidate.replacingOccurrences(of: "{keyword}", with: encodedKeyword)
            }
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
        var items: [TransientVideoDiscoveryItem] = []
        var seenURLs: Set<String> = Set<String>()
        var rejectionCounts: [ItemRejectionReason: Int] = [:]

        for anchor: HTMLDiscoveryAnchorSnapshot in anchors {
            let outcome: ItemParseOutcome = try self.item(
                from: anchor,
                pageURL: pageURL,
                keyword: keyword
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
            rejectionCounts: rejectionCounts
        )
    }

    private func item(
        from anchor: HTMLDiscoveryAnchorSnapshot,
        pageURL: URL,
        keyword: String
    ) throws -> ItemParseOutcome {
        let rawTitle: String = self.normalizedText(anchor.text)
        let title: String = self.cleanedTitle(self.htmlScanner.bestTitle(anchor: anchor, fallback: rawTitle))
        guard title.count >= 2 else {
            return .rejected(.emptyTitle)
        }
        guard self.isBlockedUtilityTitle(title) == false else {
            return .rejected(.nonResourceURL)
        }

        let href: String = anchor.href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard href.isEmpty == false else {
            return .rejected(.emptyHref)
        }

        let detailURL: String = self.urlResolver.absoluteString(href, baseURLString: pageURL.absoluteString)
        guard detailURL.hasPrefix("http://") || detailURL.hasPrefix("https://") else {
            return .rejected(.invalidURL)
        }

        guard self.isLikelyVideoResourceURL(detailURL, pageURL: pageURL) else {
            return .rejected(.nonResourceURL)
        }

        let score: Int = try self.videoScore(anchor: anchor, title: title, detailURL: detailURL, keyword: keyword)
        guard score >= 2 else {
            return .rejected(.lowScore)
        }

        return .accepted(
            TransientVideoDiscoveryItem(
                id: detailURL,
                title: title,
                detailURL: detailURL,
                coverURL: try self.coverURL(anchor: anchor, pageURL: pageURL),
                latestText: try self.latestText(anchor: anchor),
                matchedKeyword: keyword,
                sourcePageURL: pageURL.absoluteString,
                playbackKind: self.isDirectMediaURL(detailURL) ? .directMedia : .webPage
            ),
            score: score
        )
    }

    private func isLikelyVideoResourceURL(_ absoluteString: String, pageURL: URL) -> Bool {
        guard let url: URL = URL(string: absoluteString),
              let host: String = url.host?.lowercased() else {
            return false
        }

        let path: String = url.path.lowercased()
        let absoluteLowercasedString: String = absoluteString.lowercased()
        guard path.isEmpty == false, path != "/" else {
            return false
        }

        if self.isDirectMediaURL(absoluteString) {
            return true
        }

        let blockedExactPaths: Set<String> = [
            "/movie",
            "/movies",
            "/series",
            "/anime",
            "/variety",
            "/collections",
            "/favorites",
            "/calendar",
            "/movie-calendar",
            "/share",
            "/request",
            "/faq",
            "/contact"
        ]
        if blockedExactPaths.contains(path) {
            return false
        }

        let blockedURLFragments: [String] = [
            "login",
            "signin",
            "sign-in",
            "signup",
            "sign-up",
            "register",
            "logout",
            "account",
            "member",
            "user",
            "profile",
            "setting",
            "password",
            "forgot",
            "reset",
            "history",
            "favorite",
            "bookmark",
            "contact",
            "feedback",
            "request",
            "faq",
            "登录",
            "登入",
            "注册",
            "登出",
            "会员",
            "用户",
            "账号",
            "帳號",
            "收藏",
            "历史",
            "歷史",
            "求片",
            "反馈",
            "聯絡",
            "联系"
        ]
        if blockedURLFragments.contains(where: { fragment in absoluteLowercasedString.contains(fragment) }) {
            return false
        }

        let blockedPrefixes: [String] = [
            "/search",
            "/about",
            "/login",
            "/register",
            "/profile",
            "/settings",
            "/favorite",
            "/bookmarks",
            "/rss",
            "/assets",
            "/static",
            "/cdn-cgi"
        ]
        if blockedPrefixes.contains(where: { prefix in path == prefix || path.hasPrefix("\(prefix)/") }) {
            return false
        }

        let resourceMarkers: [String] = [
            "/video/",
            "/videos/",
            "/movie/",
            "/movies/",
            "/film/",
            "/watch/",
            "/play/",
            "/vod/",
            "/voddetail/",
            "/vodplay/",
            "/detail/",
            "/show/"
        ]
        if resourceMarkers.contains(where: { marker in path.contains(marker) }) {
            return true
        }

        return pageURL.host?.lowercased() == host
    }

    private func isBlockedUtilityTitle(_ title: String) -> Bool {
        let lowercasedTitle: String = title.lowercased()
        let blockedTitleFragments: [String] = [
            "login",
            "sign in",
            "signin",
            "register",
            "signup",
            "account",
            "profile",
            "settings",
            "password",
            "history",
            "favorite",
            "bookmark",
            "contact",
            "feedback",
            "faq",
            "登录",
            "登入",
            "注册",
            "登出",
            "会员",
            "用户",
            "账号",
            "帳號",
            "设置",
            "設定",
            "密码",
            "密碼",
            "收藏",
            "历史",
            "歷史",
            "求片",
            "常见问题",
            "常見問題",
            "联系我们",
            "聯絡我們",
            "反馈"
        ]

        return blockedTitleFragments.contains { fragment in
            lowercasedTitle.contains(fragment)
        }
    }

    private func videoScore(anchor: HTMLDiscoveryAnchorSnapshot, title: String, detailURL: String, keyword: String) throws -> Int {
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
        let videoMarkers: [String] = [
            "电影", "电视剧", "影视", "视频", "动漫", "综艺", "短剧",
            "movie", "film", "video", "watch", "play", "vod", "episode",
            "最新", "更新", "上映", "第", "集", "季", "高清", "正片"
        ]
        var score: Int = 0

        if keyword.isEmpty == false && haystack.contains(keyword.lowercased()) {
            score += 2
        }

        for marker: String in videoMarkers where haystack.contains(marker.lowercased()) {
            score += 1
        }

        if anchor.hasImage {
            score += 1
        }

        if self.isDirectMediaURL(detailURL) {
            score += 4
        }

        return score
    }

    private func coverURL(anchor: HTMLDiscoveryAnchorSnapshot, pageURL: URL) throws -> String? {
        for rawURL: String in anchor.coverURLCandidates {
            let absoluteURL: String = self.urlResolver.absoluteString(rawURL, baseURLString: pageURL.absoluteString)
            if self.htmlScanner.isBlockedCoverURLString(absoluteURL) == false {
                return absoluteURL
            }
        }

        return nil
    }

    private func isDirectMediaURL(_ value: String) -> Bool {
        guard let components: URLComponents = URLComponents(string: value) else {
            return false
        }

        let path: String = components.path.lowercased()
        return path.hasSuffix(".mp4")
            || path.hasSuffix(".m3u8")
            || path.hasSuffix(".mov")
            || path.hasSuffix(".m4v")
    }

    private func latestText(anchor: HTMLDiscoveryAnchorSnapshot) throws -> String? {
        let text: String = anchor.ancestors.first?.text ?? anchor.text
        let markers: [String] = ["最新", "更新", "上映", "第", "集", "季", "高清", "正片"]
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
            " 更新",
            " 最新",
            " 正片",
            " 高清",
            " 完结"
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
            "parsed url=\(url.absoluteString) htmlBytes=\(html.utf8.count) anchors=\(result.anchorCount) accepted=\(result.items.count) rejected={\(rejectionSummary)}"
        )
    }

    private func log(_ message: String) {
        print("[BrowseCraftVideoDiscovery] \(message)")
    }
    #endif
}
