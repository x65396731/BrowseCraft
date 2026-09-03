import Foundation
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：ViewModel 测试不碰网络；这些端口替身要么按脚本返回，要么直接失败。
struct TestPortError: Error, Equatable {
    let reason: String
}

struct StubPageDataLoader: PageDataLoader {
    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        throw TestPortError(reason: "No network for \(request.url.absoluteString)")
    }
}

struct StubPageContentLoader: PageContentLoader {
    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        throw TestPortError(reason: "No network for \(request.url.absoluteString)")
    }
}

final class ScriptedRSSFeedLoader: RSSFeedLoading, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var result: Result<RSSFeed, Error>
    private var recordedFeedURLs: [URL] = []

    init(result: Result<RSSFeed, Error> = .failure(TestPortError(reason: "Feed is not scripted."))) {
        self.result = result
    }

    var requestedFeedURLs: [URL] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedFeedURLs
    }

    func setResult(_ result: Result<RSSFeed, Error>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.result = result
    }

    func load(feedURL: URL) async throws -> RSSFeed {
        self.lock.lock()
        self.recordedFeedURLs.append(feedURL)
        let result: Result<RSSFeed, Error> = self.result
        self.lock.unlock()
        return try result.get()
    }
}

struct StubPublicURLPolicy: PublicURLChecking {
    func validate(_ url: URL) throws {}

    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
        return candidate.host == inputURL.host
    }
}

struct StubPreflightPageLoader: PreflightPageAcquiring {
    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        throw TestPortError(reason: "Preflight is not available in ViewModel tests.")
    }
}

struct StubPreflightRenderedPageLoader: PreflightRenderedPageAcquiring {
    @MainActor
    func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        throw TestPortError(reason: "Rendered preflight is not available in ViewModel tests.")
    }
}
