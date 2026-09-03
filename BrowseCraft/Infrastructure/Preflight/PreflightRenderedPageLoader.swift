import BrowseCraftDomain
import Foundation
import WebKit

/// Stateless Sendable adapter. Every acquisition receives its own MainActor
/// operation and non-persistent WKWebView, so concurrent preflight samples do
/// not share cookies, credentials, navigation state, or continuations.
struct PreflightRenderedPageLoader: PreflightRenderedPageAcquiring, Sendable {
    private let publicURLPolicy: any PublicURLChecking
    private let maximumResponseBytes: Int

    init(
        publicURLPolicy: any PublicURLChecking,
        maximumResponseBytes: Int = 5_000_000
    ) {
        self.publicURLPolicy = publicURLPolicy
        self.maximumResponseBytes = maximumResponseBytes
    }

    @MainActor
    func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        let operation: PreflightRenderedPageOperation = PreflightRenderedPageOperation(
            publicURLPolicy: self.publicURLPolicy,
            maximumResponseBytes: self.maximumResponseBytes
        )
        return try await operation.acquire(request)
    }
}

/// Isolation is limited to a non-persistent WebKit data store plus validation of
/// every main-frame navigation. WebKit subresource access is not claimed to be
/// blocked by this loader; the result records that narrower isolation scope.
@MainActor
private final class PreflightRenderedPageOperation: NSObject, WKNavigationDelegate {
    private let publicURLPolicy: any PublicURLChecking
    private let maximumResponseBytes: Int
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<PreflightAcquiredPage, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var activeRequest: PreflightPageRequest?
    private var redirectChain: [PreflightRedirectRecord] = []
    private var lastMainFrameURL: URL?
    private var hasCompleted: Bool = false

    init(
        publicURLPolicy: any PublicURLChecking,
        maximumResponseBytes: Int
    ) {
        self.publicURLPolicy = publicURLPolicy
        self.maximumResponseBytes = maximumResponseBytes
    }

    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        try self.publicURLPolicy.validate(request.url)

        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.processPool = WKProcessPool()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView: WKWebView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        self.activeRequest = request
        self.lastMainFrameURL = request.url

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard Task.isCancelled == false else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                var urlRequest: URLRequest = URLRequest(
                    url: request.url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: request.timeoutSeconds
                )
                urlRequest.httpMethod = "GET"
                urlRequest.setValue(
                    "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
                    forHTTPHeaderField: "Accept"
                )
                webView.load(urlRequest)
                self.startTimeout(seconds: request.timeoutSeconds)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        Task { @MainActor [weak self, weak webView] in
            guard let self: PreflightRenderedPageOperation = self,
                  let webView: WKWebView = webView else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                try Task.checkCancellation()
                guard self.hasCompleted == false else {
                    return
                }
                let result: Any? = try await webView.evaluateJavaScript(
                    "document.documentElement ? document.documentElement.outerHTML : ''"
                )
                guard let html: String = result as? String, html.isEmpty == false else {
                    throw PreflightPageAcquisitionError.emptyContent
                }
                let data: Data = Data(html.utf8)
                guard data.count <= self.maximumResponseBytes else {
                    throw PreflightPageAcquisitionError.responseTooLarge
                }
                guard let request: PreflightPageRequest = self.activeRequest,
                      let finalURL: URL = webView.url ?? self.lastMainFrameURL else {
                    throw PreflightPageAcquisitionError.invalidResponse
                }
                try self.publicURLPolicy.validate(finalURL)
                self.finish(
                    .success(
                        PreflightAcquiredPage(
                            requestedURL: request.url,
                            data: data,
                            finalURL: finalURL,
                            redirectChain: self.redirectChain,
                            statusCode: nil,
                            mediaType: "text/html",
                            textEncodingName: "utf-8",
                            acquisitionIdentity: UUID().uuidString,
                            source: .rendered,
                            isolationScope: .mainFrameWebView
                        )
                    )
                )
            } catch is CancellationError {
                self.finish(.failure(CancellationError()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let targetURL: URL = navigationAction.request.url else {
            return .allow
        }
        do {
            try self.publicURLPolicy.validate(targetURL)
            if let previousURL: URL = self.lastMainFrameURL,
               previousURL != targetURL {
                self.redirectChain.append(
                    PreflightRedirectRecord(
                        statusCode: nil,
                        sourceURL: previousURL,
                        targetURL: targetURL
                    )
                )
            }
            self.lastMainFrameURL = targetURL
            return .allow
        } catch {
            self.finish(.failure(PreflightPageAcquisitionError.unsafeRedirect))
            return .cancel
        }
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            self.finish(.failure(PreflightPageAcquisitionError.authenticationRequired))
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        self.finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        self.finish(.failure(error))
    }

    private func startTimeout(seconds: TimeInterval) {
        self.timeoutTask?.cancel()
        self.timeoutTask = Task { @MainActor [weak self] in
            let nanoseconds: UInt64 = UInt64(max(seconds, 1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard Task.isCancelled == false else {
                return
            }
            self?.finish(.failure(PreflightPageAcquisitionError.timedOut))
        }
    }

    private func finish(_ result: Result<PreflightAcquiredPage, Error>) {
        guard self.hasCompleted == false else {
            return
        }
        self.hasCompleted = true
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.webView?.stopLoading()
        self.webView?.navigationDelegate = nil
        self.webView = nil
        self.activeRequest = nil
        let continuation: CheckedContinuation<PreflightAcquiredPage, Error>? = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
