import Foundation
import BrowseCraftCore

// 中文注释：VideoHTMLMapper 是视频站模板映射策略协议；MacCMS 只是当前第一个实现。
protocol VideoHTMLMapper {
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
