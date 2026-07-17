import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：SourceCredentialStore 测试，锁定登录态基础抽象的命中、过滤和过期行为。
struct SourceCredentialStoreTests {
    @Test func returnsCookieHeaderForMatchingSourceAndURL() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let cookie: HTTPCookie = try self.makeCookie(
            name: "session",
            value: "abc",
            domain: "example.test",
            path: "/reader"
        )
        let context: SourceRequestContext = SourceRequestContext(
            sourceID: "example",
            baseURL: try #require(URL(string: "https://example.test")),
            purpose: .reader
        )

        store.save(
            SourceCredential(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://example.test")),
                cookies: [cookie]
            )
        )

        let cookieHeader: String? = store.cookieHeader(
            for: context,
            url: try #require(URL(string: "https://example.test/reader/1"))
        )

        #expect(cookieHeader == "session=abc")
    }

    @Test func filtersCookieByDomainAndPath() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let matchingCookie: HTTPCookie = try self.makeCookie(
            name: "session",
            value: "abc",
            domain: "example.test",
            path: "/reader"
        )
        let pathMismatchCookie: HTTPCookie = try self.makeCookie(
            name: "admin",
            value: "secret",
            domain: "example.test",
            path: "/admin"
        )
        let domainMismatchCookie: HTTPCookie = try self.makeCookie(
            name: "other",
            value: "skip",
            domain: "other.test",
            path: "/"
        )

        store.save(
            SourceCredential(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://example.test")),
                cookies: [matchingCookie, pathMismatchCookie, domainMismatchCookie]
            )
        )

        let cookieHeader: String? = store.cookieHeader(
            for: SourceRequestContext(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://example.test")),
                purpose: .image
            ),
            url: try #require(URL(string: "https://example.test/reader/1.jpg"))
        )

        #expect(cookieHeader == "session=abc")
    }

    @Test func doesNotReturnCredentialForMismatchedSourceOrBaseURL() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        store.save(
            SourceCredential(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://example.test")),
                cookies: [
                    try self.makeCookie(
                        name: "session",
                        value: "abc",
                        domain: "example.test",
                        path: "/"
                    )
                ]
            )
        )

        let sourceMismatchCookie: String? = store.cookieHeader(
            for: SourceRequestContext(
                sourceID: "other",
                baseURL: try #require(URL(string: "https://example.test")),
                purpose: .detail
            ),
            url: try #require(URL(string: "https://example.test/detail"))
        )
        let baseURLMismatchCookie: String? = store.cookieHeader(
            for: SourceRequestContext(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://other.test")),
                purpose: .detail
            ),
            url: try #require(URL(string: "https://other.test/detail"))
        )

        #expect(sourceMismatchCookie == nil)
        #expect(baseURLMismatchCookie == nil)
    }

    @Test func expiredCredentialDoesNotReturnHeadersCookiesOrTokens() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let context: SourceRequestContext = SourceRequestContext(
            sourceID: "example",
            baseURL: try #require(URL(string: "https://example.test")),
            purpose: .list
        )
        store.save(
            SourceCredential(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://example.test")),
                cookies: [
                    try self.makeCookie(
                        name: "session",
                        value: "abc",
                        domain: "example.test",
                        path: "/"
                    )
                ],
                headers: ["Authorization": "Bearer secret"],
                accessToken: "secret",
                localStorage: ["token": "secret"],
                expiresAt: Date(timeIntervalSinceNow: -60)
            )
        )

        #expect(
            store.cookieHeader(
                for: context,
                url: try #require(URL(string: "https://example.test/list"))
            ) == nil
        )
        #expect(
            store.headerOverrides(
                for: context,
                url: try #require(URL(string: "https://example.test/list"))
            ).isEmpty
        )
        #expect(store.token(for: "example", key: "accessToken") == nil)
        #expect(store.storageValue(for: "example", storage: .localStorage, key: "token") == nil)
    }

    @Test func headerOverridesExcludeCookieHeader() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let context: SourceRequestContext = SourceRequestContext(
            sourceID: "example",
            baseURL: try #require(URL(string: "https://example.test")),
            purpose: .rss
        )
        store.save(
            SourceCredential(
                sourceID: "example",
                baseURL: try #require(URL(string: "https://example.test")),
                headers: [
                    "Authorization": "Bearer secret",
                    "Cookie": "session=secret"
                ]
            )
        )

        let headers: [String: String] = store.headerOverrides(
            for: context,
            url: try #require(URL(string: "https://example.test/feed.xml"))
        )

        #expect(headers == ["Authorization": "Bearer secret"])
    }

    private func makeCookie(
        name: String,
        value: String,
        domain: String,
        path: String
    ) throws -> HTTPCookie {
        return try #require(
            HTTPCookie(
                properties: [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: path,
                    .expires: Date(timeIntervalSinceNow: 3_600)
                ]
            )
        )
    }
}
