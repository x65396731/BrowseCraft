import Foundation

/// 中文注释：演示模式（拍 App Store 截图）的启动参数开关，全仓唯一读取点；`App/Demo/DemoMode` 与 `Shared/Ads/AdPlaybackHandler`
/// 都从这里取。Release 恒为 false，调用方不必再各包一层 `#if DEBUG`（2026-10-20 审计发布前清单第 10 项）。
enum DemoModeFlag {
    static let launchArgument: String = "-BrowseCraftDemoMode"

    static let isEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(Self.launchArgument)
        #else
        return false
        #endif
    }()
}
