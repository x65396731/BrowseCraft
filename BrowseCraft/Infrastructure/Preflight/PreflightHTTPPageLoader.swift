import BrowseCraftDomain
import Foundation

struct PreflightHTTPPageLoader: PreflightPageAcquiring {
    private let publicURLPolicy: any PublicURLChecking
    private let maximumResponseBytes: Int
    /// `BC-ACQ-060`：预检取页的执行面必须等于引擎采集入口页的执行面。
    ///
    /// 中文注释：预检在**规则还不存在**的时候取页面，因此没有 `sharedRequest` 可以遵循。
    /// 此前它既不声明 UA、又自带一套窄 `Accept`，于是走 URLSession 默认的 CFNetwork UA——
    /// 三端里唯一的异类。快看漫画即此例：引擎（项目 UA）被站点 302 到 `m.` 子站、
    /// 站内出边 1，预检（CFNetwork UA）留在 `www`、站内出边 99，两侧判的不是同一页。
    /// 取值因此来自与运行时同一个提供者，引擎侧的常量由第十二闸门从本文件的源码核对。
    private let browserRequestHeaderProvider: any BrowserRequestHeaderProviding

    init(
        publicURLPolicy: any PublicURLChecking,
        maximumResponseBytes: Int = 5_000_000,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding =
            ChromeRequestHeaderProvider()
    ) {
        self.publicURLPolicy = publicURLPolicy
        self.maximumResponseBytes = maximumResponseBytes
        self.browserRequestHeaderProvider = browserRequestHeaderProvider
    }

    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        // 中文注释：`BC-PREFLIGHT-065`——与运行时同一 https 升级（`BC-ACQ-065`）；`requestedURL` 仍是输入原样。
        let fetchURL: URL = HTTPSUpgrade.upgraded(request.url) ?? request.url
        try self.publicURLPolicy.validate(fetchURL)

        let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = request.timeoutSeconds
        configuration.timeoutIntervalForResource = request.timeoutSeconds
        configuration.waitsForConnectivity = false

        let delegate: PreflightURLSessionDelegate = PreflightURLSessionDelegate(
            publicURLPolicy: self.publicURLPolicy
        )
        let session: URLSession = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer {
            session.finishTasksAndInvalidate()
        }

        var urlRequest: URLRequest = URLRequest(
            url: fetchURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: request.timeoutSeconds
        )
        urlRequest.httpMethod = "GET"
        // `BC-ACQ-060`：整套头取自运行时同一个提供者，不在这里另写一份。
        for (field, value): (String, String) in self.browserRequestHeaderProvider.defaultHeaders(
            for: fetchURL,
            referer: nil,
            includeOrigin: false
        ) {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (bytes, response): (URLSession.AsyncBytes, URLResponse) =
                try await session.bytes(for: urlRequest)
            if delegate.didRejectRedirect {
                throw PreflightPageAcquisitionError.unsafeRedirect
            }
            guard let httpResponse: HTTPURLResponse = response as? HTTPURLResponse else {
                throw PreflightPageAcquisitionError.invalidResponse
            }
            let statusAccepted: Bool = (200..<400).contains(httpResponse.statusCode)
            var bodyBuffer: PreflightResponseBodyBuffer = try PreflightResponseBodyBuffer(
                maximumResponseBytes: self.maximumResponseBytes,
                expectedContentLength: httpResponse.expectedContentLength
            )
            for try await byte: UInt8 in bytes {
                try bodyBuffer.append(byte)
            }
            let data: Data = bodyBuffer.data
            // 中文注释：`BC-PREFLIGHT-063`——403/503 带挑战页正文时交给分类器判 `antiBotChallenge`
            // （提示后放行提交）；其余被拒状态码仍按 `BC-PREFLIGHT-062` 抛 `rejectedStatus`。
            if statusAccepted == false {
                let html: String = String(decoding: data, as: UTF8.self)
                guard HTMLChallengeInterstitialDetector.isChallengeInterstitial(html) else {
                    throw PreflightPageAcquisitionError.rejectedStatus(httpResponse.statusCode)
                }
            }
            guard data.isEmpty == false else {
                throw PreflightPageAcquisitionError.emptyContent
            }
            let finalURL: URL = httpResponse.url ?? fetchURL
            try self.publicURLPolicy.validate(finalURL)
            return PreflightAcquiredPage(
                requestedURL: request.url,
                data: data,
                finalURL: finalURL,
                redirectChain: delegate.redirectChain,
                statusCode: httpResponse.statusCode,
                mediaType: httpResponse.mimeType,
                textEncodingName: httpResponse.textEncodingName,
                acquisitionIdentity: UUID().uuidString,
                source: .http,
                isolationScope: .fullHTTP
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PreflightPageAcquisitionError {
            throw error
        } catch is PublicURLCheckError {
            throw PreflightPageAcquisitionError.unsafeRedirect
        } catch let error as URLError where error.code == .timedOut {
            throw PreflightPageAcquisitionError.timedOut
        } catch {
            if delegate.didRejectAuthentication {
                throw PreflightPageAcquisitionError.authenticationRequired
            }
            throw error
        }
    }
}

struct PreflightResponseBodyBuffer {
    private let maximumResponseBytes: Int
    private(set) var data: Data

