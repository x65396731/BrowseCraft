import Foundation
import BrowseCraftCore

// 中文注释：VideoContentMapperRegistry 只按内容结构选择 mapper；WebView 是渲染方式，不是内容 mapper。
struct VideoContentMapperRegistry {
    func mapper(for adapter: VideoAdapter?) -> any VideoContentMapper {
        switch adapter {
        case .macCMS, nil:
            return MacCMSVideoContentMapper()
        case .genericHTML, .webView:
            return GenericHTMLVideoContentMapper()
        case .plugin:
            return PluginRequiredVideoContentMapper()
        }
    }
}

struct PluginRequiredVideoContentMapper: VideoContentMapper {
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
        return SourceRuntimeError.unsupported(
            .custom("This video source requires the Plugin module, but PluginSourceRuntime is not connected yet.")
        )
    }
}
