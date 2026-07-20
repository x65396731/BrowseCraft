import Foundation

enum SourceCredentialOrigin: String {
    case webView
    case manual
    case apiLogin
    case importedCookie
    case memory
}

enum SourceCredentialStorage: String {
    case localStorage
    case sessionStorage
}

struct SourceCredential {
    let sourceID: String
    let baseURL: URL?
    let cookies: [HTTPCookie]
    let headers: [String: String]
    let accessToken: String?
    let refreshToken: String?
    let localStorage: [String: String]
    let sessionStorage: [String: String]
    let expiresAt: Date?
    let origin: SourceCredentialOrigin

    init(
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
