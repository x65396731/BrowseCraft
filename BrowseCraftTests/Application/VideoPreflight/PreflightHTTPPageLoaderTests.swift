import Foundation
import XCTest
@testable import BrowseCraft
import BrowseCraftDomain

final class PreflightHTTPPageLoaderTests: XCTestCase {
    func testBodyBufferRejectsDeclaredAndStreamedResponsesAboveLimit() throws {
        XCTAssertThrowsError(
            try PreflightResponseBodyBuffer(
                maximumResponseBytes: 4,
                expectedContentLength: 5
            )
        ) { error in
            XCTAssertEqual(error as? PreflightPageAcquisitionError, .responseTooLarge)
        }

        var buffer: PreflightResponseBodyBuffer = try PreflightResponseBodyBuffer(
            maximumResponseBytes: 4,
            expectedContentLength: -1
        )
        try [UInt8](repeating: 1, count: 4).forEach { byte in
            try buffer.append(byte)
        }
        XCTAssertEqual(buffer.data.count, 4)
        XCTAssertThrowsError(try buffer.append(1)) { error in
            XCTAssertEqual(error as? PreflightPageAcquisitionError, .responseTooLarge)
        }
    }

    /// `BC-ACQ-060`：预检取页的执行面必须等于引擎采集入口页的执行面。
    ///
    /// 中文注释：预检在规则存在之前取页，没有 `sharedRequest` 可遵循；此前它不声明 UA、
    /// 走 URLSession 默认的 CFNetwork UA，于是与引擎去的不是同一页（快看：引擎被 302 到
    /// `m.` 子站、站内出边 1，预检留在 `www`、出边 99）。取值必须来自运行时同一个提供者。
    ///
    /// 这是**弱装置**：它只证明 loader 会向注入的提供者要头，挡得住「接线被整段拆掉」，
    /// 挡不住「拿到头之后没塞进请求」。引擎侧第十二闸门从本仓源码核对取值本身。
    func testPreflightAsksTheRuntimeHeaderProviderForItsHeaders() async throws {
        let recorder = HeaderProviderRecorder()
        let url: URL = try XCTUnwrap(URL(string: "https://example.invalid/list"))
        let loader = PreflightHTTPPageLoader(
            publicURLPolicy: AllowAllPublicURLPolicy(),
            browserRequestHeaderProvider: recorder
        )
        _ = try? await loader.acquire(
            PreflightPageRequest(url: url, timeoutSeconds: 1)
        )
        let requested: [URL] = await recorder.requestedURLs
        XCTAssertEqual(requested, [url])
    }

    /// 默认提供者就是运行时那一个——三端同源的落点在这里。
    func testDefaultHeaderProviderIsTheRuntimeOne() throws {
        let runtime = ChromeRequestHeaderProvider()
        let headers: [String: String] = runtime.defaultHeaders(
            for: try XCTUnwrap(URL(string: "https://example.com/")),
            referer: nil,
            includeOrigin: false
        )
        XCTAssertEqual(headers["User-Agent"], runtime.userAgent)
        XCTAssertFalse(runtime.userAgent.contains("iPhone"), "运行时默认头不是移动 UA")
    }

