import Foundation

// 中文注释：SourceRepository.swift 属于仓储协议层，用于说明本文件承载的核心职责。

/// 中文注释：面向领域层的源仓储协议，负责源规则的读取、保存和删除。
/// 中文注释：协议把来源存储细节隔离在基础设施层，当前 App 装配使用会话内存实现。
protocol SourceRepository {
    /// 中文注释：fetchSources 方法封装当前类型的一段业务或界面行为。
    func fetchSources() throws -> [Source]
    /// 中文注释：saveSource 方法封装当前类型的一段业务或界面行为。
    func saveSource(_ source: Source) throws
    /// 中文注释：deleteSource 方法封装当前类型的一段业务或界面行为。
    func deleteSource(id: String) throws
}
