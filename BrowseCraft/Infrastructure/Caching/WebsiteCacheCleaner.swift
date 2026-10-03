import WebKit

// 中文注释：缓存页「清除缓存」里网页那一部分（`docs/design/Cache-Page-Redesign-Design.md` 5.1）。
// 只清 WebKit 的缓存类数据；Cookie、localStorage / sessionStorage 里是来源登录状态，属于用户数据，不清。
enum WebsiteCacheCleaner {
    @MainActor
    static func removeCachedResources() async {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache
        ]
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
    }
}
