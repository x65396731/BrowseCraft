import Foundation
import BrowseCraftCore

// 中文注释：VideoPlaybackRuntimeCapability 是视频播放入口使用的 runtime 能力协议，不代表第二个 runtime。
protocol VideoPlaybackRuntimeCapability: SourceRuntime {
    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput
}

extension VideoRuleSourceRuntime: VideoPlaybackRuntimeCapability {}
