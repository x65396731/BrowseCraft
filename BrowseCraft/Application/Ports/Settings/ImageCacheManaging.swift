import BrowseCraftDomain
import Foundation

// 中文注释：设置界面需要改图片缓存上限并清空缓存，但不该认识 Nuke 的 pipeline / DataCache。
// 这里声明界面真正需要的三个动作，由 Infrastructure 的 ImageCacheConfigurator 实现。
// （2026-09-18 收敛边界豁免：此前 SettingsViewModel 直接持有 ImageCacheConfigurator。）

/// 中文注释：图片缓存的应用层端口。只描述「应用设置」与「清空」两件事，不暴露任何图片库细节。
/// 刻意不标 `@MainActor`：一旦标了，实现类型会整体被推断为主 actor 隔离，而实现内部有磁盘裁剪的队列工作。
/// 调用方（`SettingsViewModel`）自身在主 actor 上，同步调用即可。
protocol ImageCacheManaging: AnyObject {
    /// 中文注释：落盘并生效新的缓存上限；失败时抛错，由调用方决定文案。
    func apply(settings: ImageCacheSettings) throws
    /// 中文注释：上限调小后按新上限裁剪已占用的磁盘缓存。
    func trimConfiguredDataCacheIfNeeded(settings: ImageCacheSettings)
    /// 中文注释：清空内存与磁盘缓存；磁盘清理是异步的，返回不代表已清完。
    func clearConfiguredCaches()
}
