import Foundation
import BrowseCraftCore

typealias HTMLDiscoveryAncestorSnapshot = BrowseCraftCore.SourceDiscoveryAncestorSnapshot
typealias HTMLDiscoveryAnchorSnapshot = BrowseCraftCore.SourceDiscoveryAnchorSnapshot

/// 中文注释：仅把 HTML 转成 Discovery 用快照，不向 Application 暴露 DOM 查询能力。
protocol HTMLDiscoveryParsingService {
    func parseAnchors(html: String, pageURL: URL) throws -> [HTMLDiscoveryAnchorSnapshot]
}
