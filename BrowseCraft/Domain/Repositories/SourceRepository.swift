import BrowseCraftDomain
import Foundation

// 中文注释：SourceRepository 提供 Source 的读取、保存和删除入口。

/// 中文注释：面向领域层的源仓储协议，负责源规则的读取、保存和删除。
/// 中文注释：删除 Source 时在同一写事务里连带删除它的三张历史表记录与收藏（`BCA-DB-005`），并交回被删内容供撤销；
/// 库的当前选择正好是它时清空（`BCA-DB-004`）。
protocol SourceRepository: Sendable {
    func fetchSources() throws -> [Source]
    func saveSource(_ source: Source) throws
    /// 中文注释：已添加来源上次应用的目录规则原文指纹（sourceID → 指纹）；没记过的来源不在表里。
    /// 目录跟随先比它，相同就不物化整条规则（`docs/design/Catalog-Rule-Update-Design.md` 第二节）。
    func catalogRuleFingerprints() throws -> [String: String]
    /// 中文注释：目录物化出的来源连同各自的指纹一次写入，一个写事务；语义与逐条 `saveSource` 相同（含位置额度与同步入队）。
    func saveCatalogSources(_ sources: [Source], fingerprintsBySourceID: [String: String]) throws
    /// 中文注释：只给来源行盖指纹——规则与本地相等、只是还没记过指纹时用；不改规则、不动 `updatedAt`、不入同步队列。
    func stampCatalogRuleFingerprints(_ fingerprintsBySourceID: [String: String]) throws
    /// 中文注释：删除来源并连带删除历史与收藏，交回被删内容；来源不在册时仍做清理但返回 nil。
    /// 不发本地变更通知——调用方在撤销窗口结束后调 `notifyLocalChanges()`（见 `docs/design/Source-Deletion-Cascade-Design.md` 第四节）。
    @discardableResult
    func deleteSource(id: String) throws -> SourceDeletionReceipt?
    /// 中文注释：撤销删除——把被删的来源、历史与收藏原样写回，并以当前时间重新入队为更新。
    func restoreDeletedSource(_ receipt: SourceDeletionReceipt) throws
    /// 中文注释：把 `deleteSource` 攒下的本地变更告知同步协调器；没有同步的仓储不必实现。
    func notifyLocalChanges()
    func reconcileSourceSlotAssignments() throws -> [Source]
    func activateSource(
        id: String,
        replacingSourceID: String?
    ) throws -> [Source]
}

extension SourceRepository {
    func notifyLocalChanges() {}

    func catalogRuleFingerprints() throws -> [String: String] {
        return [:]
    }

    func saveCatalogSources(_ sources: [Source], fingerprintsBySourceID: [String: String]) throws {
        _ = fingerprintsBySourceID
        for source: Source in sources {
            try self.saveSource(source)
        }
    }

    func stampCatalogRuleFingerprints(_ fingerprintsBySourceID: [String: String]) throws {
        _ = fingerprintsBySourceID
    }

    func reconcileSourceSlotAssignments() throws -> [Source] {
        return try self.fetchSources()
    }

    func activateSource(
        id: String,
        replacingSourceID: String?
    ) throws -> [Source] {
        _ = replacingSourceID
        guard var source: Source = try self.fetchSources().first(where: { source in
            return source.id == id
        }) else {
            return try self.fetchSources()
        }
        source.enabled = true
        try self.saveSource(source)
        return try self.fetchSources()
    }
}

/// 中文注释：删除来源时的留底——撤销时按这里的内容原样写回（`docs/design/Source-Deletion-Cascade-Design.md` 第四节）。
struct SourceDeletionReceipt: Sendable {
    /// 删除前的来源记录原样（含启用状态；`deletedAt` 为 nil）。
    let source: Source
    /// 删除前库的当前选择正好是它时的库状态（来源 ID 与列表位置）；它不是当前来源时为 nil。
    let librarySelection: UserLibraryState?
    let comicHistories: [ComicChapterHistory]
    let videoHistories: [VideoWatchHistory]
    let bookHistories: [BookReadingHistory]
    /// 删除前在册、这次被写了删除标记的收藏条目（带原收藏时间）。
    let favoriteItems: [FavoriteContentItem]
    /// 这次删除是否往同步队列写了东西（非内置来源，或有收藏）；为真时撤销窗口结束后要发本地变更通知。
    let enqueuedSyncChanges: Bool
}

/// 中文注释：站点位置只约束用户添加的 Source；内置 Source 不消耗购买位置。
enum SourceSlotPolicy: Sendable {
    static let includedSiteSlotCount: Int = 1

    static func effectiveLimit(storedLimit: Int) -> Int {
        return max(Self.includedSiteSlotCount, storedLimit)
    }

    static func consumesNewSlot(
        source: Source,
        existingSourceConsumesSlot: Bool
    ) -> Bool {
        return source.isBuiltIn == false
            && source.deletedAt == nil
            && source.enabled
            && existingSourceConsumesSlot == false
    }
}

enum SourceRepositoryError: LocalizedError, Equatable, Sendable {
    case siteSlotLimitReached(limit: Int)
    case sourceLockedBySlotLimit
    case invalidSourceSlotReplacement

    var errorDescription: String? {
        switch self {
        case .siteSlotLimitReached(let limit):
            return String(format: NSLocalizedString("source_error_slot_limit_reached", comment: ""), limit)
        case .sourceLockedBySlotLimit:
            return NSLocalizedString("source_error_locked_by_slot_limit", comment: "")
        case .invalidSourceSlotReplacement:
            return NSLocalizedString("source_error_invalid_slot_replacement", comment: "")
        }
    }
}
