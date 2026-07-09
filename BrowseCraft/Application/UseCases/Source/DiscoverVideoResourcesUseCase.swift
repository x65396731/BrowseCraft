import Foundation
import SwiftSoup

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

    init(
        pageContentLoader: PageContentLoader,
        urlResolver: URLResolvingService = URLResolvingService()
    ) {
        self.pageContentLoader = pageContentLoader
        self.urlResolver = urlResolver
    }

    func execute(_ input: DiscoverVideoResourcesInput) async throws -> [TransientVideoDiscoveryItem] {
        let siteURL: URL = try self.siteURL(from: input.siteURLString)
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
                html = try await self.pageContentLoader.getString(from: url, request: request)
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

    private func siteURL(from rawValue: String) throws -> URL {
        let trimmed: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            normalized = trimmed
        } else {
            normalized = "https://\(trimmed)"
        }

        guard let url: URL = URL(string: normalized),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw URLResolvingError.invalidURL(rawValue)
        }

        return url
    }

    private func candidateSearchURLs(siteURL: URL, keyword: String) -> [URL] {
        var urls: [URL] = []
        guard keyword.isEmpty == false,
              let encodedKeyword: String = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return [siteURL]
        }

        let baseURLString: String = siteURL.absoluteString
        let root: String = "\(siteURL.scheme ?? "https")://\(siteURL.host ?? "")"
        let sitePath: String = siteURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var preferredCandidates: [String] = []
        if sitePath.isEmpty == false {
            let scopedPath: String = "/\(sitePath)"
            preferredCandidates.append("\(scopedPath)/search?keyword=\(encodedKeyword)")
            preferredCandidates.append("\(scopedPath)/search?q=\(encodedKeyword)")
            preferredCandidates.append("\(scopedPath)/vodsearch/\(encodedKeyword)----------.html")
        }

        let rawCandidates: [String] = preferredCandidates + [
            "/search?keyword=\(encodedKeyword)",
            "/search?q=\(encodedKeyword)",
            "/search?wd=\(encodedKeyword)",
            "/?s=\(encodedKeyword)",
            "/search/\(encodedKeyword)",
            "/so/\(encodedKeyword)",
            "/vodsearch/\(encodedKeyword)----------.html",
            siteURL.path.isEmpty || siteURL.path == "/" ? "/" : siteURL.path
        ]

        for rawCandidate: String in rawCandidates {
            let absoluteString: String = self.urlResolver.absoluteString(rawCandidate, baseURLString: root)
            if let url: URL = URL(string: absoluteString),
               urls.contains(url) == false {
                urls.append(url)
            }
        }

        if let url: URL = URL(string: baseURLString), urls.contains(url) == false {
            urls.append(url)
        }

        return urls
    }

    private func parseItems(
        html: String,
        pageURL: URL,
        keyword: String
    ) throws -> ParseItemsResult {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let anchors: [Element] = try document.select("a[href]").array()
        var items: [TransientVideoDiscoveryItem] = []
        var seenURLs: Set<String> = Set<String>()
        var rejectionCounts: [ItemRejectionReason: Int] = [:]

        for anchor: Element in anchors {
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
        from anchor: Element,
        pageURL: URL,
        keyword: String
    ) throws -> ItemParseOutcome {
        let rawTitle: String = self.normalizedText(try anchor.text())
        let title: String = self.cleanedTitle(self.bestTitle(anchor: anchor, fallback: rawTitle))
        guard title.count >= 2 else {
            return .rejected(.emptyTitle)
        }
        guard self.isBlockedUtilityTitle(title) == false else {
            return .rejected(.nonResourceURL)
        }

        let href: String = try anchor.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func bestTitle(anchor: Element, fallback: String) -> String {
        if fallback.isEmpty == false {
            return fallback
        }

        let titleAttribute: String = (try? anchor.attr("title")) ?? ""
        let title: String = self.normalizedText(titleAttribute)
        if title.isEmpty == false {
            return title
        }

        if let images: Elements = try? anchor.select("img"),
           let image: Element = images.first(),
           let imageAlt: String = try? image.attr("alt") {
            return self.normalizedText(imageAlt)
        }

        return ""
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

    private func videoScore(anchor: Element, title: String, detailURL: String, keyword: String) throws -> Int {
        let parent: Element? = anchor.parent()
        let grandparent: Element? = parent?.parent()
        let parentText: String = parent.flatMap { element in try? element.text() } ?? ""
        let anchorClassName: String = (try? anchor.className()) ?? ""
        let parentClassName: String = parent.flatMap { element in try? element.className() } ?? ""
        let grandparentClassName: String = grandparent.flatMap { element in try? element.className() } ?? ""
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

        if try anchor.select("img").isEmpty() == false {
            score += 1
        }

        if self.isDirectMediaURL(detailURL) {
            score += 4
        }

        return score
    }

    private func coverURL(anchor: Element, pageURL: URL) throws -> String? {
        let containers: [Element] = self.coverSearchContainers(startingAt: anchor)
        for container: Element in containers {
            if let rawURL: String = try self.coverURLString(from: container) {
                let absoluteURL: String = self.urlResolver.absoluteString(rawURL, baseURLString: pageURL.absoluteString)
                if self.isBlockedCoverURLString(absoluteURL) == false {
                    return absoluteURL
                }
            }
        }

        return nil
    }

    private func coverSearchContainers(startingAt anchor: Element) -> [Element] {
        var containers: [Element] = [anchor]
        var current: Element? = anchor
        for _ in 0..<12 {
            guard let parent: Element = current?.parent() else {
                break
            }

            containers.append(parent)
            current = parent
        }

        return containers
    }

    private func coverURLString(from container: Element) throws -> String? {
        let selector: String = [
            "img[data-original]",
            "img[data-src]",
            "img[data-lazy-src]",
            "img[data-srcset]",
            "img[srcset]",
            "img[src]",
            "source[data-srcset]",
            "source[srcset]",
            "picture source[data-srcset]",
            "picture source[srcset]",
            "[style*=\"background-image\"]",
            "[style*=\"url(\"]"
        ].joined(separator: ",")
        let elements: [Element]
        if try container.select(selector).isEmpty() == false {
            elements = try container.select(selector).array()
        } else {
            elements = [container]
        }

        for element: Element in elements {
            if let value: String = try self.directCoverURLString(from: element) {
                return value
            }
        }

        return nil
    }

    private func directCoverURLString(from element: Element) throws -> String? {
        let directAttributes: [String] = [
            "data-original",
            "data-src",
            "data-lazy-src",
            "data-thumb",
            "data-image",
            "data-img",
            "data-poster",
            "poster",
            "content",
            "src"
        ]
        for attributeName: String in directAttributes {
            let value: String = try element.attr(attributeName).trimmingCharacters(in: .whitespacesAndNewlines)
            if self.isUsableCoverURLString(value) {
                return value
            }
        }

        if let value: String = self.firstSrcsetURL(try element.attr("data-srcset")) {
            return value
        }

        if let value: String = self.firstSrcsetURL(try element.attr("srcset")) {
            return value
        }

        return self.firstStyleURL(try element.attr("style"))
    }

    private func firstSrcsetURL(_ srcset: String) -> String? {
        return srcset
            .split(separator: ",")
            .lazy
            .compactMap { candidate -> String? in
                let value: String? = candidate
                    .split(whereSeparator: { character in
                        return character.isWhitespace
                    })
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard let value: String, self.isUsableCoverURLString(value) else {
                    return nil
                }

                return value
            }
            .first
    }

    private func firstStyleURL(_ style: String) -> String? {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: #"url\((?:'|")?([^)'"]+)(?:'|")?\)"#
        ) else {
            return nil
        }

        let range: NSRange = NSRange(style.startIndex..<style.endIndex, in: style)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: style, range: range),
              match.numberOfRanges > 1,
              let matchRange: Range<String.Index> = Range(match.range(at: 1), in: style) else {
            return nil
        }

        let value: String = String(style[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return self.isUsableCoverURLString(value) ? value : nil
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

    private func isUsableCoverURLString(_ value: String) -> Bool {
        return value.isEmpty == false
            && value.hasPrefix("data:") == false
            && value.hasPrefix("blob:") == false
            && value != "#"
    }

    private func isBlockedCoverURLString(_ value: String) -> Bool {
        let lowercasedValue: String = value.lowercased()
        return lowercasedValue.hasSuffix(".svg")
            || lowercasedValue.contains("/logo")
            || lowercasedValue.contains("logo-")
    }

    private func latestText(anchor: Element) throws -> String? {
        let text: String
        if let parent: Element = anchor.parent() {
            text = (try? parent.text()) ?? ""
        } else {
            text = (try? anchor.text()) ?? ""
        }
        let markers: [String] = ["最新", "更新", "上映", "第", "集", "季", "高清", "正片"]
        guard markers.contains(where: { marker in text.contains(marker) }) else {
            return nil
        }

        return String(self.normalizedText(text).prefix(80))
    }

    private func normalizedText(_ text: String) -> String {
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { part in part.isEmpty == false }
            .joined(separator: " ")
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
