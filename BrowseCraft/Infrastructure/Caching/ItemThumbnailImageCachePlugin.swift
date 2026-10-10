import Foundation
@preconcurrency import Nuke

// 中文注释：ItemThumbnailImageCachePlugin 为 Library item 缩略图提供独立于漫画阅读图的缓存池。
// 界面层经 `ItemThumbnailImagePipelineProviding` 使用它，不直接引用本类型。
/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：`pipeline` 是 lazy，首次访问在主线程（RootView 注入）后只读；Nuke `ImagePipeline` 自身线程安全。
final class ItemThumbnailImageCachePlugin: ImagePipelineDelegate, ItemThumbnailImagePipelineProviding, @unchecked Sendable {
    static let shared: ItemThumbnailImageCachePlugin = ItemThumbnailImageCachePlugin()

    /// 中文注释：磁盘固定上限，不受设置页所选上限控制（缓存页把它单独列一条用量，用户裁定保持固定）。
    static let diskLimitBytes: Int = Constants.diskLimitBytes

    private enum Constants {
        static let dataCacheName: String = "BrowseCraft.ItemThumbnailDataCache"
        static let diskLimitBytes: Int = 256 * 1024 * 1024
        static let memoryLimitBytes: Int = 64 * 1024 * 1024
        static let cacheKeyPrefix: String = "item-thumbnail"
    }

    lazy var pipeline: ImagePipeline = {
        let dataCache: DataCache? = try? DataCache(name: Constants.dataCacheName)
        dataCache?.sizeLimit = Constants.diskLimitBytes
        if let dataCache: DataCache = dataCache {
            Self.trimIfNeeded(dataCache: dataCache)
        }

        let imageCache: ImageCache = ImageCache(
            costLimit: Constants.memoryLimitBytes,
            countLimit: 600
        )

        var configuration: ImagePipeline.Configuration = .withDataCache
        configuration.dataCache = dataCache
        configuration.imageCache = imageCache
        return ImagePipeline(configuration: configuration, delegate: self)
    }()

    private init() {}

    /// 中文注释：缩略图的磁盘缓存，供缓存页算用量与清除。
    var dataCache: DataCache? {
        return self.pipeline.configuration.dataCache as? DataCache
    }

    /// 中文注释：清掉缩略图的内存缓存；磁盘部分由调用方经 `dataCache` 清并等待完成。
    func removeAllFromMemory() {
        self.pipeline.cache.removeAll(caches: .memory)
    }

    // 中文注释：这里有意不实现 `ImagePipelineDelegate.cacheKey(for:pipeline:)`。Nuke 对自定义键会同时用作内存键与磁盘键，
    // 且不再拼 `thumbnail.identifier`——同一封面在库页大格与历史行小格就会互相串用解码结果（2026-10-10 复审 B-1）。
    // 只把 `cacheKey(url:request:)` 放进 `userInfo[.imageIdKey]`（见 `thumbnailRequest(from:)`），内存键与磁盘键仍由 Nuke
    // 按「imageId + 解码尺寸 + processors」组装，按尺寸各存一份。

    /// 中文注释：图片身份：去掉 fragment 的地址 + Accept + Cookie 名集合。Referer 不进键（同一张图被多个详情页引用）；
    /// Cookie 只看名字——值进键的话站点会话 Cookie 一轮换，该站全部缩略图的内存与磁盘缓存一起失效。
    static func cacheKey(
        url: URL,
        request: URLRequest?
    ) -> String {
        let urlKey: String = Self.normalizedURLKey(url)
        let acceptHeader: String = Self.normalizedHeader(
            request?.value(forHTTPHeaderField: "Accept")
        )
        let cookieNames: String = Self.normalizedCookieNames(
            request?.value(forHTTPHeaderField: "Cookie")
        )
        return [
            Constants.cacheKeyPrefix,
            urlKey,
            "accept=\(acceptHeader)",
            "cookie=\(cookieNames)"
        ].joined(separator: "|")
    }

    func thumbnailRequest(from request: ImageRequest) -> ImageRequest {
        return Self.thumbnailRequest(from: request)
    }

    static func thumbnailRequest(
        from request: ImageRequest
    ) -> ImageRequest {
        guard let url: URL = request.url else {
            return request
        }

        var thumbnailRequest: ImageRequest = request
        var userInfo: [ImageRequest.UserInfoKey: Any] = thumbnailRequest.userInfo
        userInfo[.imageIdKey] = Self.cacheKey(
            url: url,
            request: request.urlRequest
        )
        thumbnailRequest.userInfo = userInfo
        thumbnailRequest.priority = .low
        return thumbnailRequest
    }

    private static func normalizedURLKey(_ url: URL) -> String {
        guard var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        components.fragment = nil
        return (components.url?.absoluteString ?? url.absoluteString)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private static func normalizedHeader(_ value: String?) -> String {
        return value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    /// 中文注释：`a=1; b=2` → `a,b`（排序去重、小写）；没有 Cookie 头为空串。
    private static func normalizedCookieNames(_ value: String?) -> String {
        guard let value: String = value else {
            return ""
        }
        let names: Set<String> = Set(
            value.split(separator: ";").compactMap { pair in
                let name: Substring = pair.split(separator: "=", maxSplits: 1).first ?? ""
                let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        return names.sorted().joined(separator: ",")
    }

    private static func trimIfNeeded(dataCache: DataCache) {
        dataCache.flush()
        dataCache.queue.async {
            let entries: [ItemThumbnailCacheDiskEntry] = Self.diskEntries(in: dataCache.path)
            var totalBytes: Int = entries.reduce(0) { partialResult, entry in
                return partialResult + entry.allocatedBytes
            }

            guard totalBytes > Constants.diskLimitBytes else {
                return
            }

            let targetBytes: Int = Int(Double(Constants.diskLimitBytes) * 0.75)
            var removableEntries: [ItemThumbnailCacheDiskEntry] = entries.sorted { lhs, rhs in
                return lhs.lastAccessDate > rhs.lastAccessDate
            }

            while totalBytes > targetBytes,
                  let entry: ItemThumbnailCacheDiskEntry = removableEntries.popLast() {
                try? FileManager.default.removeItem(at: entry.url)
                totalBytes -= entry.allocatedBytes
            }
        }
    }

    private static func diskEntries(in cachePath: URL) -> [ItemThumbnailCacheDiskEntry] {
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

            return ItemThumbnailCacheDiskEntry(
                url: url,
                allocatedBytes: values.totalFileAllocatedSize ?? values.fileSize ?? 0,
                lastAccessDate: values.contentAccessDate ?? Date.distantPast
            )
        }
    }
}

private struct ItemThumbnailCacheDiskEntry {
    let url: URL
    let allocatedBytes: Int
    let lastAccessDate: Date
}
