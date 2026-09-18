import Nuke
import SwiftUI

// 中文注释：Library / History 缩略图用独立于漫画阅读图的缓存池。池子与请求改写都带 Nuke 类型，
// 因此进不了 Application 端口（Application 禁止 import Nuke）；按本层既有的请求头 provider 同一模式
// 经 Environment 注入，由装配根提供实现，视图不再直接取 Infrastructure 的单例。
// （2026-09-18 收敛边界豁免时引入。）

/// 中文注释：缩略图专用图片管线。`thumbnailRequest(from:)` 负责把请求改写成该池的缓存键与优先级。
protocol ItemThumbnailImagePipelineProviding: Sendable {
    var pipeline: ImagePipeline { get }
    func thumbnailRequest(from request: ImageRequest) -> ImageRequest
}

/// 中文注释：默认实现——不分池，直接用共享管线、请求原样返回。预览与未装配的场景走这条。
struct SharedItemThumbnailImagePipelineProvider: ItemThumbnailImagePipelineProviding {
    var pipeline: ImagePipeline {
        return ImagePipeline.shared
    }

    func thumbnailRequest(from request: ImageRequest) -> ImageRequest {
        return request
    }
}

private struct ItemThumbnailImagePipelineEnvironmentKey: EnvironmentKey {
    static let defaultValue: any ItemThumbnailImagePipelineProviding = SharedItemThumbnailImagePipelineProvider()
}

extension EnvironmentValues {
    var itemThumbnailImagePipeline: any ItemThumbnailImagePipelineProviding {
        get { self[ItemThumbnailImagePipelineEnvironmentKey.self] }
        set { self[ItemThumbnailImagePipelineEnvironmentKey.self] = newValue }
    }
}
