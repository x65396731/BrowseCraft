import BrowseCraftCore
import BrowseCraftLog
import Foundation
import ReadiumShared

// 中文注释：站点有声作品的音频请求客户端。AVFoundation 只看到 Readium 的自定义 scheme（readiumhttp://…），
// 真正发网络请求的是这里的 DefaultHTTPClient——App 没有全局 ATS 例外，http 地址在这里升级成 https 再发
//（2026-09-14 loyalbooks 模拟器复验：规则产出的 mp3 是 http://www.archive.org/…，URLSession 报 -1022 被 ATS 拦下）。
// 播放页型有声章节（fwq 设计稿第 46 节 A1）：出版物里登记的是章节播放页，请求发出前经 `SiteBookPageAudioResolver`
// 取页解析出真正的音频地址并改写请求，同时带上规则给的请求头，没给 Referer 时以章节页为 Referer（A2）。
// DefaultHTTPClient 对代理是弱引用，本对象由出版物容器持有。

/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：成员全不可变；Readium `DefaultHTTPClient` 未标 Sendable，代理回调由 URLSession 串行调用。
final class SiteBookAudioHTTPClient: DefaultHTTPClientDelegate, @unchecked Sendable {
    let client: DefaultHTTPClient
    private let pageAudioResolver: SiteBookPageAudioResolver?

    init(configuration: URLSessionConfiguration = .default, pageAudioResolver: SiteBookPageAudioResolver? = nil) {
        self.client = DefaultHTTPClient(configuration: configuration)
        self.pageAudioResolver = pageAudioResolver
        self.client.delegate = self
    }

    func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible> {
        guard let resolver: SiteBookPageAudioResolver = self.pageAudioResolver else {
            return .success(Self.upgradedToHTTPS(request))
        }
        do {
            guard let resolved: SiteBookResolvedAudio = try await resolver.resolve(request.url.url) else {
                return .success(Self.upgradedToHTTPS(request))
            }
            return .success(Self.upgradedToHTTPS(Self.redirected(request, to: resolved)))
        } catch {
            return .failure(.other(error))
        }
    }

    /// 中文注释：规则请求的公共钩子（BCA-OBS-014）：有声书音频请求的响应与失败在这里记。
    func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didReceiveResponse response: HTTPResponse) {
        AppLog.info(.network, "audio-response", [
            "host": .host(request.url.url),
            "path": .path(request.url.url),
            "status": .int(response.status.rawValue)
        ])
    }

    func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didFailWithError error: HTTPError) {
        AppLog.error(.network, "audio-request-failed", [
            "host": .host(request.url.url),
            "path": .path(request.url.url),
            "error": .error(error)
        ])
    }

    /// 中文注释：http → https，其余原样；升级后不再回退 http（回退也会被 ATS 拦，没有意义）。
    static func upgradedToHTTPS(_ request: HTTPRequest) -> HTTPRequest {
        let url: URL = request.url.url
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return request
        }
        components.scheme = "https"
        guard let upgradedURL: URL = components.url, let httpURL: HTTPURL = HTTPURL(url: upgradedURL) else {
            return request
        }
        var upgraded: HTTPRequest = request
        upgraded.url = httpURL
        return upgraded
    }

    /// 中文注释：把播放页请求改写成解析出的音频地址；请求原有的头（Range 等）保留，解析结果的头只补缺。
    static func redirected(_ request: HTTPRequest, to resolved: SiteBookResolvedAudio) -> HTTPRequest {
        guard let url: HTTPURL = HTTPURL(url: resolved.url) else {
            return request
        }
        var redirected: HTTPRequest = request
        redirected.url = url
        let existing: Set<String> = Set(request.headers.keys.map { $0.lowercased() })
        for (name, value) in resolved.headers where existing.contains(name.lowercased()) == false {
            redirected.headers[name] = value
        }
        return redirected
    }
}

/// 中文注释：播放页解析出的音频地址与请求头。
struct SiteBookResolvedAudio: Hashable, Sendable {
    let url: URL
    let headers: [String: String]
}

/// 中文注释：播放页型有声章节的地址解析（fwq 设计稿第 46 节 A1 / A2）。一章只取一次页：同一章的多次 Range 请求
/// 共用第一次的结果；取页失败不缓存，下次请求重试。不是登记过的播放页时返回 nil（请求原样发出）。
actor SiteBookPageAudioResolver {
    private let chapters: [String: URL]
    private let provider: BookChapterContentProvider
    private var tasks: [String: Task<SiteBookResolvedAudio, Error>] = [:]

    init(chapters: [URL], provider: @escaping BookChapterContentProvider) {
        var byKey: [String: URL] = [:]
        for chapter: URL in chapters {
            byKey[chapter.absoluteString] = chapter
        }
        self.chapters = byKey
        self.provider = provider
    }

    func resolve(_ url: URL) async throws -> SiteBookResolvedAudio? {
        let key: String = url.absoluteString
        guard let chapterURL: URL = self.chapters[key] else {
            return nil
        }
        if let task: Task<SiteBookResolvedAudio, Error> = self.tasks[key] {
            return try await task.value
        }
        let provider: BookChapterContentProvider = self.provider
        let task: Task<SiteBookResolvedAudio, Error> = Task {
            return try await Self.load(chapterURL, provider: provider)
        }
        self.tasks[key] = task
        do {
            return try await task.value
        } catch {
            self.tasks[key] = nil
            throw error
        }
    }

    private static func load(_ chapterURL: URL, provider: BookChapterContentProvider) async throws -> SiteBookResolvedAudio {
        guard case .audio(let items) = try await provider(chapterURL), let first: SourceBookAudioItem = items.first else {
            throw BookPublicationContentError.unexpectedContent(chapterURL: chapterURL)
        }
        var headers: [String: String] = first.headers
        if headers.keys.contains(where: { $0.lowercased() == "referer" }) == false {
            headers["Referer"] = chapterURL.absoluteString
        }
        return SiteBookResolvedAudio(url: first.url, headers: headers)
    }
}
