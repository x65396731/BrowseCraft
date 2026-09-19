import Foundation

enum SourceLoginSessionError: LocalizedError {
    case webViewUnavailable
    case noCredentialMaterial
    case invalidStorageResult

    var errorDescription: String? {
        switch self {
        case .webViewUnavailable:
            return NSLocalizedString("source_login_error_webview_unavailable", comment: "登录页未加载完")
        case .noCredentialMaterial:
            return NSLocalizedString("source_login_error_no_credential", comment: "没抓到登录凭据")
        case .invalidStorageResult:
            return NSLocalizedString("source_login_error_invalid_storage", comment: "存储结果不可读")
        }
    }
}

struct SourceLoginStorageSnapshot: Equatable {
    let localStorage: [String: String]
    let sessionStorage: [String: String]
}
