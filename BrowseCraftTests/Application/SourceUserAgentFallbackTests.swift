import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：`BCA-RUNTIME-010`——规则匹配不到内容时换手机 Safari UA 重做一次，成功按来源记住；其它错误不触发。
struct SourceUserAgentFallbackTests {
    @Test func selectorEmptyRetriesOnceWithMobileUserAgentAndRemembersIt() async throws {
        let fallback: SourceUserAgentFallback = Self.makeFallback()
        let source: Source = Self.makeSource()
        let attempts: AttemptRecorder = AttemptRecorder()

        let output: String = try await fallback.perform(source: source) {
            let userAgent: String? = fallback.overridingUserAgent(forSourceID: source.id)
            attempts.record(userAgent)
            if userAgent == nil {
                throw Self.selectorEmpty(source: source)
            }
            return "mobile-template"
        }

        #expect(output == "mobile-template")
        #expect(attempts.values == [nil, ClientUserAgent.mobileSafari])
        #expect(fallback.overridingUserAgent(forSourceID: source.id) == ClientUserAgent.mobileSafari)

        // 中文注释：记住之后直接带手机 UA，不再多取一遍。
        let second: AttemptRecorder = AttemptRecorder()
        _ = try await fallback.perform(source: source) {
            second.record(fallback.overridingUserAgent(forSourceID: source.id))
            return "again"
        }
        #expect(second.values == [ClientUserAgent.mobileSafari])
    }

    @Test func otherErrorsDoNotTriggerTheRetry() async throws {
        let fallback: SourceUserAgentFallback = Self.makeFallback()
        let source: Source = Self.makeSource()
        let attempts: AttemptRecorder = AttemptRecorder()

        await #expect(throws: RuleExecutionError.self) {
            try await fallback.perform(source: source) { () async throws -> String in
                attempts.record(fallback.overridingUserAgent(forSourceID: source.id))
                throw RuleExecutionError.httpStatus(url: "https://example.test/list", statusCode: 403)
            }
        }
        #expect(attempts.values == [nil])
        #expect(fallback.overridingUserAgent(forSourceID: source.id) == nil)
    }

    @Test func mobileAlsoEmptyRethrowsTheOriginalErrorAndStopsRetrying() async throws {
        let fallback: SourceUserAgentFallback = Self.makeFallback()
        let source: Source = Self.makeSource()
        let attempts: AttemptRecorder = AttemptRecorder()

        do {
            _ = try await fallback.perform(source: source) { () async throws -> String in
                attempts.record(fallback.overridingUserAgent(forSourceID: source.id))
                throw Self.selectorEmpty(source: source)
            }
            Issue.record("expected selectorEmpty")
        } catch let error as RuleExecutionError {
            guard case .selectorEmpty = error else {
                Issue.record("expected selectorEmpty, got \(error)")
                return
            }
        }
        #expect(attempts.values == [nil, ClientUserAgent.mobileSafari])
        #expect(fallback.overridingUserAgent(forSourceID: source.id) == nil)

        let again: AttemptRecorder = AttemptRecorder()
        _ = try? await fallback.perform(source: source) { () async throws -> String in
            again.record(fallback.overridingUserAgent(forSourceID: source.id))
            throw Self.selectorEmpty(source: source)
        }
        #expect(again.values == [nil])
    }

    @Test func emptyOutputTriggersTheRetryWhenTheCallerSaysSo() async throws {
        let fallback: SourceUserAgentFallback = Self.makeFallback()
        let source: Source = Self.makeSource()

        let items: [String] = try await fallback.perform(source: source, isEmpty: { $0.isEmpty }) {
            fallback.overridingUserAgent(forSourceID: source.id) == nil ? [] : ["book"]
        }

        #expect(items == ["book"])
    }

    @Test func ruleUpdateResetsTheDecision() async throws {
        let fallback: SourceUserAgentFallback = Self.makeFallback()
        let source: Source = Self.makeSource()
        _ = try await fallback.perform(source: source) {
            if fallback.overridingUserAgent(forSourceID: source.id) == nil {
                throw Self.selectorEmpty(source: source)
            }
            return "mobile"
        }
        #expect(fallback.overridingUserAgent(forSourceID: source.id) == ClientUserAgent.mobileSafari)

        var updated: Source = source
        updated.updatedAt = Date(timeIntervalSince1970: 200)
        let attempts: AttemptRecorder = AttemptRecorder()
        _ = try await fallback.perform(source: updated) {
            attempts.record(fallback.overridingUserAgent(forSourceID: source.id))
            return "desktop-template-now-works"
        }
        #expect(attempts.values == [nil])
    }

    @Test func headersSwapOnlyTheUserAgent() async throws {
        let fallback: SourceUserAgentFallback = Self.makeFallback()
        let source: Source = Self.makeSource()
        _ = try await fallback.perform(source: source) {
            if fallback.overridingUserAgent(forSourceID: source.id) == nil {
                throw Self.selectorEmpty(source: source)
            }
            return "mobile"
        }

        let headers: [String: String] = fallback.applying(
            to: ["user-agent": ClientUserAgent.desktopSafari, "Accept-Language": "zh-Hant-TW"],
            sourceID: source.id
        )
        #expect(headers == ["User-Agent": ClientUserAgent.mobileSafari, "Accept-Language": "zh-Hant-TW"])
        #expect(fallback.applying(to: ["User-Agent": "x"], sourceID: "other") == ["User-Agent": "x"])
    }

    @Test func coverRequestsFollowTheSourceUserAgent() async throws {
        // 中文注释：封面走共享实例（`imageRequestConfig` 的出口）；来源 id 每次唯一，不串到别的用例。
        var source: Source = Self.makeSource()
        source.id = "source-ua-cover-\(UUID().uuidString)"
        let presentation: ResolveLibrarySourcePresentationUseCase = ResolveLibrarySourcePresentationUseCase()
        let before: RequestConfig? = presentation.imageRequestConfig(for: source, listTab: nil)
        #expect(before?.imageHeaders?["User-Agent"] == nil)

        _ = try await SourceUserAgentFallback.shared.perform(source: source) {
            if SourceUserAgentFallback.shared.overridingUserAgent(forSourceID: source.id) == nil {
                throw Self.selectorEmpty(source: source)
            }
            return "mobile"
        }
        let after: RequestConfig? = presentation.imageRequestConfig(for: source, listTab: nil)
        #expect(after?.imageHeaders?["User-Agent"] == ClientUserAgent.mobileSafari)
    }

    private static func makeFallback() -> SourceUserAgentFallback {
        let suite: String = "SourceUserAgentFallbackTests.\(UUID().uuidString)"
        return SourceUserAgentFallback(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private static func makeSource() -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: "source-ua",
            name: "Source",
            baseURL: "https://example.test",
            type: .html,
            configuration: TestSourceFixtures.pluginConfiguration(),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func selectorEmpty(source: Source) -> RuleExecutionError {
        return .selectorEmpty(stage: .list, sourceID: source.id, url: "https://example.test/list", ruleID: nil)
    }
}

private final class AttemptRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var recorded: [String?] = []

    var values: [String?] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recorded
    }

    func record(_ value: String?) {
        self.lock.lock()
        self.recorded.append(value)
        self.lock.unlock()
    }
}
