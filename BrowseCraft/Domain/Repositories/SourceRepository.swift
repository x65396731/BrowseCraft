import Foundation

// 中文注释：SourceRepository 提供 Source 的读取、保存和删除入口。

/// 中文注释：面向领域层的源仓储协议，负责源规则的读取、保存和删除。
/// 中文注释：删除 Source 时只清理当前选择等运行状态；历史和收藏快照独立保留。
protocol SourceRepository {
    func fetchSources() throws -> [Source]
    func saveSource(_ source: Source) throws
    func deleteSource(id: String) throws
}

/// 中文注释：站点位置只约束用户添加的 Source；内置 Source 不消耗购买位置。
enum SourceSlotPolicy {
    static let includedSiteSlotCount: Int = 1

    static func effectiveLimit(storedLimit: Int) -> Int {
        return max(Self.includedSiteSlotCount, storedLimit)
    }

    static func consumesNewSlot(
        source: Source,
        existingSourceIsActive: Bool
    ) -> Bool {
        return source.isBuiltIn == false
            && source.deletedAt == nil
            && existingSourceIsActive == false
    }
}

enum SourceRepositoryError: LocalizedError, Equatable {
    case siteSlotLimitReached(limit: Int)

    var errorDescription: String? {
        switch self {
        case .siteSlotLimitReached(let limit):
            let noun: String = limit == 1 ? "source" : "sources"
            return "Your account can keep up to \(limit) custom \(noun). Purchase more site slots in Settings > Premium to add another source."
        }
    }
}
