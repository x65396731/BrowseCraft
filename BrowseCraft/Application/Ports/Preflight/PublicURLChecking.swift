import Foundation

// 中文注释：公共地址校验只在 App 的预检里用，2026-10-10 从 BrowseCraftDomain 搬回。

enum PublicURLCheckError: Error, Equatable, Sendable {
    case unsupportedScheme
    case userInfoNotAllowed
    case missingHost
    case localHost
    case nonPublicAddress
    case resolutionFailed
}

protocol PublicURLChecking: Sendable {
    func validate(_ url: URL) throws
    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool
}
