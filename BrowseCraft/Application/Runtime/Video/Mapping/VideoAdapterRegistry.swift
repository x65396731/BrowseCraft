import Foundation
import BrowseCraftCore

// 中文注释：VideoAdapterRegistry 只负责 adapter 到 mapper 的执行分发，不负责检测站点类型。
struct VideoAdapterRegistry {
    func mapper(for adapter: VideoAdapter?) -> any VideoHTMLMapper {
        switch adapter {
        case .macCMS, nil:
            return MacCMSVideoHTMLMapper()
        case .genericHTML:
            return GenericHTMLVideoHTMLMapper()
        case .webView:
            return UnsupportedVideoHTMLMapper(adapter: .webView)
        case .plugin:
            return UnsupportedVideoHTMLMapper(adapter: .plugin)
        }
    }
}

struct UnsupportedVideoHTMLMapper: VideoHTMLMapper {
    let adapter: VideoAdapter

    func mapList(
        html: String,
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem] {
        throw self.unsupportedError()
    }

    func mapDetail(
        html: String,
        definition: SourceDefinition,
        detailURL: URL
    ) throws -> VideoDetailContent {
        throw self.unsupportedError()
    }

    func mapPlayback(
        html: String,
        definition: SourceDefinition,
        playPageURL: URL
    ) throws -> SourceVideoPlaybackReference {
        throw self.unsupportedError()
    }

    private func unsupportedError() -> SourceRuntimeError {
        let message: String
        switch self.adapter {
        case .webView:
            message = "Video WebView rendering adapter is not connected yet."
        case .plugin:
            message = "This video source requires the Plugin module, but PluginSourceRuntime is not connected yet."
        case .macCMS, .genericHTML:
            message = "Video adapter \(self.adapter.rawValue) is not connected yet."
        }

        return SourceRuntimeError.unsupported(
            .custom(message)
        )
    }
}
