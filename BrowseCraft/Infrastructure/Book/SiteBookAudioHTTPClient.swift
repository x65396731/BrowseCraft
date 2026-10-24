import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog
import Foundation
import ReadiumShared

// 中文注释：站点有声作品的音频请求客户端。AVFoundation 只看到 Readium 的自定义 scheme（readiumhttp://…），
// 真正发网络请求的是这里的 DefaultHTTPClient——App 没有全局 ATS 例外，http 地址在这里升级成 https 再发
//（2026-09-14 loyalbooks 模拟器复验：规则产出的 mp3 是 http://www.archive.org/…，URLSession 报 -1022 被 ATS 拦下）。
// 播放页型有声章节（fwq 设计稿第 46 节 A1）：出版物里登记的是章节播放页，请求发出前经 `SiteBookPageAudioResolver`
// 取页解析出真正的音频地址并改写请求，同时带上规则给的请求头，没给 Referer 时以章节页为 Referer（A2）。
// DefaultHTTPClient 对代理是弱引用，本对象由出版物容器持有。

/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：除 `requestedChapters` 外成员全不可变，`requestedChapters` 只在锁内读写；
/// Readium `DefaultHTTPClient` 未标 Sendable，代理回调由 URLSession 串行调用。
final class SiteBookAudioHTTPClient: DefaultHTTPClientDelegate, @unchecked Sendable {
    let client: DefaultHTTPClient
    private let pageAudioResolver: SiteBookPageAudioResolver?
    /// 中文注释：单集音频取不到时告诉播放页（`APP-MEMO-043`）；nil 时只记日志。
    private let failureHandler: BookAudioResourceFailureHandler?
    /// 中文注释：发出去的请求地址（升级 https、改写成解析出的音频地址之后）→ 出版物里登记的这一集地址，失败时按它对回是哪一集。
    private var requestedChapters: [String: URL] = [:]
    private let lock: NSLock = NSLock()

    init(
        configuration: URLSessionConfiguration = .default,
        pageAudioResolver: SiteBookPageAudioResolver? = nil,
        failureHandler: BookAudioResourceFailureHandler? = nil
    ) {
        self.client = DefaultHTTPClient(configuration: configuration)
        self.pageAudioResolver = pageAudioResolver
        self.failureHandler = failureHandler
        self.client.delegate = self
    }

    func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible> {
        let chapterURL: URL = request.url.url
        guard let resolver: SiteBookPageAudioResolver = self.pageAudioResolver else {
            return .success(self.remembering(Self.upgradedToHTTPS(request), chapterURL: chapterURL))
        }
        do {
            guard let resolved: SiteBookResolvedAudio = try await resolver.resolve(chapterURL) else {
                return .success(self.remembering(Self.upgradedToHTTPS(request), chapterURL: chapterURL))
            }
            return .success(self.remembering(Self.upgradedToHTTPS(Self.redirected(request, to: resolved)), chapterURL: chapterURL))
        } catch {
            // 中文注释：取播放页就失败了，请求不会发出，`didFailWithError` 也不会回调，在这里报。
            self.reportFailure(chapterURL: chapterURL, kind: Self.failureKind(resolverError: error), statusCode: Self.statusCode(of: error))
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
        guard let kind: BookAudioResourceFailure.Kind = Self.failureKind(httpError: error) else {
            return
        }
        let chapterURL: URL = self.chapterURL(forRequestURL: request.url.url) ?? request.url.url
        self.reportFailure(chapterURL: chapterURL, kind: kind, statusCode: Self.statusCode(of: error))
    }

    /// 中文注释：HTTP 失败的分类：404 / 403 / 410 算站点上已失效，其余暂时性失败可重试；取消（AVPlayer 换 Range、换集）不算失败。
    static func failureKind(httpError: HTTPError) -> BookAudioResourceFailure.Kind? {
        switch httpError {
        case .cancelled:
            return nil
        case .errorResponse(let response):
            return BookAudioResourceFailure.kind(statusCode: response.status.rawValue)
        case .other(let error):
            return Self.failureKind(resolverError: error)
        default:
            return .unavailable
        }
    }

    /// 中文注释：播放页型章节取页失败：页面上解不出音频算已失效；取页本身回 404 / 403 / 410 也算；其余可重试。
    static func failureKind(resolverError: Error) -> BookAudioResourceFailure.Kind {
        if resolverError is BookPublicationContentError {
            return .gone
        }
        if case RuleExecutionError.httpStatus(_, let statusCode) = resolverError {
            return BookAudioResourceFailure.kind(statusCode: statusCode)
        }
        return .unavailable
    }

    static func statusCode(of error: Error) -> Int? {
        if case HTTPError.errorResponse(let response) = error {
            return response.status.rawValue
        }
        if case RuleExecutionError.httpStatus(_, let statusCode) = error {
            return statusCode
        }
        return nil
    }

    private func remembering(_ request: HTTPRequest, chapterURL: URL) -> HTTPRequest {
        self.lock.lock()
        self.requestedChapters[request.url.url.absoluteString] = chapterURL
        self.lock.unlock()
        return request
    }

    private func chapterURL(forRequestURL url: URL) -> URL? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.requestedChapters[url.absoluteString]
    }

    private func reportFailure(chapterURL: URL, kind: BookAudioResourceFailure.Kind, statusCode: Int?) {
        AppLog.notice(.network, "audio-chapter-unavailable", [
            "host": .host(chapterURL),
            "path": .path(chapterURL),
            "kind": .code(kind == .gone ? "gone" : "unavailable"),
            "status": .int(statusCode ?? 0)
        ])
        self.failureHandler?(BookAudioResourceFailure(chapterURL: chapterURL, kind: kind, statusCode: statusCode))
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
