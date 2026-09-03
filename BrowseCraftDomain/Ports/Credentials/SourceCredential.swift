import Foundation

public enum SourceCredentialOrigin: String, Sendable {
    case webView
    case manual
    case apiLogin
    case importedCookie
    case memory
}

public enum SourceCredentialStorage: String, Sendable {
    case localStorage
    case sessionStorage
}

public struct SourceCredential: Sendable {
    public let sourceID: String
    public let baseURL: URL?
    public let cookies: [HTTPCookie]
    public let headers: [String: String]
    public let accessToken: String?
    public let refreshToken: String?
    public let localStorage: [String: String]
    public let sessionStorage: [String: String]
    public let expiresAt: Date?
    public let origin: SourceCredentialOrigin

    public init(
        sourceID: String,
        baseURL: URL? = nil,
        cookies: [HTTPCookie] = [],
        headers: [String: String] = [:],
        accessToken: String? = nil,
        refreshToken: String? = nil,
        localStorage: [String: String] = [:],
        sessionStorage: [String: String] = [:],
        expiresAt: Date? = nil,
        origin: SourceCredentialOrigin = .memory
    ) {
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.cookies = cookies
        self.headers = headers
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.localStorage = localStorage
        self.sessionStorage = sessionStorage
        self.expiresAt = expiresAt
        self.origin = origin
    }
}
