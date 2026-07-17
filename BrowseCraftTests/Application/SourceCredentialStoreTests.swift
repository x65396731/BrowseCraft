import Foundation
import Testing
import WebKit
@testable import BrowseCraft

// 中文注释：SourceCredentialStore 测试，锁定登录态基础抽象的命中、过滤和过期行为。
struct SourceCredentialStoreTests {
    @MainActor
    @Test func sourceLoginWebUIUsesPersistentWebsiteDataStore() {
        let coordinator: SourceLoginWebCoordinator = SourceLoginWebCoordinator()

        #expect(coordinator.configuration.websiteDataStore === WKWebsiteDataStore.default())
        #expect(coordinator.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(coordinator.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
    }

    @Test func libraryLoginStateUsesComicRuleLoginURLAndDefaultsToGuest() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let source: Source = try self.makeComicSource(
            loginURL: "https://example.test/login",
            credentialKeys: ["accessToken", "refreshToken"]
        )

        let state: LibrarySourceLoginState? = LibrarySourceLoginStateResolver(
            credentialStore: store
        ).resolve(source: source)

        #expect(state?.sourceID == source.id)
        #expect(state?.sourceName == source.name)
        #expect(state?.baseURL.absoluteString == "https://example.test")
        #expect(state?.loginURL.absoluteString == "https://example.test/login")
        #expect(state?.credentialKeys == ["accessToken", "refreshToken"])
        #expect(state?.status == .guest)
    }

    @Test func capturedLoginSessionBuildsSourceScopedCredential() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let source: Source = try self.makeComicSource(
            loginURL: "https://example.test/login",
            credentialKeys: ["accessToken", "refreshToken"]
        )
        let state: LibrarySourceLoginState = try #require(
            LibrarySourceLoginStateResolver(credentialStore: store).resolve(source: source)
        )
        let cookie: HTTPCookie = try self.makeCookie(
            name: "session",
            value: "member",
            domain: ".example.test",
            path: "/"
        )

        let credential: SourceCredential = try SourceLoginCredentialBuilder().build(
            state: state,
            cookies: [cookie],
            storage: SourceLoginStorageSnapshot(
                localStorage: ["accessToken": "access"],
                sessionStorage: ["refreshToken": "refresh"]
            )
        )

        #expect(credential.sourceID == source.id)
        #expect(credential.baseURL == state.baseURL)
        #expect(credential.cookies.map(\.name) == ["session"])
        #expect(credential.accessToken == "access")
        #expect(credential.refreshToken == "refresh")
        #expect(credential.origin == .webView)
        #expect(SourceLoginSessionDomainMatcher.matches(cookie: cookie, state: state))
        #expect(
            SourceLoginSessionDomainMatcher.matches(
                cookie: try self.makeCookie(
                    name: "other",
                    value: "skip",
                    domain: "other.test",
                    path: "/"
                ),
                state: state
            ) == false
        )
    }

    @Test func capturedLoginSessionRejectsEmptyCredentialMaterial() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let source: Source = try self.makeComicSource(loginURL: "https://example.test/login")
        let state: LibrarySourceLoginState = try #require(
            LibrarySourceLoginStateResolver(credentialStore: store).resolve(source: source)
        )

        #expect(throws: SourceLoginSessionError.self) {
            try SourceLoginCredentialBuilder().build(
                state: state,
                cookies: [],
                storage: SourceLoginStorageSnapshot(localStorage: [:], sessionStorage: [:])
            )
        }
    }

    @Test func libraryLoginStateIsAuthenticatedOnlyForActiveCredentialMaterial() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let source: Source = try self.makeComicSource(loginURL: "https://example.test/login")
        store.save(
            SourceCredential(
                sourceID: source.id,
                baseURL: URL(string: source.baseURL),
                accessToken: "member-token",
                expiresAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        let state: LibrarySourceLoginState? = LibrarySourceLoginStateResolver(
            credentialStore: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        ).resolve(source: source)

        #expect(state?.status == .authenticated)
    }

    @Test func libraryLoginStateRejectsMissingInvalidAndExpiredLoginData() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let missingLoginSource: Source = try self.makeComicSource(loginURL: nil)
        let invalidLoginSource: Source = try self.makeComicSource(loginURL: "javascript:login()")
        let expiredSource: Source = try self.makeComicSource(
            id: "expired.example",
            loginURL: "https://example.test/login"
        )
        store.save(
            SourceCredential(
                sourceID: expiredSource.id,
                accessToken: "expired-token",
                expiresAt: Date(timeIntervalSince1970: 500)
            )
        )
        let resolver: LibrarySourceLoginStateResolver = LibrarySourceLoginStateResolver(
            credentialStore: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        #expect(resolver.resolve(source: missingLoginSource) == nil)
        #expect(resolver.resolve(source: invalidLoginSource) == nil)
        #expect(resolver.resolve(source: expiredSource)?.status == .guest)
    }

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

    @Test func ruleContextUsesSourceScopedUserTokenAndFallsBackToAnonymousValue() throws {
        let store: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        var source: Source = try self.makeComicSource(
            id: "comic.member",
            loginURL: "https://example.test/login"
        )
        var ruleContext: [String: SiteRuleContextValue] = source.rule.context ?? [:]
        ruleContext["readerAccessToken"] = SiteRuleContextValue(
            anonymousValue: "guest-token",
            userValue: "{credentialStore.accessToken}"
        )
        source.rule.context = ruleContext
        store.save(
            SourceCredential(
                sourceID: source.id,
                baseURL: URL(string: source.baseURL),
                accessToken: "member-token"
            )
        )
        store.save(
            SourceCredential(
                sourceID: "comic.other",
                accessToken: "other-token"
            )
        )

        let authenticatedValues: [String: String] = ComicRuleAPIResolver.ruleContextValues(
            source: source,
            credentialProvider: store
        )
        let anonymousValues: [String: String] = ComicRuleAPIResolver.ruleContextValues(source: source)

        #expect(authenticatedValues["readerAccessToken"] == "member-token")
        #expect(anonymousValues["readerAccessToken"] == "guest-token")
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

    private func makeComicSource(
        id: String = "comic.example",
        loginURL: String?,
        credentialKeys: [String] = []
    ) throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        rule.site?.loginURL = loginURL
        if credentialKeys.isEmpty == false {
            var context: [String: SiteRuleContextValue] = rule.context ?? [:]
            credentialKeys.forEach { key in
                context["test\(key)"] = SiteRuleContextValue(
                    userValue: "{credentialStore.\(key)}"
                )
            }
            rule.context = context
        }
        let now: Date = Date(timeIntervalSince1970: 1_000)
        return Source(
            id: id,
            name: rule.name,
            baseURL: rule.baseUrl,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}
