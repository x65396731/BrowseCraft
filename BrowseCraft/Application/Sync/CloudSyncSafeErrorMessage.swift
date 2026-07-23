import CryptoKit
import Foundation
import OSLog

/// 中文注释：云同步诊断只记录不可逆实体摘要和已脱敏错误，不记录业务 ID、URL、Header 或 JSON 内容。
enum CloudSyncDiagnostics {
    private static let logger: Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BrowseCraft",
        category: "CloudSync"
    )

    static func logSyncStarted(
        trigger: CloudSyncTrigger,
        accountScope: CloudAccountScope
    ) {
        let accountHash: String = Self.hashIdentifier(accountScope.rawValue)
        Self.logger.notice(
            "sync started trigger=\(trigger.rawValue, privacy: .public) accountHash=\(accountHash, privacy: .public)"
        )
    }

    static func logSyncCompleted(_ result: CloudSyncRunResult) {
        let accountHash: String = Self.hashIdentifier(result.accountScope.rawValue)
        let durationMilliseconds: Int = max(
            0,
            Int(result.finishedAt.timeIntervalSince(result.startedAt) * 1_000)
        )
        Self.logger.notice(
            "sync completed trigger=\(result.trigger.rawValue, privacy: .public) accountHash=\(accountHash, privacy: .public) uploadedCount=\(result.uploadedCount, privacy: .public) downloadedCount=\(result.downloadedCount, privacy: .public) deletedCount=\(result.deletedCount, privacy: .public) skippedCount=\(result.skippedCount, privacy: .public) failedCount=\(result.failedCount, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logSyncFailed(
        trigger: CloudSyncTrigger,
        accountScope: CloudAccountScope,
        error: any Error
    ) {
        let accountHash: String = Self.hashIdentifier(accountScope.rawValue)
        let safeError: String = CloudSyncSafeErrorMessage.describe(error)
        Self.logger.error(
            "sync failed trigger=\(trigger.rawValue, privacy: .public) accountHash=\(accountHash, privacy: .public) error=\(safeError, privacy: .public)"
        )
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
        let accountHash: String = Self.hashIdentifier(accountScope.rawValue)
        Self.logger.notice(
            "cloud fetch summary accountHash=\(accountHash, privacy: .public) rawSourceCount=\(rawSourceCount, privacy: .public) mappedSourceCount=\(mappedSourceCount, privacy: .public) rawFavoriteItemCount=\(rawFavoriteItemCount, privacy: .public) mappedFavoriteItemCount=\(mappedFavoriteItemCount, privacy: .public) unknownRecordCount=\(unknownRecordCount, privacy: .public) rejectedRecordCount=\(rejectedRecordCount, privacy: .public)"
        )
    }

    static func logDownloadMergeSummary(
        entityType: SyncEntityType,
        accountScope: CloudAccountScope,
        receivedCount: Int,
        downloadedCount: Int,
        deletedCount: Int,
        skippedCount: Int
    ) {
        let accountHash: String = Self.hashIdentifier(accountScope.rawValue)
        Self.logger.notice(
            "download merge summary entityType=\(entityType.rawValue, privacy: .public) accountHash=\(accountHash, privacy: .public) receivedCount=\(receivedCount, privacy: .public) downloadedCount=\(downloadedCount, privacy: .public) deletedCount=\(deletedCount, privacy: .public) skippedCount=\(skippedCount, privacy: .public)"
        )
    }

    static func logLocalPartitionSummary(
        entityType: SyncEntityType,
        accountScope: CloudAccountScope,
        acceptedCount: Int,
        requeuedCount: Int,
        liveCount: Int,
        tombstoneCount: Int
    ) {
        let accountHash: String = Self.hashIdentifier(accountScope.rawValue)
        Self.logger.notice(
            "local partition summary entityType=\(entityType.rawValue, privacy: .public) accountHash=\(accountHash, privacy: .public) acceptedCount=\(acceptedCount, privacy: .public) requeuedCount=\(requeuedCount, privacy: .public) liveCount=\(liveCount, privacy: .public) tombstoneCount=\(tombstoneCount, privacy: .public)"
        )
    }

    static func logPendingUpload(_ item: SyncQueueItem) {
        guard let lastError: String = item.lastError else {
            return
        }
        let entityHash: String = Self.hashIdentifier(item.entityID)
        let nextRetryAt: String = item.nextRetryAt?.ISO8601Format() ?? "immediate"
        Self.logger.error(
            "sync_queue pending entityType=\(item.entityType.rawValue, privacy: .public) entityHash=\(entityHash, privacy: .public) operation=\(item.operation.rawValue, privacy: .public) retryCount=\(item.retryCount, privacy: .public) nextRetryAt=\(nextRetryAt, privacy: .public) lastError=\(lastError, privacy: .public)"
        )
    }

    static func logLocalRecordRejection(
        entityType: SyncEntityType,
        entityID: String,
        code: String,
        error: any Error
    ) {
        let entityHash: String = Self.hashIdentifier(entityID)
        let safeError: String = CloudSyncSafeErrorMessage.describe(error)
        Self.logger.error(
            "upload rejected before CloudKit entityType=\(entityType.rawValue, privacy: .public) entityHash=\(entityHash, privacy: .public) code=\(code, privacy: .public) detail=\(safeError, privacy: .public)"
        )
    }

    private static func hashIdentifier(_ value: String) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}

enum CloudSyncSafeErrorMessage {
    static func describe(_ error: any Error) -> String {
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
