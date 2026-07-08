import Foundation
import BrowseCraftCore

// 中文注释：VideoTabDiscovererRegistry 只按内容结构选择 tab discovery；WebView 是渲染方式。
struct VideoTabDiscovererRegistry {
    func discoverer(for adapter: VideoAdapter?) -> any VideoTabDiscovering {
        switch adapter {
        case .macCMS, nil:
            return MacCMSVideoTabDiscoverer()
        case .genericHTML, .webView:
            return GenericHTMLVideoTabDiscoverer()
        case .plugin:
            return FallbackVideoTabDiscoverer()
        }
    }
}
