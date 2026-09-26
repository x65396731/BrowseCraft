#if DEBUG
import Foundation

/// 中文注释：仅 DEBUG——拍 App Store 截图用的演示模式。带启动参数 `-BrowseCraftDemoMode` 时：
/// - 数据库换成独立的 demo.sqlite，每次启动删掉重建再写入演示来源与纪录，真实数据库完全不碰；
/// - 规则执行换成 `DemoSourceRuntimeResolver`，列表、详情、正文都返回自造内容，不联网；
/// - 账户会话、iCloud 同步与推送注册不启动。
/// `-BrowseCraftDemoAssets <目录>` 指向演示封面所在目录（cover-01.png … cover-12.png）。
/// 模拟器进程能直接读宿主机路径，所以封面不必进包；未传参或文件缺失时封面走占位图。
enum DemoMode {
    static let isEnabled: Bool = ProcessInfo.processInfo.arguments.contains("-BrowseCraftDemoMode")

    static let assetsDirectory: URL? = {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let flagIndex: Int = arguments.firstIndex(of: "-BrowseCraftDemoAssets") else {
            return nil
        }
        let valueIndex: Int = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return URL(fileURLWithPath: arguments[valueIndex], isDirectory: true)
    }()

    /// 中文注释：演示封面按 1…12 编号，对应 `DemoContent.works` 的顺序。
    static func coverURL(number: Int) -> URL? {
        guard let directory: URL = self.assetsDirectory else {
            return nil
        }
        let url: URL = directory.appendingPathComponent(String(format: "cover-%02d.png", number))
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    /// 中文注释：每次启动都从空库开始，演示内容才稳定可复现。
    static func freshDatabasePath() throws -> String {
        let directory: URL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("BrowseCraftDemo", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("demo.sqlite").path
    }
}
#endif
