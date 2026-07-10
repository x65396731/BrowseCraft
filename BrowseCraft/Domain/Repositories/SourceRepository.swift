import Foundation

// 中文注释：SourceRepository 提供 Source 的读取、保存和删除入口。

/// 中文注释：面向领域层的源仓储协议，负责源规则的读取、保存和删除。
/// 中文注释：删除 Source 时只清理当前选择等运行状态；历史和收藏快照独立保留。
protocol SourceRepository {
    func fetchSources() throws -> [Source]
    func saveSource(_ source: Source) throws
    func deleteSource(id: String) throws
}
