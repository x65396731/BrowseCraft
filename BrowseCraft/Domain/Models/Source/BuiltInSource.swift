import Foundation

// 中文注释：BuiltInSource 声明应用随包来源，并为每个来源提供明确 runtime 配置。

/// 中文注释：应用随包提供的内置源。
/// 中文注释：内置源和用户源存放在同一个仓储中，稳定 ID 用于避免每次启动重复插入。
/// 中文注释：这里只负责声明内置来源；具体执行由对应 SourceRuntime 负责。
enum BuiltInSource {
    static func allBuiltIns(now: Date = Date()) -> [Source] {
        _ = now
        return []
    }
}
