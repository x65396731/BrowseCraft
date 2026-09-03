import Foundation

public enum PreflightPageAcquisitionSource: String, Hashable, Sendable {
    case http
    case rendered
}

public enum PreflightIsolationScope: String, Hashable, Sendable {
    case fullHTTP
    case mainFrameWebView
}

public struct PreflightRedirectRecord: Hashable, Sendable {
    public init(
        statusCode: Int?,
        sourceURL: URL,
        targetURL: URL
    ) {
        self.statusCode = statusCode
        self.sourceURL = sourceURL
        self.targetURL = targetURL
    }

    public let statusCode: Int?
    public let sourceURL: URL
    public let targetURL: URL
}

public struct PreflightPageRequest: Hashable, Sendable {
    public let url: URL
    public let timeoutSeconds: TimeInterval

    public init(url: URL, timeoutSeconds: TimeInterval = 12) {
        self.url = url
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct PreflightAcquiredPage: Hashable, Sendable {
    public let requestedURL: URL
    public let data: Data
    public let finalURL: URL
    public let redirectChain: [PreflightRedirectRecord]
    public let statusCode: Int?
    public let mediaType: String?
    public let textEncodingName: String?
    public let byteCount: Int
    public let acquisitionIdentity: String
    public let source: PreflightPageAcquisitionSource
    public let isolationScope: PreflightIsolationScope

    public init(
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

public enum PreflightPageAcquisitionError: Error, Equatable, Sendable {
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

public protocol PreflightPageAcquiring: Sendable {
    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage
}

public protocol PreflightRenderedPageAcquiring: Sendable {
    @MainActor
    func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage
}
