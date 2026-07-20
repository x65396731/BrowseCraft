import Foundation

enum SourceLoginSessionError: LocalizedError {
    case webViewUnavailable
    case noCredentialMaterial
    case invalidStorageResult

    var errorDescription: String? {
        switch self {
        case .webViewUnavailable:
            return "Wait for the login page to finish loading before saving."
        case .noCredentialMaterial:
            return "No login Cookie or configured token was found. Complete login before tapping Done."
        case .invalidStorageResult:
            return "The login page returned an unreadable storage result."
        }
    }
}

struct SourceLoginStorageSnapshot: Equatable {
    let localStorage: [String: String]
    let sessionStorage: [String: String]
}
