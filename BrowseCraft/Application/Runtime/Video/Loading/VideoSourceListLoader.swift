import Foundation
import BrowseCraftCore

// 中文注释：VideoSourceListLoading 是 VideoSourceRuntime 的列表加载依赖，便于后续替换不同站点策略。
protocol VideoSourceListLoading {
    func loadList(
        _ input: SourceListInput,
        definition: SourceDefinition
    ) async throws -> SourceListOutput
}

// 中文注释：VideoSourceListLoader 负责 video source 的列表 URL 选择、页面加载和列表映射。
struct VideoSourceListLoader: VideoSourceListLoading {
    private let pageContentLoader: PageContentLoader
    private let mapper: any VideoContentMapper
    private let renderGuard: VideoHTMLRenderGuard
    private let requestConfigResolver: VideoRequestConfigResolver

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoContentMapper,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        requestConfigResolver: VideoRequestConfigResolver = VideoRequestConfigResolver()
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
        self.renderGuard = renderGuard
        self.requestConfigResolver = requestConfigResolver
    }

    func loadList(
        _ input: SourceListInput,
        definition: SourceDefinition
    ) async throws -> SourceListOutput {
        let url: URL = try self.listURL(for: input, definition: definition)
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        let request: RequestConfig? = self.requestConfigResolver.request(
            for: .list,
            definition: videoDefinition,
            context: input.context
        )
        let html: String
        let renderIssues: [SourceRuntimeIssue]
        do {
            html = try await self.pageContentLoader.getString(from: url, request: request)
            renderIssues = try self.renderGuard.validateMappableHTML(url: url, html: html, request: request)
        } catch {
            throw self.requestConfigResolver.mappedLoadingError(error, url: url)
        }

        if videoDefinition.entryKind == .play {
            let coverURL: URL? = self.coverURL(from: html, baseURL: url)
            #if DEBUG
            print(
                "[BrowseCraftVideoList] single-play-item " +
                "source=\(definition.id) " +
                "url=\(url.absoluteString) " +
                "cover=\(coverURL?.absoluteString ?? "nil")"
            )
            #endif
            let items: [SourceContentItem] = [
                SourceContentItem(
                    id: "\(definition.id).video.single.\(self.stableID(from: url))",
                    title: definition.name,
                    detailURL: url,
                    coverURL: coverURL,
                    latestText: "Single video",
                    updatedAt: nil
                )
            ]
            return SourceListOutput(
                items: items,
                pagination: nil,
                diagnostics: SourceRuntimeDiagnostics.succeeded(
                    requestLogs: [
                        self.requestConfigResolver.requestLog(
                            url: url,
                            request: request,
                            html: html
                        )
                    ],
                    issues: renderIssues,
                    context: SourceRuntimeDiagnosticContext(
                        runtimeContext: input.context,
                        requestURL: url
                    )
                )
            )
        }

        let items: [SourceContentItem] = try self.mapper.mapList(
            html: html,
            definition: definition,
            pageURL: url
        )
        let requestLogs: [SourceRequestLog] = [
            self.requestConfigResolver.requestLog(
                url: url,
                request: request,
                html: html
            )
        ]
        let issues: [SourceRuntimeIssue] = renderIssues
            + self.requestConfigResolver.emptyListIssues(items: items)

        return SourceListOutput(
            items: items,
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                requestLogs: requestLogs,
                issues: issues,
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: url
                )
            )
        )
    }

    private func listURL(
        for input: SourceListInput,
        definition: SourceDefinition
    ) throws -> URL {
        if let urlOverride: URL = input.urlOverride {
            return urlOverride
        }

        if let requestOverrideURL: URL = input.context.requestOverride?.url {
            return requestOverrideURL
        }

        return try self.entryURL(definition: definition)
    }

    private func entryURL(definition: SourceDefinition) throws -> URL {
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        return videoDefinition.entryURL
    }

    private func coverURL(from html: String, baseURL: URL) -> URL? {
        let patterns: [String] = [
            #"<meta[^>]+property=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image(?::secure_url)?["']"#,
            #"<meta[^>]+name=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image(?::src)?["']"#,
            #""thumbnail_url"\s*:\s*"([^"]+)""#,
            #""thumbnailUrl"\s*:\s*"([^"]+)""#,
            #"background:\s*url\((https?:\/\/[^)]+)\)"#,
            #"placeholderInit\([^;]+,\s*"([^"]+)""#
        ]

        for pattern: String in patterns {
            guard let value: String = self.normalizedURLString(
                    self.firstMatch(html, pattern: pattern)
                ),
                  let url: URL = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return url
        }

        if let youtubeURL: URL = self.youtubeThumbnailURL(from: baseURL) {
            return youtubeURL
        }

        return nil
    }

    private func normalizedURLString(_ value: String?) -> String? {
        return value?
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmedNonEmpty
    }

    private func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange: Range<String.Index> = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[valueRange])
    }

    private func stableID(from url: URL) -> String {
        let value: String = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")

        return value.isEmpty ? "root" : value
    }

    private func youtubeThumbnailURL(from url: URL) -> URL? {
        guard let host: String = url.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            return nil
        }

        let components: [String] = url.pathComponents.filter { component in
            component != "/"
        }
        let videoID: String?
        if components.first == "embed", components.count >= 2 {
            videoID = components[1]
        } else if host.contains("youtu.be"), let first: String = components.first {
            videoID = first
        } else {
            videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { item in item.name == "v" })?
                .value
        }

        guard let videoID: String = videoID?.trimmedNonEmpty else {
            return nil
        }

        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
