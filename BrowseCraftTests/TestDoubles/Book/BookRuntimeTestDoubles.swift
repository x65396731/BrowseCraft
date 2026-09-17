import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：站点书运行时的测试替身：真实 catalog 夹具物化成 Source、按 URL 回夹具 HTML 的页面加载器、单运行时解析器。
// 原先私有在 BookSourceRuntimeEndToEndTests 里；阅读器 VM 的有声用例也要用，抽到这里共享。

final class BookRuntimeFixtureMarker {}

enum BookRuntimeFixtures {
    static func source(fixture: String) throws -> Source {
        let url: URL = try #require(Bundle(for: BookRuntimeFixtureMarker.self).url(forResource: fixture, withExtension: "json"))
        let catalog: [String: Any] = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let ruleJSON: Data = try JSONSerialization.data(withJSONObject: try #require(catalog["ruleJSON"]))
        let catalogSource: CatalogSource = CatalogSource(
            id: try #require(catalog["id"] as? String),
            name: try #require(catalog["name"] as? String),
            baseURL: try #require(catalog["baseURL"] as? String),
            kind: .book,
            ruleJSON: String(decoding: ruleJSON, as: UTF8.self)
        )
        return try CatalogSourceMaterializer().source(from: catalogSource, createdAt: Date(), updatedAt: Date())
    }

    static func context(sourceID: String) -> SourceRuntimeContext {
        return SourceRuntimeContext(sourceID: sourceID, pageID: nil, tabID: nil, ruleID: nil, requestOverride: nil, debugMode: false)
    }
}

struct SingleRuntimeResolver: SourceRuntimeResolving {
    let runtime: BookSourceRuntime
    func runtime(for source: Source) throws -> any SourceRuntime {
        return self.runtime
    }
}

/// 中文注释：按 URL 回夹具 HTML；没备的 URL 直接报错，避免测试静默走到网络。
final class FixturePageContentLoader: PageContentLoader, @unchecked Sendable {
    private let fixtures: [String: String]
    /// 中文注释：站点 302（sfacg 作品页 → 移动站）：请求地址 → 落点地址；夹具按请求地址取，`finalURL` 给落点。
    private let redirects: [String: String]
    private(set) var requestedURLs: [String] = []
    private let lock: NSLock = NSLock()

    init(fixtures: [String: String], redirects: [String: String] = [:]) {
        self.fixtures = fixtures
        self.redirects = redirects
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.lock.withLock {
            self.requestedURLs.append(request.url.absoluteString)
        }
        guard let name: String = self.fixtures[request.url.absoluteString],
              let url: URL = Bundle(for: BookRuntimeFixtureMarker.self).url(forResource: name, withExtension: "html") else {
            throw NSError(domain: "FixturePageContentLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "no fixture for \(request.url)"])
        }
        let finalURL: URL = self.redirects[request.url.absoluteString].flatMap { URL(string: $0) } ?? request.url
        return PageContentResponse(content: try String(contentsOf: url, encoding: .utf8), finalURL: finalURL)
    }
}
