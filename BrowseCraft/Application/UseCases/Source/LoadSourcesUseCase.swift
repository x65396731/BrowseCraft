import BrowseCraftDomain
import Foundation

// 中文注释：Source 位置额度、槽位启用与删除的用例（文件名沿用；零引用的 `LoadSourcesUseCase` 已于 2026-10-20 删除）。

/// 中文注释：读取当前用户实际生效的 Source 位置上限，展示语义与保存 Source 时的额度校验保持一致。
struct LoadSourceSlotLimitUseCase {
    private let appUserRepository: AppUserRepository

    init(appUserRepository: AppUserRepository) {
        self.appUserRepository = appUserRepository
    }

    func execute(userID: String) throws -> Int {
        let storedLimit: Int = try self.appUserRepository
            .fetchUser(id: userID)?
            .siteSlotLimit ?? SourceSlotPolicy.includedSiteSlotCount
        return SourceSlotPolicy.effectiveLimit(storedLimit: storedLimit)
    }
}

/// 中文注释：云恢复或权益变化后，把同步的 enabled 分配收敛到当前用户额度。
struct ReconcileSourceSlotAssignmentsUseCase: Sendable {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute() throws -> [Source] {
        return try self.sourceRepository.reconcileSourceSlotAssignments()
    }
}

/// 中文注释：在一个事务中启用锁定源，并在额度已满时替换指定的活动源。
struct ActivateSourceSlotUseCase: Sendable {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute(
        sourceID: String,
        replacingSourceID: String?
    ) throws -> [Source] {
        return try self.sourceRepository.activateSource(
            id: sourceID,
            replacingSourceID: replacingSourceID
        )
    }
}

/// 中文注释：删除一个 Source（历史与收藏保留，`BCA-DB-005`），交回来源与库状态的留底供撤销；
/// 由 Sources 页面的左滑 / 长按删除与删除个人规则触发。
struct DeleteSourceUseCase: Sendable {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    /// 中文注释：不发同步通知；撤销窗口结束后由 `notifyChanges()` 补发。
    @discardableResult
    func execute(sourceId: String) throws -> SourceDeletionReceipt? {
        return try self.sourceRepository.deleteSource(id: sourceId)
    }

    /// 中文注释：撤销删除，按留底写回来源与库状态。
    func restore(_ receipt: SourceDeletionReceipt) throws {
        try self.sourceRepository.restoreDeletedSource(receipt)
    }

    /// 中文注释：撤销窗口结束后把删除告知同步协调器。
    func notifyChanges() {
        self.sourceRepository.notifyLocalChanges()
    }
}
