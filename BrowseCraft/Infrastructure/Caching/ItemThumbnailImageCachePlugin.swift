import Foundation
import Nuke

// 中文注释：ItemThumbnailImageCachePlugin 为 Library item 缩略图提供独立于漫画阅读图的缓存池。
final class ItemThumbnailImageCachePlugin: ImagePipelineDelegate {
    static let shared: ItemThumbnailImageCachePlugin = ItemThumbnailImageCachePlugin()

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

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        guard let url: URL = request.url else {
            return nil
        }

        return Self.cacheKey(
            url: url,
            request: request.urlRequest
        )
    }

    static func cacheKey(
        url: URL,
        request: URLRequest?
    ) -> String {
        let urlKey: String = Self.normalizedURLKey(url)
        let acceptHeader: String = Self.normalizedHeader(
            request?.value(forHTTPHeaderField: "Accept")
        )
        let cookieHeader: String = Self.normalizedHeader(
            request?.value(forHTTPHeaderField: "Cookie")
        )
        return [
            Constants.cacheKeyPrefix,
            urlKey,
            "accept=\(acceptHeader)",
            "cookie=\(cookieHeader)"
        ].joined(separator: "|")
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
