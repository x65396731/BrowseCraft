import Foundation
import BrowseCraftCore

// 中文注释：VideoContentMapperRegistry 只按内容结构选择 mapper；WebView 是渲染方式，不是内容 mapper。
struct VideoContentMapperRegistry {
    func mapper(for definition: SourceDefinition) -> any VideoContentMapper {
        if self.shouldUseMacCMSCompatibilityMapper(definition) {
            return MacCMSVideoContentMapper()
        }
        return self.mapper(for: definition.video?.adapter)
    }

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

    private func shouldUseMacCMSCompatibilityMapper(_ definition: SourceDefinition) -> Bool {
        guard definition.video?.adapter == .genericHTML else {
            return false
        }

        let sourceID: String = definition.id.lowercased()
        let host: String = definition.baseURL.host?.lowercased() ?? ""
        return sourceID == "kpkuang"
            && (host == "kpkuang.fun" || host == "www.kpkuang.fun")
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
