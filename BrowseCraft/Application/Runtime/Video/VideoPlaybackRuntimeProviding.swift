import Foundation
import BrowseCraftCore

// 中文注释：VideoPlaybackRuntimeProviding 是播放入口使用的 video-only 能力协议，不代表第二个 runtime。
protocol VideoPlaybackRuntimeProviding: SourceRuntime {
    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput
    func loadVideoDetailContent(_ input: SourceDetailInput) async throws -> VideoDetailContent
}

extension VideoSourceRuntime: VideoPlaybackRuntimeProviding {}
