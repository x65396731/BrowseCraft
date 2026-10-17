import BrowseCraftLog
import Foundation

/// 中文注释：云同步诊断只记录不可逆实体摘要和已脱敏错误，不记录业务 ID、URL、Header 或 JSON 内容。
/// 记录走全仓唯一的日志类型 `AppLog`（Logging-Design.md）；账号与实体标识一律 `.id`，错误先过 `CloudSyncSafeErrorMessage`。
enum CloudSyncDiagnostics {
    static func logSyncStarted(
        trigger: CloudSyncTrigger,
        accountScope: CloudAccountScope
    ) {
        AppLog.notice(.sync, "sync-started", [
            "trigger": .code("\(trigger.rawValue)"),
            "accountHash": .id(accountScope.rawValue)
        ])
    }

    static func logSyncCompleted(_ result: CloudSyncRunResult) {
        AppLog.notice(.sync, "sync-completed", [
            "trigger": .code("\(result.trigger.rawValue)"),
            "accountHash": .id(result.accountScope.rawValue),
            "uploadedCount": .int(result.uploadedCount),
            "downloadedCount": .int(result.downloadedCount),
            "deletedCount": .int(result.deletedCount),
            "skippedCount": .int(result.skippedCount),
            "failedCount": .int(result.failedCount),
            "ms": .duration(max(0, result.finishedAt.timeIntervalSince(result.startedAt)))
        ])
    }

    static func logSyncFailed(
        trigger: CloudSyncTrigger,
        accountScope: CloudAccountScope,
        error: any Error
    ) {
        AppLog.error(.sync, "sync-failed", [
            "trigger": .code("\(trigger.rawValue)"),
            "accountHash": .id(accountScope.rawValue),
            "reason": .code(CloudSyncSafeErrorMessage.describe(error)),
            "error": .error(error)
        ])
    }

    static func logSyncPhase(
        _ phase: String,
        trigger: CloudSyncTrigger,
        accountScope: CloudAccountScope
    ) {
        AppLog.info(.sync, "sync-phase", [
            "phase": .code(phase),
            "trigger": .code("\(trigger.rawValue)"),
            "accountHash": .id(accountScope.rawValue)
        ])
    }

    static func logSyncRequest(
        trigger: CloudSyncTrigger,
        outcome: String
    ) {
        AppLog.info(.sync, "sync-request", [
            "trigger": .code("\(trigger.rawValue)"),
            "outcome": .code(outcome)
        ])
    }

    static func logIdentityGateRejected(
        accountScope: CloudAccountScope,
        reason: String
    ) {
        AppLog.error(.sync, "identity-gate-rejected", [
            "accountHash": .id(accountScope.rawValue),
            "reason": .code(reason)
        ])
    }

    static func logIdentityAssociation(
        event: String,
        localUserID: UUID,
        cloudUserID: UUID? = nil
    ) {
        AppLog.notice(.identity, "identity-association", [
            "event": .code(event),
            "localUserHash": .id(localUserID),
            "cloudUserHash": cloudUserID.map { LogValue.id($0) } ?? .code("none")
        ])
    }

    static func logIdentityAssociationFailed(
        stage: String,
        error: any Error
    ) {
        AppLog.error(.identity, "identity-association-failed", [
            "stage": .code(stage),
            "reason": .code(CloudSyncSafeErrorMessage.describe(error)),
            "error": .error(error)
        ])
    }

    static func logIdentityAttestation(
        accountScope: CloudAccountScope,
        outcome: String
    ) {
        AppLog.notice(.identity, "identity-attestation", [
            "accountHash": .id(accountScope.rawValue),
            "outcome": .code(outcome)
        ])
    }

    static func logIdentityChange(event: String) {
        AppLog.notice(.identity, "identity-change", ["event": .code(event)])
    }

    static func logRetry(
        accountScope: CloudAccountScope,
        outcome: String,
        delay: TimeInterval? = nil
    ) {
        AppLog.notice(.sync, "sync-retry", [
            "accountHash": .id(accountScope.rawValue),
            "outcome": .code(outcome),
            "delayMs": .duration(max(0, delay ?? 0))
        ])
    }

    static func logCloudFetchSummary(
        accountScope: CloudAccountScope,
        rawSourceCount: Int,
        mappedSourceCount: Int,
        rawFavoriteItemCount: Int,
        mappedFavoriteItemCount: Int,
        unknownRecordCount: Int,
        rejectedRecordCount: Int
    ) {
        AppLog.info(.sync, "cloud-fetch-summary", [
            "accountHash": .id(accountScope.rawValue),
            "rawSourceCount": .int(rawSourceCount),
            "mappedSourceCount": .int(mappedSourceCount),
            "rawFavoriteItemCount": .int(rawFavoriteItemCount),
            "mappedFavoriteItemCount": .int(mappedFavoriteItemCount),
            "unknownRecordCount": .int(unknownRecordCount),
            "rejectedRecordCount": .int(rejectedRecordCount)
        ])
    }

