import Foundation

// 中文注释：SourceRepository 提供 Source 的读取、保存和删除入口。

/// 中文注释：面向领域层的源仓储协议，负责源规则的读取、保存和删除。
/// 中文注释：删除 Source 时只清理当前选择等运行状态；历史和收藏快照独立保留。
protocol SourceRepository: Sendable {
    func fetchSources() throws -> [Source]
    func saveSource(_ source: Source) throws
    func deleteSource(id: String) throws
    func reconcileSourceSlotAssignments() throws -> [Source]
    func activateSource(
        id: String,
        replacingSourceID: String?
    ) throws -> [Source]
}

extension SourceRepository {
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
            let noun: String = limit == 1 ? "source" : "sources"
            return "Your account can activate up to \(limit) custom \(noun). Purchase more site slots in Settings > Premium to activate another source."
        case .sourceLockedBySlotLimit:
            return "This source is restored but locked by your current source limit. Replace an active source or purchase more site slots in Settings > Premium."
        case .invalidSourceSlotReplacement:
            return "The selected active source could not be replaced. Reload Sources and try again."
        }
    }
}
