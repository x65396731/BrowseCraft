import Foundation

enum RuntimeSourceImportKind: String, Hashable {
    case comic
    case rss
    case video
}

struct RuntimeSourcePreviewResult: Hashable {
    var kind: RuntimeSourceImportKind
    var entryURL: URL
    var title: String?
    var summary: String
    var logLines: [String]
}

struct RuntimeRSSDebugResult: Hashable {
    var entryURL: URL
    var byteCount: Int
    var rawPreview: String
    var feedTitle: String?
    var itemCount: Int?
    var firstItemTitle: String?
    var parserError: String?
    var logLines: [String]
}

enum RuntimeSourcePreviewError: LocalizedError, Equatable {
    case invalidURL
    case emptyRSSFeed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http or https URL."
        case .emptyRSSFeed:
            return "The RSS feed loaded but returned no items."
        }
    }
}

struct PreviewRuntimeSourceUseCase {
    private let pageContentLoader: PageContentLoader
    private let rssFeedLoader: any RSSFeedLoading
    private let videoSourceUseCase: AddVideoSourceUseCase

    init(
        pageContentLoader: PageContentLoader,
        rssFeedLoader: any RSSFeedLoading,
        videoSourceUseCase: AddVideoSourceUseCase
    ) {
        self.pageContentLoader = pageContentLoader
        self.rssFeedLoader = rssFeedLoader
        self.videoSourceUseCase = videoSourceUseCase
    }

    func execute(
        kind: RuntimeSourceImportKind,
        entryURLString: String,
        name: String? = nil
    ) async throws -> RuntimeSourcePreviewResult {
        switch kind {
        case .comic:
            return try await self.previewComic(entryURLString: entryURLString)
        case .rss:
            return try await self.previewRSS(entryURLString: entryURLString)
        case .video:
            return try self.previewVideo(entryURLString: entryURLString, name: name)
        }
    }

    func debugRSS(entryURLString: String) async throws -> RuntimeRSSDebugResult {
        let entryURL: URL = try self.url(from: entryURLString)
        let data: Data
        let rawString: String

        if let dataLoader: PageDataLoader = self.pageContentLoader as? PageDataLoader {
            data = try await dataLoader.getData(from: entryURL, request: nil)
            rawString = Self.string(from: data)
        } else {
            rawString = try await self.pageContentLoader.getString(from: entryURL, request: nil)
            data = Data(rawString.utf8)
        }

        var logLines: [String] = [
            "Feed URL: \(entryURL.absoluteString)",
            "Bytes: \(data.count)",
            "Raw preview chars: \(Self.rawPreview(from: rawString).count)"
        ]

        do {
            let feed: RSSFeed = try RSSFeedMapper().map(data)
            let firstTitle: String = feed.items.first?.title?.trimmedNonEmpty ?? "none"
            logLines.append("Parser: success")
            logLines.append("Feed title: \(feed.title ?? "none")")
            logLines.append("Items: \(feed.items.count)")
            logLines.append("First item: \(firstTitle)")

            return RuntimeRSSDebugResult(
                entryURL: entryURL,
                byteCount: data.count,
                rawPreview: Self.rawPreview(from: rawString),
                feedTitle: feed.title,
                itemCount: feed.items.count,
                firstItemTitle: firstTitle,
                parserError: nil,
                logLines: logLines
            )
        } catch {
            logLines.append("Parser: failed")
            logLines.append("Parser error: \(error.localizedDescription)")

            return RuntimeRSSDebugResult(
                entryURL: entryURL,
                byteCount: data.count,
                rawPreview: Self.rawPreview(from: rawString),
                feedTitle: nil,
                itemCount: nil,
                firstItemTitle: nil,
                parserError: error.localizedDescription,
                logLines: logLines
            )
        }
    }

    private func previewComic(entryURLString: String) async throws -> RuntimeSourcePreviewResult {
        let entryURL: URL = try self.url(from: entryURLString)
        let html: String = try await self.pageContentLoader.getString(from: entryURL, request: nil)
        let title: String? = self.htmlTitle(from: html)

        return RuntimeSourcePreviewResult(
            kind: .comic,
            entryURL: entryURL,
            title: title,
            summary: title ?? "HTML loaded.",
            logLines: [
                "URL: \(entryURL.absoluteString)",
                "HTML bytes: \(html.utf8.count)",
                "Title: \(title ?? "none")"
            ]
        )
    }

    private func previewRSS(entryURLString: String) async throws -> RuntimeSourcePreviewResult {
        let entryURL: URL = try self.url(from: entryURLString)
        let feed: RSSFeed = try await self.rssFeedLoader.load(feedURL: entryURL)
        if feed.items.isEmpty {
            throw RuntimeSourcePreviewError.emptyRSSFeed
        }
        let firstTitle: String = feed.items.first?.title?.trimmedNonEmpty ?? "none"

        return RuntimeSourcePreviewResult(
            kind: .rss,
            entryURL: entryURL,
            title: feed.title,
            summary: feed.title ?? "RSS feed loaded.",
            logLines: [
                "Feed URL: \(entryURL.absoluteString)",
                "Feed title: \(feed.title ?? "none")",
                "Items: \(feed.items.count)",
                "First item: \(firstTitle)"
            ]
        )
    }

    private func previewVideo(
        entryURLString: String,
        name: String?
    ) throws -> RuntimeSourcePreviewResult {
        let inspection: VideoSourceImportInspection = try self.videoSourceUseCase.inspect(
            entryURLString: entryURLString,
            name: name
        )

        return RuntimeSourcePreviewResult(
            kind: .video,
            entryURL: inspection.entryURL,
            title: inspection.sourceName,
            summary: "Video URL inspected.",
            logLines: inspection.logLines
        )
    }

    private func url(from string: String) throws -> URL {
        let trimmed: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url: URL = URL(string: trimmed),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw RuntimeSourcePreviewError.invalidURL
        }

        return url
    }

    private func htmlTitle(from html: String) -> String? {
        guard let range: Range<String.Index> = html.range(
            of: #"<title[^>]*>(.*?)</title>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let titleHTML: String = String(html[range])
        guard let start: String.Index = titleHTML.firstIndex(of: ">"),
              let end: String.Index = titleHTML.range(of: "</title>", options: .caseInsensitive)?.lowerBound else {
            return nil
        }

        return String(titleHTML[titleHTML.index(after: start)..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmedNonEmpty
    }

    private static func string(from data: Data) -> String {
        if let string: String = String(data: data, encoding: .utf8) {
            return string
        }

        return String(decoding: data, as: UTF8.self)
    }

    private static func rawPreview(from string: String) -> String {
        let limit: Int = 2_000
        if string.count <= limit {
            return string
        }

        return String(string.prefix(limit))
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
