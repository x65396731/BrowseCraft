import Combine
import Foundation

// 中文注释：SettingsViewModel 负责设置页中需要调用应用服务的状态与动作。

/// 中文注释：SettingsViewModel 把 Settings UI 与 Nuke 缓存配置隔离，View 不直接操作缓存服务。
final class SettingsViewModel: ObservableObject {
    @Published private(set) var imageCacheSettings: ImageCacheSettings
    @Published var cacheErrorMessage: String?
    @Published var cacheStatusMessage: String?

    private let imageCacheConfigurator: ImageCacheConfigurator

    init(imageCacheConfigurator: ImageCacheConfigurator) {
        self.imageCacheConfigurator = imageCacheConfigurator
        self.imageCacheSettings = ImageCacheSettings.load()
    }

    @MainActor
    func selectImageCacheLimit(_ limit: ImageCacheLimitOption) {
        let settings: ImageCacheSettings = ImageCacheSettings(limit: limit)

        do {
            try self.imageCacheConfigurator.apply(settings: settings)
            self.imageCacheConfigurator.trimConfiguredDataCacheIfNeeded(settings: settings)
            self.imageCacheSettings = settings
            self.cacheErrorMessage = nil
            self.cacheStatusMessage = nil
        } catch {
            #if DEBUG
            print("[BrowseCraftImageCache] settings update failed error=\(error)")
            #endif
            self.cacheErrorMessage = "Image cache settings could not be updated."
        }
    }

    @MainActor
    func clearImageCache() {
        self.imageCacheConfigurator.clearConfiguredCaches()
        self.cacheErrorMessage = nil
        // 中文注释：Nuke DataCache 的 removeAll 是异步写入队列动作，因此文案只承诺“已开始清理”。
        self.cacheStatusMessage = "Image cache clearing has started."

        #if DEBUG
        print("[BrowseCraftImageCache] clear cache requested")
        #endif
    }
}
