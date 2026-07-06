import Foundation
import BrowseCraftCore

// 中文注释：VideoPlayableSourceRuntime 是 P4.13.4 播放入口使用的应用层桥接协议。
protocol VideoPlayableSourceRuntime: SourceRuntime {
    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput
    func loadVideoDetailContent(_ input: SourceDetailInput) async throws -> VideoDetailContent
}

extension VideoSourceRuntime: VideoPlayableSourceRuntime {}
