import Foundation
import Nuke
import Testing
@testable import BrowseCraft

// 中文注释：共享图片管线的内存缓存上限是显式定的（2026-10-10 复审 B-10），不随 Nuke 按物理内存算的缺省漂。
struct ImageCacheConfiguratorMemoryLimitTests {
    @Test func configuringTheSharedPipelineCapsTheSharedMemoryCache() throws {
        let defaults: UserDefaults = UserDefaults(suiteName: "ImageCacheConfiguratorMemoryLimitTests-\(UUID().uuidString)")!
        let configurator: ImageCacheConfigurator = ImageCacheConfigurator(
            userDefaults: defaults,
            dataCacheName: "ImageCacheConfiguratorMemoryLimitTests-\(UUID().uuidString)"
        )

        try configurator.configureSharedPipeline()

        let expectedLimit: Int = min(ImageCache.defaultCostLimit(), ImageCacheConfigurator.sharedMemoryLimitBytes)
        #expect(ImageCache.shared.costLimit == expectedLimit)
        #expect(ImageCache.shared.costLimit <= 256 * 1024 * 1024)
        #expect(ImageCache.shared.entryCostLimit == ImageCacheConfigurator.sharedMemoryEntryCostLimit)
        // 中文注释：上限定在 `ImageCache.shared` 上才有效——共享管线用的就是它。
        #expect(ImagePipeline.shared.configuration.imageCache as AnyObject === ImageCache.shared)
    }
}
