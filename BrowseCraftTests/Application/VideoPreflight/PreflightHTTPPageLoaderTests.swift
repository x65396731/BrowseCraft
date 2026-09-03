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
