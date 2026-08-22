import Foundation

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
