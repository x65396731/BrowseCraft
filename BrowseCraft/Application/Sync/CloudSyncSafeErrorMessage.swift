import Foundation

enum CloudSyncSafeErrorMessage {
    static func describe(_ error: any Error) -> String {
        if let securityError: CloudSyncPayloadSecurityError = error as? CloudSyncPayloadSecurityError {
            return securityError.description
        }
        if let sessionError: CloudSyncSessionError = error as? CloudSyncSessionError {
            return sessionError.description
        }
        return "Cloud synchronization failed type=\(String(reflecting: type(of: error)))"
    }
}

enum CloudSyncSessionError: Error, Hashable, Sendable, CustomStringConvertible {
    case synchronizationDisabled
    case accountChanged
    case alreadyRunning

    var description: String {
        switch self {
        case .synchronizationDisabled:
            return "Cloud synchronization is disabled"
        case .accountChanged:
            return "Cloud account changed during synchronization"
        case .alreadyRunning:
            return "Cloud synchronization is already running"
        }
    }
}