    func testUnsafeRedirectIsCancelledBeforeURLSessionFollowsIt() throws {
        let sourceURL: URL = try XCTUnwrap(URL(string: "https://example.com/list"))
        let privateTargetURL: URL = try XCTUnwrap(URL(string: "http://127.0.0.1/admin"))
        let policy: RedirectTestPublicURLPolicy = RedirectTestPublicURLPolicy(
            rejectedHost: "127.0.0.1"
        )
        let delegate: PreflightURLSessionDelegate = PreflightURLSessionDelegate(
            publicURLPolicy: policy
        )
        let session: URLSession = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let task: URLSessionDataTask = session.dataTask(with: sourceURL)
        let response: HTTPURLResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: sourceURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": privateTargetURL.absoluteString]
            )
        )
        let recorder: RedirectRequestRecorder = RedirectRequestRecorder()

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: privateTargetURL)
        ) { request in
            recorder.record(request)
        }

        XCTAssertNil(recorder.request)
        XCTAssertTrue(delegate.didRejectRedirect)
        XCTAssertTrue(delegate.redirectChain.isEmpty)
    }

    func testSafeRedirectIsRecordedAndAllowed() throws {
        let sourceURL: URL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let targetURL: URL = try XCTUnwrap(URL(string: "https://example.com/list"))
        let delegate: PreflightURLSessionDelegate = PreflightURLSessionDelegate(
            publicURLPolicy: RedirectTestPublicURLPolicy(rejectedHost: nil)
        )
        let session: URLSession = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let task: URLSessionDataTask = session.dataTask(with: sourceURL)
        let response: HTTPURLResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: sourceURL,
                statusCode: 301,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": targetURL.absoluteString]
            )
        )
        let recorder: RedirectRequestRecorder = RedirectRequestRecorder()

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: targetURL)
        ) { request in
            recorder.record(request)
        }

        XCTAssertEqual(recorder.request?.url, targetURL)
        XCTAssertFalse(delegate.didRejectRedirect)
        XCTAssertEqual(delegate.redirectChain.count, 1)
        XCTAssertEqual(delegate.redirectChain.first?.sourceURL, sourceURL)
        XCTAssertEqual(delegate.redirectChain.first?.targetURL, targetURL)
    }

    /// `BC-PREFLIGHT-065`：跳转目标是 http 时升成 https 再跟随（Movieffm `mvffm.net` → `http://www.` 形状）。
    func testHTTPRedirectTargetIsUpgradedToHTTPSBeforeFollowing() throws {
        let sourceURL: URL = try XCTUnwrap(URL(string: "https://example.com/drama/"))
        let httpTargetURL: URL = try XCTUnwrap(URL(string: "http://www.example.com:80/drama/"))
        let upgradedURL: URL = try XCTUnwrap(URL(string: "https://www.example.com/drama/"))
        let delegate: PreflightURLSessionDelegate = PreflightURLSessionDelegate(
            publicURLPolicy: RedirectTestPublicURLPolicy(rejectedHost: nil)
        )
        let session: URLSession = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let task: URLSessionDataTask = session.dataTask(with: sourceURL)
        let response: HTTPURLResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: sourceURL,
                statusCode: 301,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": httpTargetURL.absoluteString]
            )
        )
        let recorder: RedirectRequestRecorder = RedirectRequestRecorder()

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: httpTargetURL)
        ) { request in
            recorder.record(request)
        }

        XCTAssertEqual(recorder.request?.url, upgradedURL)
        XCTAssertFalse(delegate.didRejectRedirect)
        XCTAssertEqual(delegate.redirectChain.first?.targetURL, upgradedURL)
    }
}

private final class RedirectRequestRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var recordedRequest: URLRequest?

    var request: URLRequest? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedRequest
    }

    func record(_ request: URLRequest?) {
        self.lock.lock()
        self.recordedRequest = request
        self.lock.unlock()
    }
}

private struct RedirectTestPublicURLPolicy: PublicURLChecking {
    let rejectedHost: String?

    func validate(_ url: URL) throws {
        if url.host == self.rejectedHost {
            throw PublicURLCheckError.nonPublicAddress
        }
    }

    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
        return candidate.host == inputURL.host
    }
}

/// 记录被问过哪些 URL 的请求头提供者替身。
private actor HeaderProviderRecorder: BrowserRequestHeaderProviding {
    private(set) var requestedURLs: [URL] = []

    nonisolated var userAgent: String { "recorder" }

    nonisolated func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String] {
        Task { await self.record(url) }
        return ["User-Agent": "recorder"]
    }

    private func record(_ url: URL) {
        self.requestedURLs.append(url)
    }
}

private struct AllowAllPublicURLPolicy: PublicURLChecking {
    func validate(_ url: URL) throws {}

    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
        return candidate.host == inputURL.host
    }
}