    init(maximumResponseBytes: Int, expectedContentLength: Int64) throws {
        self.maximumResponseBytes = max(0, maximumResponseBytes)
        if expectedContentLength > Int64(self.maximumResponseBytes) {
            throw PreflightPageAcquisitionError.responseTooLarge
        }
        self.data = Data()
        self.data.reserveCapacity(
            min(max(Int(expectedContentLength), 0), self.maximumResponseBytes)
        )
    }

    mutating func append(_ byte: UInt8) throws {
        guard self.data.count < self.maximumResponseBytes else {
            throw PreflightPageAcquisitionError.responseTooLarge
        }
        self.data.append(byte)
    }
}

/// URLSession may invoke delegate callbacks concurrently. Every mutable field is
/// protected by `lock`; the injected policy is itself Sendable and immutable.
final class PreflightURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let publicURLPolicy: any PublicURLChecking
    private let lock: NSLock = NSLock()
    private var rejectedRedirect: Bool = false
    private var rejectedAuthentication: Bool = false
    private var redirects: [PreflightRedirectRecord] = []

    init(publicURLPolicy: any PublicURLChecking) {
        self.publicURLPolicy = publicURLPolicy
    }

    var didRejectRedirect: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.rejectedRedirect
    }

    var redirectChain: [PreflightRedirectRecord] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.redirects
    }

    var didRejectAuthentication: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.rejectedAuthentication
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let targetURL: URL = request.url else {
            self.markRejectedRedirect()
            completionHandler(nil)
            return
        }
        // 中文注释：`BC-PREFLIGHT-065`——跳转目标是 http 时先升 https（运行时 `httpsUpgradingRedirector` 同一纪律），
        // 否则 ATS 在这一跳拒绝（`-1022`），预检落「暂时无法检查」而引擎与运行时都跟得过去。
        let redirectURL: URL = HTTPSUpgrade.upgraded(targetURL) ?? targetURL
        var redirected: URLRequest = request
        redirected.url = redirectURL
        do {
            try self.publicURLPolicy.validate(redirectURL)
            self.recordRedirect(
                PreflightRedirectRecord(
                    statusCode: response.statusCode,
                    sourceURL: response.url ?? task.currentRequest?.url ?? redirectURL,
                    targetURL: redirectURL
                )
            )
            completionHandler(redirected)
        } catch {
            self.markRejectedRedirect()
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            completionHandler(.performDefaultHandling, nil)
        case NSURLAuthenticationMethodClientCertificate:
            // 中文注释：`BC-PREFLIGHT-064`——TLS 客户端证书质询不是登录态（bakamh 握手里带
            // `CertificateRequest`，不带证书照样给正文）。不提供证书、继续握手，不读任何凭据。
            completionHandler(.rejectProtectionSpace, nil)
        default:
            self.markRejectedAuthentication()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func markRejectedRedirect() {
        self.lock.lock()
        self.rejectedRedirect = true
        self.lock.unlock()
    }

    private func recordRedirect(_ redirect: PreflightRedirectRecord) {
        self.lock.lock()
        self.redirects.append(redirect)
        self.lock.unlock()
    }

    private func markRejectedAuthentication() {
        self.lock.lock()
        self.rejectedAuthentication = true
        self.lock.unlock()
    }
}
