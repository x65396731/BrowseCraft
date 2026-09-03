import BrowseCraftCore
import Foundation
import XCTest
@testable import BrowseCraft

/// v3 用例：只采集输入页；三态由 Core 入口页归约决定。
final class AssessVideoGenerationInputUseCaseTests: XCTestCase {
    private actor RecordingLoader: PreflightPageAcquiring {
        private(set) var requests: [PreflightPageRequest] = []
        private let handler: @Sendable (PreflightPageRequest) async throws -> PreflightAcquiredPage

        init(handler: @escaping @Sendable (PreflightPageRequest) async throws -> PreflightAcquiredPage) {
            self.handler = handler
        }

        func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
            self.requests.append(request)
            return try await self.handler(request)
        }

        func requestCount() -> Int { return self.requests.count }
    }

    private struct RenderedUnavailable: PreflightRenderedPageAcquiring {
        @MainActor
        func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
            throw PreflightPageAcquisitionError.isolationUnavailable
        }
    }

    private struct AllowingPolicy: PublicURLChecking {
        func validate(_ url: URL) throws {}
        func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool { return candidate.host == inputURL.host }
    }

    private struct RejectingPolicy: PublicURLChecking {
        func validate(_ url: URL) throws { throw PublicURLCheckError.nonPublicAddress }
        func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool { return false }
    }

    private static func page(_ url: URL, html: String) -> PreflightAcquiredPage {
        return PreflightAcquiredPage(
            requestedURL: url, data: Data(html.utf8), finalURL: url, statusCode: 200,
            mediaType: "text/html", textEncodingName: "utf-8", acquisitionIdentity: url.absoluteString,
            source: .http, isolationScope: .fullHTTP
        )
    }

    private static func cards(_ prefix: String, _ range: ClosedRange<Int>) -> String {
        return range.map { "<article><a href=\"\(prefix)\($0)-t.html\"><img src=\"\($0).jpg\">Title \($0)</a></article>" }.joined()
    }

    private func makeUseCase(
        policy: any PublicURLChecking = AllowingPolicy(),
        loader: RecordingLoader,
        samplingPolicy: VideoGenerationInputSamplingPolicy = VideoGenerationInputSamplingPolicy()
    ) -> AssessVideoGenerationInputUseCase {
        return AssessVideoGenerationInputUseCase(
            publicURLPolicy: policy,
            httpLoader: loader,
            renderedLoader: RenderedUnavailable(),
            structureObserver: DefaultSourceListStructureObserver(),
            entryFamilyAssessor: DefaultSourceListEntryFamilyAssessor(),
            samplingPolicy: samplingPolicy
        )
    }

    func testUnsafeInputStopsBeforeAnyAcquisition() async {
        let loader = RecordingLoader { request in Self.page(request.url, html: "<html></html>") }
        do {
            _ = try await self.makeUseCase(policy: RejectingPolicy(), loader: loader).execute(siteURLString: "https://10.0.0.1/list")
            XCTFail("expected unsafeURL")
        } catch let issue as VideoGenerationInputPreflightExecutionIssue {
            XCTAssertEqual(issue, .unsafeURL)
        } catch {
            XCTFail("unexpected \(error)")
        }
        let count = await loader.requestCount()
        XCTAssertEqual(count, 0)
    }

    func testSingleFamilyPageIsAcceptedAndOnlyInputIsFetched() async throws {
        let loader = RecordingLoader { request in
            Self.page(request.url, html: "<html><body><main>\(Self.cards("/films/", 1...12))</main></body></html>")
        }
        let result = try await self.makeUseCase(loader: loader).execute(siteURLString: "https://example.com/films/?sort=new&page=2")
        XCTAssertEqual(result.status, .accepted)
        XCTAssertEqual(result.entryShape, .directListOwner)
        XCTAssertEqual(result.submissionString, "https://example.com/films/?sort=new&page=2")
        XCTAssertEqual(result.audit.familyCount, 1)
        let count = await loader.requestCount()
        XCTAssertEqual(count, 1, "v3 只采集输入页")
    }

    func testMultipleFamiliesAreRejected() async throws {
        let loader = RecordingLoader { request in
            Self.page(request.url, html: "<html><body><main>\(Self.cards("/videos/", 1...12))</main><section>\(Self.cards("/categories/", 1...8))</section></body></html>")
        }
        let result = try await self.makeUseCase(loader: loader).execute(siteURLString: "https://example.com/")
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .multipleIndependentListFamilies)
        XCTAssertEqual(result.entryShape, .multipleListFamilies)
        XCTAssertFalse(result.canSubmit)
    }

    func testPageWithoutListIsRejected() async throws {
        let loader = RecordingLoader { request in
            Self.page(request.url, html: "<html><body><main><h1>About</h1><p>Some text</p><a href=\"/x\">x</a></main></body></html>")
        }
        let result = try await self.makeUseCase(loader: loader).execute(siteURLString: "https://example.com/about")
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .noExecutableListFamily)
    }

    func testGlobalDeadlineReturnsInconclusive() async throws {
        let loader = RecordingLoader { request in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return Self.page(request.url, html: "<html></html>")
        }
        let useCase = self.makeUseCase(loader: loader, samplingPolicy: VideoGenerationInputSamplingPolicy(globalDeadlineSeconds: 0.2))
        let result = try await useCase.execute(siteURLString: "https://example.com/list")
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.reason, .budgetExhausted)
    }

    func testAuthenticationRequiredBecomesRequiresUserSession() async throws {
        let loader = RecordingLoader { _ in throw PreflightPageAcquisitionError.authenticationRequired }
        let result = try await self.makeUseCase(loader: loader).execute(siteURLString: "https://example.com/list")
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.reason, .requiresUserSession)
    }
}
