import Foundation

// 中文注释：SourceRepository 提供 Source 的读取、保存和删除入口。

/// 中文注释：面向领域层的源仓储协议，负责源规则的读取、保存和删除。
/// 中文注释：删除 Source 时必须同时清理归属于该 sourceID 的运行状态和历史记录。
protocol SourceRepository {
    func fetchSources() throws -> [Source]
    func saveSource(_ source: Source) throws
    func deleteSource(id: String) throws
}
