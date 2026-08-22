import Foundation

enum PreflightPageAcquisitionSource: String, Hashable, Sendable {
    case http
    case rendered
}

enum PreflightIsolationScope: String, Hashable, Sendable {
    case fullHTTP
    case mainFrameWebView
}

struct PreflightRedirectRecord: Hashable, Sendable {
    let statusCode: Int?
    let sourceURL: URL
    let targetURL: URL
}

struct PreflightPageRequest: Hashable, Sendable {
    let url: URL
    let timeoutSeconds: TimeInterval

    init(url: URL, timeoutSeconds: TimeInterval = 12) {
        self.url = url
        self.timeoutSeconds = timeoutSeconds
    }
}

struct PreflightAcquiredPage: Hashable, Sendable {
    let requestedURL: URL
    let data: Data
    let finalURL: URL
    let redirectChain: [PreflightRedirectRecord]
    let statusCode: Int?
    let mediaType: String?
    let textEncodingName: String?
    let byteCount: Int
    let acquisitionIdentity: String
    let source: PreflightPageAcquisitionSource
    let isolationScope: PreflightIsolationScope

    init(
        requestedURL: URL,
        data: Data,
        finalURL: URL,
        redirectChain: [PreflightRedirectRecord] = [],
        statusCode: Int? = nil,
        mediaType: String?,
        textEncodingName: String?,
        acquisitionIdentity: String,
        source: PreflightPageAcquisitionSource,
        isolationScope: PreflightIsolationScope
    ) {
        self.requestedURL = requestedURL
        self.data = data
        self.finalURL = finalURL
        self.redirectChain = redirectChain
        self.statusCode = statusCode
        self.mediaType = mediaType
        self.textEncodingName = textEncodingName
        self.byteCount = data.count
        self.acquisitionIdentity = acquisitionIdentity
        self.source = source
        self.isolationScope = isolationScope
    }
}

enum PreflightPageAcquisitionError: Error, Equatable, Sendable {
    case invalidResponse
    case rejectedStatus(Int)
    case responseTooLarge
    case unsupportedContent
    case unsafeRedirect
    case authenticationRequired
    case timedOut
    case emptyContent
    case isolationUnavailable
}

protocol PreflightPageAcquiring: Sendable {
    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage
}

protocol PreflightRenderedPageAcquiring: Sendable {
    @MainActor
    func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage
}