    static func logDownloadMergeSummary(
        entityType: SyncEntityType,
        accountScope: CloudAccountScope,
        receivedCount: Int,
        downloadedCount: Int,
        deletedCount: Int,
        skippedCount: Int
    ) {
        AppLog.info(.sync, "download-merge-summary", [
            "entityType": .code("\(entityType.rawValue)"),
            "accountHash": .id(accountScope.rawValue),
            "receivedCount": .int(receivedCount),
            "downloadedCount": .int(downloadedCount),
            "deletedCount": .int(deletedCount),
            "skippedCount": .int(skippedCount)
        ])
    }

    static func logLocalPartitionSummary(
        entityType: SyncEntityType,
        accountScope: CloudAccountScope,
        acceptedCount: Int,
        requeuedCount: Int,
        liveCount: Int,
        tombstoneCount: Int
    ) {
        AppLog.info(.sync, "local-partition-summary", [
            "entityType": .code("\(entityType.rawValue)"),
            "accountHash": .id(accountScope.rawValue),
            "acceptedCount": .int(acceptedCount),
            "requeuedCount": .int(requeuedCount),
            "liveCount": .int(liveCount),
            "tombstoneCount": .int(tombstoneCount)
        ])
    }

    static func logPendingUpload(_ item: SyncQueueItem) {
        guard let lastError: String = item.lastError else {
            return
        }
        AppLog.error(.sync, "sync-queue-pending", [
            "entityType": .code("\(item.entityType.rawValue)"),
            "entityHash": .id(item.entityID),
            "operation": .code("\(item.operation.rawValue)"),
            "retryCount": .int(item.retryCount),
            "nextRetryAt": .code(item.nextRetryAt?.ISO8601Format() ?? "immediate"),
            "lastError": .code(lastError)
        ])
    }

    static func logLocalRecordRejection(
        entityType: SyncEntityType,
        entityID: String,
        code: String,
        error: any Error
    ) {
        AppLog.error(.sync, "upload-rejected-before-cloudkit", [
            "entityType": .code("\(entityType.rawValue)"),
            "entityHash": .id(entityID),
            "code": .code(code),
            "reason": .code(CloudSyncSafeErrorMessage.describe(error))
        ])
    }
}

enum CloudSyncSafeErrorMessage {
    static func describe(_ error: any Error) -> String {
        if let storeError: CloudAppUserIdentityStoreError =
            error as? CloudAppUserIdentityStoreError {
            switch storeError {
            case .accountUnavailable:
                return "iCloud identity account unavailable"
            case .accessDenied:
                return "iCloud identity access denied"
            case .malformedRecord:
                return "iCloud identity record malformed"
            case .unsupportedSchemaVersion(let version):
                return "iCloud identity schema unsupported version=\(version)"
            case .temporarilyUnavailable:
                return "iCloud identity temporarily unavailable"
            case .operationFailed:
                return "iCloud identity operation failed"
            }
        }
        if let associationError: CloudAppUserIdentityAssociationError =
            error as? CloudAppUserIdentityAssociationError {
            switch associationError {
            case .signInRequired:
                return "Portal sign-in required before iCloud identity association"
            case .activeUserChanged:
                return "Active user changed during iCloud identity association"
            case .unexpectedState:
                return "Unexpected iCloud identity association state"
            }
        }
        if let adoptionError: AppUserIdentityAdoptionError =
            error as? AppUserIdentityAdoptionError {
            switch adoptionError {
            case .invalidCloudIdentity:
                return "Invalid iCloud identity for adoption"
            case .activeUserChanged:
                return "Active user changed during identity adoption"
            case .portalSessionResetFailed:
                return "Portal session reset failed during identity adoption"
            case .identityRollbackFailed:
                return "Identity rollback failed during adoption"
            }
        }
        if let securityError: CloudSyncPayloadSecurityError = error as? CloudSyncPayloadSecurityError {
            return securityError.description
        }
        if let sessionError: CloudSyncSessionError = error as? CloudSyncSessionError {
            return sessionError.description
        }
        if let operationError: CloudRecordOperationError = error as? CloudRecordOperationError {
            return operationError.description
        }
        return "Cloud synchronization failed type=\(String(reflecting: type(of: error)))"
    }
}

enum CloudSyncSessionError: Error, Hashable, Sendable, CustomStringConvertible {
    case synchronizationDisabled
    case accountChanged
    case identityNotAssociated
    case activeUserChanged
    case alreadyRunning

    var description: String {
        switch self {
        case .synchronizationDisabled:
            return "Cloud synchronization is disabled"
        case .accountChanged:
            return "Cloud account changed during synchronization"
        case .identityNotAssociated:
            return "The iCloud account is not linked to the active AnyPortal profile"
        case .activeUserChanged:
            return "The active AnyPortal profile changed during synchronization"
        case .alreadyRunning:
            return "Cloud synchronization is already running"
        }
    }
}
