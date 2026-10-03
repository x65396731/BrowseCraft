import BrowseCraftDomain
import Foundation

// 中文注释：Source 列表读写用例，供来源管理、书架和历史页面读取本地 Source 状态。

/// 中文注释：从本地存储加载所有内容源，包括内置源和用户添加的源。
struct LoadSourcesUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute() throws -> [Source] {
        return try self.sourceRepository.fetchSources()
    }
}

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

/// 中文注释：删除一个 Source 并连带删除它的历史与收藏（`BCA-DB-005`），交回被删内容供撤销；
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

    /// 中文注释：撤销删除，按被删内容原样写回。
    func restore(_ receipt: SourceDeletionReceipt) throws {
        try self.sourceRepository.restoreDeletedSource(receipt)
    }

    /// 中文注释：撤销窗口结束后把删除告知同步协调器。
    func notifyChanges() {
        self.sourceRepository.notifyLocalChanges()
    }
}
