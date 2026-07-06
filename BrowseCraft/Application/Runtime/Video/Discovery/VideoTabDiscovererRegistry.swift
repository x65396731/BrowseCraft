import Foundation
import BrowseCraftCore

// 中文注释：VideoTabDiscovererRegistry 只负责 adapter 到 tab discovery 策略的分发。
struct VideoTabDiscovererRegistry {
    func discoverer(for adapter: VideoAdapter?) -> any VideoTabDiscovering {
        switch adapter {
        case .macCMS, nil:
            return MacCMSVideoTabDiscoverer()
        case .genericHTML:
            return GenericHTMLVideoTabDiscoverer()
        case .iframe, .webView, .plugin:
            return FallbackVideoTabDiscoverer()
        }
    }
}
