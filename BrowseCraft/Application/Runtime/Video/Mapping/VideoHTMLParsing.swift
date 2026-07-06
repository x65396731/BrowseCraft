import Foundation
import BrowseCraftCore

// 中文注释：VideoDetailContent 是 video detail loader 的内部映射结果，UI 只读取必要字段。
struct VideoDetailContent {
    var chapters: [SourceChapter]
    var synopsis: String?
    var metadataRows: [String]
}

// 中文注释：VideoHTMLParsing 是视频站模板解析策略协议；MacCMS 只是当前第一个实现。
protocol VideoHTMLParsing {
    func parseList(
        html: String,
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem]

    func parseDetail(
        html: String,
        definition: SourceDefinition,
        detailURL: URL
    ) throws -> VideoDetailContent

    func parsePlayback(
        html: String,
        definition: SourceDefinition,
        playPageURL: URL
    ) throws -> SourceVideoPlaybackReference
}
