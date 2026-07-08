import Foundation
import BrowseCraftCore

// 中文注释：VideoContentMapper 只负责把已经取得的 HTML/DOM 映射成视频内容，不负责请求、WebView 或插件执行。
protocol VideoContentMapper {
    func mapList(
        html: String,
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem]

    func mapDetail(
        html: String,
        definition: SourceDefinition,
        detailURL: URL
    ) throws -> VideoDetailContent

    func mapPlayback(
        html: String,
        definition: SourceDefinition,
        playPageURL: URL
    ) throws -> SourceVideoPlaybackReference
}
