import Foundation

// 中文注释：历史内置 Source 同步入口保留为空操作，真实 catalog 数据改由用户手动导入。

/// 中文注释：不再在启动时自动写入任何 Source，用户初始状态保持空规则列表。
struct SyncBuiltInSourcesUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute() throws {
        _ = self.sourceRepository
    }
}
