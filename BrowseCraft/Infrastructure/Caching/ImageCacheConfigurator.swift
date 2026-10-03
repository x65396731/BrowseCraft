import Foundation
@preconcurrency import Nuke

// 中文注释：ImageCacheConfigurator 负责把应用设置转换成 Nuke 图片缓存配置。

/// 中文注释：对外保持 ImageCache 命名，内部才接触 Nuke 的 ImagePipeline/DataCache 细节。
/// 界面层经 `ImageCacheManaging` 端口使用它，不直接持有本类型。
final class ImageCacheConfigurator: ImageCacheManaging {
    private let userDefaults: UserDefaults
    private let dataCacheName: String
    private(set) var dataCache: DataCache?

    init(
        userDefaults: UserDefaults = .standard,
        dataCacheName: String = "BrowseCraft.ImageDataCache"
    ) {
        self.userDefaults = userDefaults
        self.dataCacheName = dataCacheName
    }

    @discardableResult
    func configureSharedPipeline() throws -> ImageCacheSettings {
        let settings: ImageCacheSettings = ImageCacheSettings.load(from: self.userDefaults)
        try self.configureSharedPipeline(settings: settings)
        return settings
    }

    func configureSharedPipeline(settings: ImageCacheSettings) throws {
        let dataCache: DataCache = try self.makeDataCache(settings: settings)
        var configuration: ImagePipeline.Configuration = .withDataCache
        configuration.dataCache = dataCache
        // 中文注释：请求声明了目标像素宽度就按宽度降采样解码，否则走 Nuke 默认解码器。
        configuration.makeImageDecoder = DownsamplingImageDecoding.makeDecoder
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
        self.dataCache = dataCache
    }

    func apply(settings: ImageCacheSettings) throws {
        // 中文注释：先确认 Nuke pipeline 配置成功再落盘，避免设置值已保存但实际缓存上限没有切换。
        try self.configureSharedPipeline(settings: settings)
        settings.save(to: self.userDefaults)
    }

    func trimConfiguredDataCacheIfNeeded(settings: ImageCacheSettings) {
        guard let dataCache: DataCache = self.dataCache else {
            return
        }

        self.trim(
            dataCache: dataCache,
            maximumBytes: settings.limitBytes,
            targetBytes: settings.trimTargetBytes
        )
    }

    @MainActor
    func usage() async -> ImageCacheUsage {
        let coverBytes: Int = await Self.diskBytes(of: self.dataCache)
        let thumbnailBytes: Int = await Self.diskBytes(of: ItemThumbnailImageCachePlugin.shared.dataCache)
        return ImageCacheUsage(
            coverBytes: coverBytes,
            thumbnailBytes: thumbnailBytes,
            thumbnailLimitBytes: ItemThumbnailImageCachePlugin.diskLimitBytes
        )
    }

    /// 中文注释：封面与漫画页、列表缩略图两块一起清（此前只清了前一块，缩略图漏清）；
    /// 网页与系统网络缓存也一起清，但只清缓存类数据，登录状态所在的 Cookie 与本地存储不动。
    @MainActor
    func clearAllCaches() async {
        ImageCache.shared.removeAll()
        ItemThumbnailImageCachePlugin.shared.removeAllFromMemory()
        await Self.removeAll(from: self.dataCache)
        await Self.removeAll(from: ItemThumbnailImageCachePlugin.shared.dataCache)
        URLCache.shared.removeAllCachedResponses()
        await WebsiteCacheCleaner.removeCachedResources()
    }

    /// 中文注释：DataCache 的 removeAll 是排进它自己串行队列的异步动作；再排一个空任务等它跑完，才算真的清完。
    private static func removeAll(from dataCache: DataCache?) async {
        guard let dataCache: DataCache = dataCache else {
            return
        }
        dataCache.removeAll()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataCache.queue.async {
                continuation.resume()
            }
        }
    }

    /// 中文注释：在 DataCache 的串行队列上数目录里文件的占用，排在已提交的写入与裁剪之后，不占主线程。
    private static func diskBytes(of dataCache: DataCache?) async -> Int {
        guard let dataCache: DataCache = dataCache else {
            return 0
        }
        dataCache.flush()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            dataCache.queue.async {
                let bytes: Int = Self.diskEntries(in: dataCache.path).reduce(0) { partialResult, entry in
                    return partialResult + entry.allocatedBytes
                }
                continuation.resume(returning: bytes)
            }
        }
    }

    private func makeDataCache(settings: ImageCacheSettings) throws -> DataCache {
        let dataCache: DataCache = try DataCache(name: self.dataCacheName)
        dataCache.sizeLimit = settings.limitBytes
        return dataCache
    }

    private func trim(
        dataCache: DataCache,
        maximumBytes: Int,
        targetBytes: Int
    ) {
        dataCache.flush()
        dataCache.queue.async {
            let entries: [ImageCacheDiskEntry] = Self.diskEntries(in: dataCache.path)
            var totalBytes: Int = entries.reduce(0) { partialResult, entry in
                return partialResult + entry.allocatedBytes
            }

            guard totalBytes > maximumBytes else {
                return
            }

            // 中文注释：DataCache 的 trimRatio 不是 public，这里按文件最近访问时间手动执行 75% 目标清理。
            let sortedEntries: [ImageCacheDiskEntry] = entries.sorted { lhs, rhs in
                return lhs.lastAccessDate > rhs.lastAccessDate
            }
            var removableEntries: [ImageCacheDiskEntry] = sortedEntries

            while totalBytes > targetBytes,
                  let entry: ImageCacheDiskEntry = removableEntries.popLast() {
                try? FileManager.default.removeItem(at: entry.url)
                totalBytes -= entry.allocatedBytes
            }
        }
    }

    private static func diskEntries(in cachePath: URL) -> [ImageCacheDiskEntry] {
        let keys: Set<URLResourceKey> = [
            .contentAccessDateKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let urls: [URL] = try? FileManager.default.contentsOfDirectory(
            at: cachePath,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let values: URLResourceValues = try? url.resourceValues(forKeys: keys) else {
                return nil
            }

            return ImageCacheDiskEntry(
                url: url,
                allocatedBytes: values.totalFileAllocatedSize ?? values.fileSize ?? 0,
                lastAccessDate: values.contentAccessDate ?? Date.distantPast
            )
        }
    }
}

private struct ImageCacheDiskEntry {
    let url: URL
    let allocatedBytes: Int
    let lastAccessDate: Date
}
